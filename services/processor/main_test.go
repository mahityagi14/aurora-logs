package main

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestSlowQueryParser(t *testing.T) {
	parser := parseSlowQueryLog
	
	tests := []struct {
		name     string
		line     string
		expected ParsedLogEntry
	}{
		{
			name: "parse time line",
			line: "# Time: 2024-01-15T10:30:45.123456Z",
			expected: ParsedLogEntry{
				"timestamp": "2024-01-15T10:30:45.123456Z",
			},
		},
		{
			name: "parse user host line",
			line: "# User@Host: admin[admin] @ [10.0.0.1]",
			expected: ParsedLogEntry{
				"user_host": "admin[admin] @ [10.0.0.1]",
			},
		},
		{
			name: "parse query time line",
			line: "# Query_time: 5.234567  Lock_time: 0.123456 Rows_sent: 10  Rows_examined: 1000",
			expected: ParsedLogEntry{
				"query_time":    "5.234567",
				"lock_time":     "0.123456",
				"rows_sent":     "10",
				"rows_examined": "1000",
			},
		},
		{
			name: "sql line",
			line: "SELECT * FROM users",
			expected: ParsedLogEntry{
				"sql": "SELECT * FROM users",
			},
		},
		{
			name:     "comment line",
			line:     "# Some comment",
			expected: nil,
		},
		{
			name:     "empty line",
			line:     "",
			expected: nil,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := parser(tt.line)
			if tt.expected == nil {
				assert.Nil(t, result)
			} else {
				assert.NotNil(t, result)
				for key, expectedValue := range tt.expected {
					actualValue, exists := result[key]
					assert.True(t, exists, "Key %s should exist", key)
					assert.Equal(t, expectedValue, actualValue)
				}
			}
		})
	}
}

func TestLogMessage_Marshal(t *testing.T) {
	msg := LogMessage{
		InstanceID:  "test-instance",
		LogFileName: "error.log",
		LogType:     "error",
		LastWritten: 1234567890,
		Size:        1024,
	}
	
	data, err := json.Marshal(msg)
	assert.NoError(t, err)
	assert.NotEmpty(t, data)
	
	var decoded LogMessage
	err = json.Unmarshal(data, &decoded)
	assert.NoError(t, err)
	assert.Equal(t, msg.InstanceID, decoded.InstanceID)
	assert.Equal(t, msg.LogFileName, decoded.LogFileName)
}

func TestConfig_GetEnvAsInt(t *testing.T) {
	tests := []struct {
		name     string
		key      string
		envValue string
		default_ int
		expected int
	}{
		{
			name:     "returns int value when valid",
			key:      "TEST_INT_VAR",
			envValue: "42",
			default_: 10,
			expected: 42,
		},
		{
			name:     "returns default when env not set",
			key:      "UNSET_INT_VAR",
			envValue: "",
			default_: 10,
			expected: 10,
		},
		{
			name:     "returns default when env not a valid int",
			key:      "INVALID_INT_VAR",
			envValue: "not-a-number",
			default_: 10,
			expected: 10,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.envValue != "" {
				t.Setenv(tt.key, tt.envValue)
			}
			result := getEnvAsInt(tt.key, tt.default_)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestCircuitBreaker(t *testing.T) {
	t.Run("allows calls when closed", func(t *testing.T) {
		cb := NewCircuitBreaker(3, 5*time.Second)
		err := cb.Call(func() error {
			return nil
		})
		assert.NoError(t, err)
	})

	t.Run("opens after max failures", func(t *testing.T) {
		cb := NewCircuitBreaker(2, 5*time.Second)
		
		// First two failures
		for i := 0; i < 2; i++ {
			err := cb.Call(func() error {
				return errors.New("test error")
			})
			assert.Error(t, err)
		}
		
		// Circuit should now be open
		err := cb.Call(func() error {
			return nil
		})
		assert.Error(t, err)
		assert.Equal(t, "circuit breaker is open", err.Error())
	})

	t.Run("half-open state after timeout", func(t *testing.T) {
		cb := NewCircuitBreaker(1, 100*time.Millisecond)
		
		// Trigger open state
		_ = cb.Call(func() error {
			return errors.New("test error")
		})
		
		// Wait for reset timeout
		time.Sleep(150 * time.Millisecond)
		
		// Should allow call in half-open state
		err := cb.Call(func() error {
			return nil
		})
		assert.NoError(t, err)
	})
}

func TestHTTPConnectionPool(t *testing.T) {
	pool := NewHTTPConnectionPool(3, 5*time.Second)
	
	// Get all clients from pool
	clients := make([]*http.Client, 3)
	for i := 0; i < 3; i++ {
		clients[i] = pool.Get()
		assert.NotNil(t, clients[i])
	}
	
	// Return clients to pool
	for _, client := range clients {
		pool.Put(client)
	}
	
	// Verify we can get them again
	client := pool.Get()
	assert.NotNil(t, client)
	pool.Put(client)
}

func TestBatchProcessing(t *testing.T) {
	t.Run("batch collector groups items", func(t *testing.T) {
		// This tests the batch grouping logic
		batch := []BatchItem{
			{LogMsg: LogMessage{InstanceID: "inst1", LogType: "error"}},
			{LogMsg: LogMessage{InstanceID: "inst2", LogType: "error"}},
			{LogMsg: LogMessage{InstanceID: "inst1", LogType: "slowquery"}},
		}
		
		grouped := make(map[string][]BatchItem)
		for _, item := range batch {
			key := item.LogMsg.InstanceID
			grouped[key] = append(grouped[key], item)
		}
		
		assert.Equal(t, 2, len(grouped))
		assert.Equal(t, 2, len(grouped["inst1"]))
		assert.Equal(t, 1, len(grouped["inst2"]))
	})
}

func TestStreamingDownload(t *testing.T) {
	t.Run("pipe reader writer basics", func(t *testing.T) {
		pr, pw := io.Pipe()
		
		go func() {
			defer func() { _ = pw.Close() }()
			_, _ = pw.Write([]byte("test data\n"))
			_, _ = pw.Write([]byte("more data\n"))
		}()
		
		data, err := io.ReadAll(pr)
		assert.NoError(t, err)
		assert.Equal(t, "test data\nmore data\n", string(data))
	})
}

func TestBufferAndGzipPools(t *testing.T) {
	t.Run("buffer pool reuse", func(t *testing.T) {
		buf1 := bufferPool.Get().(*bytes.Buffer)
		buf1.WriteString("test")
		buf1.Reset()
		bufferPool.Put(buf1)
		
		buf2 := bufferPool.Get().(*bytes.Buffer)
		assert.Equal(t, 0, buf2.Len())
		bufferPool.Put(buf2)
	})
	
	t.Run("gzip writer pool reuse", func(t *testing.T) {
		gz1 := gzipWriterPool.Get().(*gzip.Writer)
		var buf bytes.Buffer
		gz1.Reset(&buf)
		_, _ = gz1.Write([]byte("test data"))
		_ = gz1.Close()
		
		assert.Greater(t, buf.Len(), 0)
		
		gz1.Reset(nil)
		gzipWriterPool.Put(gz1)
	})
}

func TestErrorLogParser(t *testing.T) {
	tests := []struct {
		name     string
		line     string
		expected ParsedLogEntry
	}{
		{
			name: "parse error log line",
			line: "2024-01-15 10:30:45 [ERROR] Connection failed",
			expected: ParsedLogEntry{
				"timestamp": "2024-01-15 10:30:45",
				"level":     "ERROR",
				"message":   "[ERROR] Connection failed",
			},
		},
		{
			name:     "invalid line",
			line:     "invalid",
			expected: nil,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := parseErrorLog(tt.line)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestMetricsExporter(t *testing.T) {
	metrics := NewMetricsExporter("http://localhost:5080", "user", "pass")
	
	t.Run("increment counter", func(t *testing.T) {
		metrics.IncrementCounter("test_counter", 5)
		metrics.mu.RLock()
		value := metrics.counters["test_counter"]
		metrics.mu.RUnlock()
		assert.Equal(t, int64(5), value)
	})
	
	t.Run("record error", func(t *testing.T) {
		metrics.RecordError("processor", "timeout")
		metrics.mu.RLock()
		value := metrics.counters["processor_timeout_errors"]
		metrics.mu.RUnlock()
		assert.Equal(t, int64(1), value)
	})
}

func TestDataIntegrityChecker(t *testing.T) {
	metrics := NewMetricsExporter("", "", "")
	checker := NewDataIntegrityChecker(metrics)
	
	checker.VerifyAndRecord("error", "test.log", 100, 100)
	metrics.mu.RLock()
	mismatches := metrics.counters["data_integrity_mismatches"]
	metrics.mu.RUnlock()
	assert.Equal(t, int64(0), mismatches)
	
	checker.VerifyAndRecord("error", "test.log", 90, 100)
	metrics.mu.RLock()
	mismatches = metrics.counters["data_integrity_mismatches"]
	metrics.mu.RUnlock()
	assert.Equal(t, int64(1), mismatches)
}

func TestParserSelection(t *testing.T) {
	bp := &BatchProcessor{}
	
	t.Run("error log parser", func(t *testing.T) {
		parser := bp.getParser("error")
		assert.NotNil(t, parser)
		// Test it returns the error parser
		result := parser("2024-01-15 10:30:45 [ERROR] test")
		assert.NotNil(t, result)
	})
	
	t.Run("slowquery parser", func(t *testing.T) {
		parser := bp.getParser("slowquery")
		assert.NotNil(t, parser)
		// Test it returns the slowquery parser
		result := parser("# Time: 2024-01-15T10:30:45Z")
		assert.NotNil(t, result)
		assert.Equal(t, "2024-01-15T10:30:45Z", result["timestamp"])
	})
	
	t.Run("generic parser", func(t *testing.T) {
		parser := bp.getParser("unknown")
		assert.NotNil(t, parser)
		result := parser("some line")
		assert.NotNil(t, result)
		assert.Equal(t, "some line", result["line"])
	})
}