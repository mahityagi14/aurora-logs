package tests

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Performance benchmarks for Aurora Log System

// BenchmarkLogProcessing tests throughput of log processing
func BenchmarkLogProcessing(b *testing.B) {
	scenarios := []struct {
		name      string
		logSize   int    // Size of each log entry in bytes
		batchSize int    // Number of logs per batch
		workers   int    // Number of concurrent workers
	}{
		{"Small-Serial", 1024, 100, 1},
		{"Small-Parallel", 1024, 100, 10},
		{"Medium-Serial", 10240, 100, 1},
		{"Medium-Parallel", 10240, 100, 10},
		{"Large-Serial", 102400, 10, 1},
		{"Large-Parallel", 102400, 10, 10},
		{"Extreme-Parallel", 1024, 1000, 50},
	}

	for _, scenario := range scenarios {
		b.Run(scenario.name, func(b *testing.B) {
			// Setup
			ctx := context.Background()
			processor := setupTestProcessor(scenario.workers)
			
			// Generate test data
			testLogs := generateTestLogs(scenario.logSize, scenario.batchSize)
			
			b.ResetTimer()
			b.SetBytes(int64(scenario.logSize * scenario.batchSize))
			
			// Run benchmark
			for i := 0; i < b.N; i++ {
				err := processor.ProcessBatch(ctx, testLogs)
				if err != nil {
					b.Fatal(err)
				}
			}
			
			// Report metrics
			b.ReportMetric(float64(scenario.batchSize*b.N)/b.Elapsed().Seconds(), "logs/sec")
			b.ReportMetric(float64(scenario.logSize*scenario.batchSize*b.N)/(1024*1024)/b.Elapsed().Seconds(), "MB/sec")
		})
	}
}

// BenchmarkRDSAPIWithCache benchmarks RDS API calls with Valkey caching
func BenchmarkRDSAPIWithCache(b *testing.B) {
	ctx := context.Background()
	
	// Setup cache
	cache := setupTestCache()
	limiter := setupRateLimiter(1000) // 1000 RPS
	
	b.Run("Without-Cache", func(b *testing.B) {
		var apiCalls int64
		b.ResetTimer()
		
		b.RunParallel(func(pb *testing.PB) {
			for pb.Next() {
				// Simulate RDS API call
				limiter.Wait(ctx)
				atomic.AddInt64(&apiCalls, 1)
				time.Sleep(10 * time.Millisecond) // Simulate API latency
			}
		})
		
		b.ReportMetric(float64(apiCalls)/b.Elapsed().Seconds(), "api_calls/sec")
	})
	
	b.Run("With-Cache", func(b *testing.B) {
		var apiCalls int64
		var cacheHits int64
		b.ResetTimer()
		
		b.RunParallel(func(pb *testing.PB) {
			i := 0
			for pb.Next() {
				key := fmt.Sprintf("cluster:%d", i%100) // 100 unique clusters
				
				// Check cache first
				if cached, found := cache.Get(key); found {
					atomic.AddInt64(&cacheHits, 1)
					_ = cached
				} else {
					// Cache miss - make API call
					limiter.Wait(ctx)
					atomic.AddInt64(&apiCalls, 1)
					time.Sleep(10 * time.Millisecond)
					
					// Store in cache
					cache.Set(key, "data", 5*time.Minute)
				}
				i++
			}
		})
		
		hitRate := float64(cacheHits) / float64(b.N) * 100
		b.ReportMetric(hitRate, "cache_hit_rate_%")
		b.ReportMetric(float64(apiCalls)/b.Elapsed().Seconds(), "api_calls/sec")
	})
}

// BenchmarkConcurrentProcessing tests system under high concurrency
func BenchmarkConcurrentProcessing(b *testing.B) {
	concurrencyLevels := []int{1, 10, 50, 100, 316} // 316 = number of RDS instances
	
	for _, concurrency := range concurrencyLevels {
		b.Run(fmt.Sprintf("Concurrency-%d", concurrency), func(b *testing.B) {
			ctx := context.Background()
			processor := setupTestProcessor(concurrency)
			
			b.ResetTimer()
			
			var wg sync.WaitGroup
			errors := make(chan error, concurrency)
			
			for i := 0; i < concurrency; i++ {
				wg.Add(1)
				go func(workerID int) {
					defer wg.Done()
					
					logsPerWorker := b.N / concurrency
					for j := 0; j < logsPerWorker; j++ {
						logs := generateTestLogs(1024, 100)
						if err := processor.ProcessBatch(ctx, logs); err != nil {
							errors <- err
							return
						}
					}
				}(i)
			}
			
			wg.Wait()
			close(errors)
			
			// Check for errors
			for err := range errors {
				b.Fatal(err)
			}
			
			b.ReportMetric(float64(concurrency), "concurrent_workers")
		})
	}
}

// BenchmarkMemoryUsage tests memory efficiency
func BenchmarkMemoryUsage(b *testing.B) {
	scenarios := []struct {
		name      string
		batchSize int
		logSize   int
	}{
		{"Small-Batch", 100, 1024},
		{"Medium-Batch", 1000, 1024},
		{"Large-Batch", 10000, 1024},
		{"Huge-Logs", 100, 1048576}, // 1MB logs
	}
	
	for _, scenario := range scenarios {
		b.Run(scenario.name, func(b *testing.B) {
			ctx := context.Background()
			processor := setupTestProcessor(1)
			
			// Force GC before measurement
			runtime.GC()
			var m1 runtime.MemStats
			runtime.ReadMemStats(&m1)
			
			b.ResetTimer()
			
			for i := 0; i < b.N; i++ {
				logs := generateTestLogs(scenario.logSize, scenario.batchSize)
				err := processor.ProcessBatch(ctx, logs)
				require.NoError(b, err)
			}
			
			// Measure memory after
			runtime.GC()
			var m2 runtime.MemStats
			runtime.ReadMemStats(&m2)
			
			memUsed := m2.Alloc - m1.Alloc
			b.ReportMetric(float64(memUsed)/(1024*1024), "MB_allocated")
			b.ReportMetric(float64(memUsed)/float64(b.N), "bytes/operation")
		})
	}
}

// BenchmarkCompressionRatio tests compression efficiency
func BenchmarkCompressionRatio(b *testing.B) {
	logTypes := []struct {
		name    string
		pattern string // Log pattern
	}{
		{"Error-Logs", "2024-01-01 ERROR [main] Database connection failed: %s"},
		{"Slow-Query", "# Query_time: %.2f Lock_time: %.2f Rows_sent: %d\nSELECT * FROM users WHERE id = %d"},
		{"JSON-Logs", `{"timestamp":"%s","level":"ERROR","message":"%s","instance_id":"%s"}`},
		{"Repetitive", "ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR"},
	}
	
	for _, logType := range logTypes {
		b.Run(logType.name, func(b *testing.B) {
			// Generate test data
			var totalUncompressed int64
			var totalCompressed int64
			
			b.ResetTimer()
			
			for i := 0; i < b.N; i++ {
				// Generate log batch
				logs := make([]string, 1000)
				for j := 0; j < 1000; j++ {
					logs[j] = fmt.Sprintf(logType.pattern, 
						generateRandomString(20),
						generateRandomFloat(),
						j,
						j)
				}
				
				// Measure compression
				uncompressed := 0
				for _, log := range logs {
					uncompressed += len(log)
				}
				
				compressed := compressLogs(logs)
				
				atomic.AddInt64(&totalUncompressed, int64(uncompressed))
				atomic.AddInt64(&totalCompressed, int64(len(compressed)))
			}
			
			ratio := float64(totalUncompressed) / float64(totalCompressed)
			b.ReportMetric(ratio, "compression_ratio")
			b.ReportMetric(float64(totalCompressed)/float64(totalUncompressed)*100, "compressed_size_%")
		})
	}
}

// TestSystemLimits tests the system under extreme conditions
func TestSystemLimits(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping stress test in short mode")
	}
	
	tests := []struct {
		name           string
		instances      int
		logsPerInstance int
		duration       time.Duration
		expectedRate   float64 // logs/sec
	}{
		{"Normal-Load", 10, 100, 10 * time.Second, 100},
		{"High-Load", 50, 1000, 30 * time.Second, 1000},
		{"Peak-Load", 316, 1000, 60 * time.Second, 5000},
		{"Sustained-Load", 100, 10000, 5 * time.Minute, 2000},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), tt.duration)
			defer cancel()
			
			// Setup
			processor := setupTestProcessor(50) // 50 workers
			
			// Generate load
			start := time.Now()
			var processed int64
			var errors int64
			
			var wg sync.WaitGroup
			for i := 0; i < tt.instances; i++ {
				wg.Add(1)
				go func(instanceID int) {
					defer wg.Done()
					
					for j := 0; j < tt.logsPerInstance; j++ {
						select {
						case <-ctx.Done():
							return
						default:
							logs := generateInstanceLogs(instanceID, 100)
							if err := processor.ProcessBatch(ctx, logs); err != nil {
								atomic.AddInt64(&errors, 1)
							} else {
								atomic.AddInt64(&processed, 100)
							}
						}
					}
				}(i)
			}
			
			wg.Wait()
			elapsed := time.Since(start)
			
			// Verify results
			rate := float64(processed) / elapsed.Seconds()
			errorRate := float64(errors) / float64(processed) * 100
			
			t.Logf("Processed %d logs in %v (%.2f logs/sec)", processed, elapsed, rate)
			t.Logf("Error rate: %.2f%%", errorRate)
			
			// Assertions
			assert.True(t, rate >= tt.expectedRate*0.8, "Processing rate too low")
			assert.True(t, errorRate < 1.0, "Error rate too high")
		})
	}
}

// TestCostEfficiency verifies cost optimization targets
func TestCostEfficiency(t *testing.T) {
	// Simulate resource usage
	scenarios := []struct {
		name         string
		instances    int
		dataGB       float64
		expectedCost float64 // USD per month
	}{
		{"POC-Load", 1, 10, 150},
		{"Small-Production", 50, 100, 1000},
		{"Medium-Production", 150, 500, 2500},
		{"Full-Production", 316, 6670, 4500}, // Target: under $4500
	}
	
	for _, scenario := range scenarios {
		t.Run(scenario.name, func(t *testing.T) {
			// Calculate actual costs based on resources
			cost := calculateMonthlyCost(scenario.instances, scenario.dataGB)
			
			t.Logf("Scenario %s: $%.2f/month (target: $%.2f)", 
				scenario.name, cost, scenario.expectedCost)
			
			// Verify cost is within budget
			assert.LessOrEqual(t, cost, scenario.expectedCost*1.1, 
				"Cost exceeds budget by more than 10%")
		})
	}
}

// Helper functions for tests

type TestProcessor struct {
	workers int
	limiter *rate.Limiter
}

func setupTestProcessor(workers int) *TestProcessor {
	return &TestProcessor{
		workers: workers,
		limiter: rate.NewLimiter(rate.Limit(1000), 1000), // 1000 RPS
	}
}

func (p *TestProcessor) ProcessBatch(ctx context.Context, logs []interface{}) error {
	// Simulate processing
	time.Sleep(time.Millisecond * time.Duration(len(logs)/10))
	return nil
}

func generateTestLogs(size, count int) []interface{} {
	logs := make([]interface{}, count)
	for i := 0; i < count; i++ {
		logs[i] = generateRandomBytes(size)
	}
	return logs
}

func generateInstanceLogs(instanceID, count int) []interface{} {
	logs := make([]interface{}, count)
	for i := 0; i < count; i++ {
		logs[i] = map[string]interface{}{
			"instance_id": fmt.Sprintf("instance-%d", instanceID),
			"log_type":    "error",
			"timestamp":   time.Now().Unix(),
			"message":     generateRandomString(100),
		}
	}
	return logs
}

func calculateMonthlyCost(instances int, dataGB float64) float64 {
	// Simplified cost calculation
	computeCost := float64(instances) * 0.5 * 730  // $0.5/hour per instance
	storageCost := dataGB * 0.023                  // S3 standard
	transferCost := dataGB * 0.01                  // Minimal transfer
	kafkaCost := 200.0                             // Fixed Kafka cost
	
	return computeCost + storageCost + transferCost + kafkaCost
}