package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	dynamoTypes "github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/rds"
	"github.com/segmentio/kafka-go"
	"net"
)

// Configuration helpers
func getEnvOrDefault(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func getEnvAsInt(key string, defaultVal int) int {
	if val := os.Getenv(key); val != "" {
		if intVal, err := strconv.Atoi(val); err == nil {
			return intVal
		}
	}
	return defaultVal
}


// Circuit Breaker implementation
type CircuitBreaker struct {
	maxFailures     int
	resetTimeout    time.Duration
	failures        atomic.Int32
	lastFailureTime atomic.Int64
	state           atomic.Int32 // 0=closed, 1=open, 2=half-open
}

func NewCircuitBreaker(maxFailures int, resetTimeout time.Duration) *CircuitBreaker {
	return &CircuitBreaker{
		maxFailures:  maxFailures,
		resetTimeout: resetTimeout,
	}
}

func (cb *CircuitBreaker) Call(fn func() error) error {
	if !cb.canExecute() {
		return errors.New("circuit breaker is open")
	}

	err := fn()
	if err != nil {
		cb.recordFailure()
	} else {
		cb.recordSuccess()
	}

	return err
}

func (cb *CircuitBreaker) canExecute() bool {
	state := cb.state.Load()
	
	switch state {
	case 0: // closed
		return true
	case 1: // open
		lastFailure := time.Unix(0, cb.lastFailureTime.Load())
		if time.Since(lastFailure) > cb.resetTimeout {
			cb.state.CompareAndSwap(1, 2) // transition to half-open
			return true
		}
		return false
	case 2: // half-open
		return true
	default:
		return false
	}
}

func (cb *CircuitBreaker) recordFailure() {
	cb.failures.Add(1)
	cb.lastFailureTime.Store(time.Now().UnixNano())
	
	if cb.failures.Load() >= int32(cb.maxFailures) {
		cb.state.Store(1) // open
	}
}

func (cb *CircuitBreaker) recordSuccess() {
	if cb.state.Load() == 2 { // half-open
		cb.state.Store(0) // closed
		cb.failures.Store(0)
	}
}

// Metrics Exporter
type MetricsExporter struct {
	url      string
	user     string
	pass     string
	client   *http.Client
	counters map[string]int64
	mu       sync.RWMutex
}

func NewMetricsExporter(url, user, pass string) *MetricsExporter {
	return &MetricsExporter{
		url:      url,
		user:     user,
		pass:     pass,
		client:   &http.Client{Timeout: 5 * time.Second},
		counters: make(map[string]int64),
	}
}

func (m *MetricsExporter) IncrementCounter(name string, value int64) {
	m.mu.Lock()
	m.counters[name] += value
	m.mu.Unlock()
}

func (m *MetricsExporter) RecordError(service, errorType string) {
	m.IncrementCounter(fmt.Sprintf("%s_%s_errors", service, errorType), 1)
}

func (m *MetricsExporter) RecordDuration(name string, duration time.Duration) {
	slog.Debug("Metric recorded", "name", name, "duration_ms", duration.Milliseconds())
}

// Data Integrity Checker
type DataIntegrityChecker struct {
	metricsExporter *MetricsExporter
}

func NewDataIntegrityChecker(metrics *MetricsExporter) *DataIntegrityChecker {
	return &DataIntegrityChecker{metricsExporter: metrics}
}

func (d *DataIntegrityChecker) VerifyAndRecord(logType, fileName string, processedLines, expectedLines int) {
	if processedLines != expectedLines {
		d.metricsExporter.IncrementCounter("data_integrity_mismatches", 1)
		slog.Warn("Data integrity mismatch", 
			"log_type", logType,
			"file", fileName,
			"processed", processedLines,
			"expected", expectedLines)
	}
}

// HTTP Connection Pool
type HTTPConnectionPool struct {
	clients chan *http.Client
	size    int
}

func NewHTTPConnectionPool(size int, timeout time.Duration) *HTTPConnectionPool {
	pool := &HTTPConnectionPool{
		clients: make(chan *http.Client, size),
		size:    size,
	}
	
	// Pre-create clients
	for i := 0; i < size; i++ {
		pool.clients <- &http.Client{
			Timeout: timeout,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 10,
				IdleConnTimeout:     90 * time.Second,
			},
		}
	}
	
	return pool
}

func (p *HTTPConnectionPool) Get() *http.Client {
	return <-p.clients
}

func (p *HTTPConnectionPool) Put(client *http.Client) {
	p.clients <- client
}

// Main types
type Config struct {
	KafkaBrokers     []string
	TrackingTable    string
	JobsTable        string
	OpenObserveURL   string
	OpenObserveUser  string
	OpenObservePass  string
	OpenObserveStream string
	ConsumerGroup    string
	MaxConcurrency   int
	BatchSize        int
	BatchTimeout     time.Duration
	Region           string
	// Added fields for checkpoint/resume and retry logic
	CheckpointTable      string
	DLQTable             string
	MaxRetries           int
	RetryBackoff         time.Duration
	CircuitBreakerMax    int
	CircuitBreakerTimeout time.Duration
	ConnectionPoolSize   int
	ConnectionTimeout    time.Duration
	// Fluent Bit forwarding configuration
	LogForwardEnabled    bool
	LogForwardHost       string
	LogForwardPort       string
	ParsingMode          string // passthrough, minimal, full
}

type LogMessage struct {
	InstanceID   string    `json:"instance_id"`
	ClusterID    string    `json:"cluster_id"`
	Engine       string    `json:"engine"`
	LogType      string    `json:"log_type"`
	LogFileName  string    `json:"log_file_name"`
	LastWritten  int64     `json:"last_written"`
	Size         int64     `json:"size"`
	Timestamp    time.Time `json:"timestamp"`
}

type ParsedLogEntry map[string]interface{}

// FluentBitForwarder handles TCP forwarding to Fluent Bit
type FluentBitForwarder struct {
	address      string
	conn         net.Conn
	mu           sync.Mutex
	connected    bool
	reconnectCh  chan struct{}
}

// NewFluentBitForwarder creates a new Fluent Bit forwarder
func NewFluentBitForwarder(host, port string) *FluentBitForwarder {
	return &FluentBitForwarder{
		address:     net.JoinHostPort(host, port),
		reconnectCh: make(chan struct{}, 1),
	}
}

// Connect establishes connection to Fluent Bit
func (f *FluentBitForwarder) Connect() error {
	f.mu.Lock()
	defer f.mu.Unlock()

	if f.connected && f.conn != nil {
		return nil
	}

	conn, err := net.DialTimeout("tcp", f.address, 5*time.Second)
	if err != nil {
		return fmt.Errorf("failed to connect to Fluent Bit at %s: %w", f.address, err)
	}

	f.conn = conn
	f.connected = true
	slog.Info("Connected to Fluent Bit", "address", f.address)
	return nil
}

// Forward sends a log entry to Fluent Bit
func (f *FluentBitForwarder) Forward(tag string, timestamp time.Time, record map[string]interface{}) error {
	f.mu.Lock()
	defer f.mu.Unlock()

	if !f.connected || f.conn == nil {
		if err := f.Connect(); err != nil {
			return err
		}
	}

	// Fluent Bit forward protocol format: [tag, [[timestamp, record]]]
	entry := []interface{}{
		tag,
		[]interface{}{
			[]interface{}{timestamp.Unix(), record},
		},
	}

	data, err := json.Marshal(entry)
	if err != nil {
		return fmt.Errorf("failed to marshal entry: %w", err)
	}

	// Set write deadline
	f.conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
	
	_, err = f.conn.Write(append(data, '\n'))
	if err != nil {
		f.connected = false
		f.conn.Close()
		return fmt.Errorf("failed to write to Fluent Bit: %w", err)
	}

	return nil
}

// Close closes the connection to Fluent Bit
func (f *FluentBitForwarder) Close() error {
	f.mu.Lock()
	defer f.mu.Unlock()

	if f.conn != nil {
		err := f.conn.Close()
		f.connected = false
		return err
	}
	return nil
}

// DynamoDBClientInterface defines the interface for DynamoDB operations
type DynamoDBClientInterface interface {
	GetItem(ctx context.Context, params *dynamodb.GetItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error)
	PutItem(ctx context.Context, params *dynamodb.PutItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error)
	UpdateItem(ctx context.Context, params *dynamodb.UpdateItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error)
	DeleteItem(ctx context.Context, params *dynamodb.DeleteItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error)
}

// Batch Processor with optimizations
type BatchProcessor struct {
	config           Config
	rdsClient        *rds.Client
	dynamoClient     DynamoDBClientInterface
	kafkaReader      *kafka.Reader
	httpPool         *HTTPConnectionPool
	metricsExporter  *MetricsExporter
	integrityChecker *DataIntegrityChecker
	circuitBreaker   *CircuitBreaker
	shutdownChan     chan struct{}
	workerCount      int
	fluentBitForwarder *FluentBitForwarder
}

type BatchItem struct {
	Message kafka.Message
	LogMsg  LogMessage
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	slog.Info("Starting Aurora Log Processor", "version", "2.0", "go_version", runtime.Version())

	if len(os.Args) > 1 && os.Args[1] == "-health" {
		fmt.Println("OK")
		os.Exit(0)
	}

	cfg := Config{
		KafkaBrokers:     strings.Split(os.Getenv("KAFKA_BROKERS"), ","),
		TrackingTable:    os.Getenv("TRACKING_TABLE"),
		JobsTable:        os.Getenv("JOBS_TABLE"),
		OpenObserveURL:   os.Getenv("OPENOBSERVE_URL"),
		OpenObserveUser:  os.Getenv("OPENOBSERVE_USER"),
		OpenObservePass:  os.Getenv("OPENOBSERVE_PASS"),
		OpenObserveStream: getEnvOrDefault("OPENOBSERVE_STREAM", "aurora_logs"),
		ConsumerGroup:    getEnvOrDefault("CONSUMER_GROUP", "aurora-processor-group"),
		MaxConcurrency:   getEnvAsInt("MAX_CONCURRENCY", 10),
		BatchSize:        getEnvAsInt("BATCH_SIZE", 100),
		BatchTimeout:     time.Duration(getEnvAsInt("BATCH_TIMEOUT_SEC", 5)) * time.Second,
		Region:           os.Getenv("AWS_REGION"),
		// Checkpoint and retry configuration
		CheckpointTable:      getEnvOrDefault("CHECKPOINT_TABLE", "aurora-log-checkpoints"),
		DLQTable:             getEnvOrDefault("DLQ_TABLE", "aurora-log-dlq"),
		MaxRetries:           getEnvAsInt("MAX_RETRIES", 3),
		RetryBackoff:         time.Duration(getEnvAsInt("RETRY_BACKOFF_SEC", 5)) * time.Second,
		CircuitBreakerMax:    getEnvAsInt("CIRCUIT_BREAKER_MAX_FAILURES", 5),
		CircuitBreakerTimeout: time.Duration(getEnvAsInt("CIRCUIT_BREAKER_TIMEOUT_SEC", 30)) * time.Second,
		ConnectionPoolSize:   getEnvAsInt("CONNECTION_POOL_SIZE", 100),
		ConnectionTimeout:    time.Duration(getEnvAsInt("CONNECTION_TIMEOUT_SEC", 30)) * time.Second,
		// Fluent Bit forwarding configuration
		LogForwardEnabled:    os.Getenv("LOG_FORWARD_ENABLED") == "true",
		LogForwardHost:       getEnvOrDefault("LOG_FORWARD_HOST", "localhost"),
		LogForwardPort:       getEnvOrDefault("LOG_FORWARD_PORT", "24224"),
		ParsingMode:          getEnvOrDefault("PARSING_MODE", "full"),
	}
	
	// Log configuration mode
	if cfg.LogForwardEnabled {
		slog.Info("Fluent Bit forwarding enabled", 
			"host", cfg.LogForwardHost, 
			"port", cfg.LogForwardPort,
			"parsing_mode", cfg.ParsingMode)
	} else {
		slog.Info("Using direct OpenObserve integration", "parsing_mode", cfg.ParsingMode)
	}

	// Configure AWS SDK with IMDSv2 support
	// Set environment variables for IMDSv2
	os.Setenv("AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE", "IPv4")
	os.Setenv("AWS_EC2_METADATA_SERVICE_ENDPOINT", "http://169.254.169.254")
	
	awsCfg, err := config.LoadDefaultConfig(context.Background(), 
		config.WithRegion(cfg.Region),
		config.WithEC2IMDSRegion(),
	)
	if err != nil {
		slog.Error("Failed to load AWS config", "error", err)
		os.Exit(1)
	}

	kafkaReader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:        cfg.KafkaBrokers,
		GroupTopics:    []string{"aurora-logs-error", "aurora-logs-slowquery"},
		GroupID:        cfg.ConsumerGroup,
		MinBytes:       10e3, // 10KB
		MaxBytes:       10e6, // 10MB
		CommitInterval: time.Second,
		StartOffset:    kafka.FirstOffset,
		ErrorLogger:    kafka.LoggerFunc(func(msg string, args ...interface{}) {
			slog.Error("Kafka error", "msg", fmt.Sprintf(msg, args...))
		}),
	})
	defer func() {
		if err := kafkaReader.Close(); err != nil {
			slog.Error("Failed to close kafka reader", "error", err)
		}
	}()

	metricsExporter := NewMetricsExporter(
		cfg.OpenObserveURL,
		cfg.OpenObserveUser,
		cfg.OpenObservePass,
	)

	// Create Fluent Bit forwarder if enabled
	var fluentBitForwarder *FluentBitForwarder
	if cfg.LogForwardEnabled {
		fluentBitForwarder = NewFluentBitForwarder(cfg.LogForwardHost, cfg.LogForwardPort)
		if err := fluentBitForwarder.Connect(); err != nil {
			slog.Warn("Failed to connect to Fluent Bit, will retry", "error", err)
		}
		defer fluentBitForwarder.Close()
	}

	processor := &BatchProcessor{
		config:           cfg,
		rdsClient:        rds.NewFromConfig(awsCfg),
		dynamoClient:     dynamodb.NewFromConfig(awsCfg),
		kafkaReader:      kafkaReader,
		httpPool:         NewHTTPConnectionPool(cfg.ConnectionPoolSize, cfg.ConnectionTimeout),
		metricsExporter:  metricsExporter,
		circuitBreaker:   NewCircuitBreaker(cfg.CircuitBreakerMax, cfg.CircuitBreakerTimeout),
		shutdownChan:     make(chan struct{}),
		workerCount:      cfg.MaxConcurrency,
		fluentBitForwarder: fluentBitForwarder,
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		sig := <-sigChan
		slog.Info("Received shutdown signal", "signal", sig)
		close(processor.shutdownChan)
		cancel()
	}()

	if err := processor.Start(ctx); err != nil {
		slog.Error("Processor failed", "error", err)
		os.Exit(1)
	}
}

func (bp *BatchProcessor) Start(ctx context.Context) error {
	// Create channels
	itemsChan := make(chan BatchItem, bp.config.BatchSize*2)
	var wg sync.WaitGroup
	
	// Start workers
	for i := 0; i < bp.workerCount; i++ {
		wg.Add(1)
		go func(workerID int) {
			defer wg.Done()
			bp.worker(ctx, workerID, itemsChan)
		}(i)
	}
	
	// Start batch collector
	wg.Add(1)
	go func() {
		defer wg.Done()
		bp.batchCollector(ctx, itemsChan)
	}()
	
	// Wait for completion
	wg.Wait()
	return nil
}

func (bp *BatchProcessor) batchCollector(ctx context.Context, itemsChan chan<- BatchItem) {
	defer close(itemsChan)
	
	batch := make([]BatchItem, 0, bp.config.BatchSize)
	ticker := time.NewTicker(bp.config.BatchTimeout)
	defer ticker.Stop()
	
	for {
		select {
		case <-ctx.Done():
			// Process remaining batch
			if len(batch) > 0 {
				bp.processBatch(ctx, batch, itemsChan)
			}
			return
			
		case <-bp.shutdownChan:
			// Process remaining batch
			if len(batch) > 0 {
				bp.processBatch(ctx, batch, itemsChan)
			}
			return
			
		case <-ticker.C:
			if len(batch) > 0 {
				bp.processBatch(ctx, batch, itemsChan)
				batch = make([]BatchItem, 0, bp.config.BatchSize)
			}
			
		default:
			// Fetch message
			msg, err := bp.kafkaReader.FetchMessage(ctx)
			if err != nil {
				if ctx.Err() != nil || errors.Is(err, io.EOF) {
					return
				}
				continue
			}
			
			// Parse message
			var logMsg LogMessage
			if err := json.Unmarshal(msg.Value, &logMsg); err != nil {
				slog.Error("Failed to unmarshal message", "error", err)
				if err := bp.kafkaReader.CommitMessages(ctx, msg); err != nil {
					slog.Error("Failed to commit message", "error", err)
				}
				continue
			}
			
			batch = append(batch, BatchItem{
				Message: msg,
				LogMsg:  logMsg,
			})
			
			if len(batch) >= bp.config.BatchSize {
				bp.processBatch(ctx, batch, itemsChan)
				batch = make([]BatchItem, 0, bp.config.BatchSize)
			}
		}
	}
}

func (bp *BatchProcessor) processBatch(ctx context.Context, batch []BatchItem, itemsChan chan<- BatchItem) {
	// Group by instance for efficient processing
	grouped := make(map[string][]BatchItem)
	for _, item := range batch {
		key := item.LogMsg.InstanceID
		grouped[key] = append(grouped[key], item)
	}
	
	slog.Info("Processing batch", "total_items", len(batch), "instances", len(grouped))
	
	// Send to workers
	for _, items := range grouped {
		for _, item := range items {
			select {
			case itemsChan <- item:
			case <-ctx.Done():
				return
			}
		}
	}
}

func (bp *BatchProcessor) worker(ctx context.Context, workerID int, itemsChan <-chan BatchItem) {
	for {
		select {
		case item, ok := <-itemsChan:
			if !ok {
				return
			}
			
			// Process with retry logic
			var err error
			retryCount := 0
			
			for retryCount <= bp.config.MaxRetries {
				err = bp.circuitBreaker.Call(func() error {
					return bp.processLogOptimized(ctx, item.LogMsg)
				})
				
				if err == nil {
					// Success - commit message
					if commitErr := bp.kafkaReader.CommitMessages(ctx, item.Message); commitErr != nil {
						slog.Error("Failed to commit message", "error", commitErr)
						// Don't retry on commit errors
					}
					break
				}
				
				if retryCount < bp.config.MaxRetries {
					slog.Warn("Retrying failed log processing",
						"worker", workerID,
						"instance", item.LogMsg.InstanceID,
						"file", item.LogMsg.LogFileName,
						"retry", retryCount+1,
						"error", err)
					
					// Exponential backoff
					backoff := time.Duration(retryCount+1) * bp.config.RetryBackoff
					select {
					case <-time.After(backoff):
					case <-ctx.Done():
						return
					}
				}
				
				retryCount++
			}
			
			if err != nil {
				// All retries failed - send to DLQ
				slog.Error("Failed to process log after retries", 
					"worker", workerID,
					"instance", item.LogMsg.InstanceID,
					"file", item.LogMsg.LogFileName,
					"retries", bp.config.MaxRetries,
					"error", err)
				
				bp.metricsExporter.RecordError("processor", "processing_failed_all_retries")
				
				// Send to DLQ
				if dlqErr := bp.sendToDLQ(ctx, item, err); dlqErr != nil {
					slog.Error("Failed to send to DLQ", "error", dlqErr)
				}
				
				// Commit message anyway to avoid reprocessing
				if commitErr := bp.kafkaReader.CommitMessages(ctx, item.Message); commitErr != nil {
					slog.Error("Failed to commit failed message", "error", commitErr)
				}
			}
			
		case <-ctx.Done():
			return
		}
	}
}

// extractTimestampFromLine attempts to extract timestamp from a log line
func extractTimestampFromLine(line string, logType string) time.Time {
	switch logType {
	case "error":
		// MySQL error log: "2025-08-02 12:34:56"
		if len(line) >= 19 {
			if ts, err := time.Parse("2006-01-02 15:04:05", line[:19]); err == nil {
				return ts
			}
		}
	case "slowquery":
		// Slow query: "# Time: 2025-08-02T15:04:05.000000Z"
		if strings.HasPrefix(line, "# Time:") {
			tsStr := strings.TrimSpace(strings.TrimPrefix(line, "# Time:"))
			layouts := []string{
				"2006-01-02T15:04:05.000000Z",
				"2006-01-02T15:04:05Z",
				"060102 15:04:05",
			}
			for _, layout := range layouts {
				if ts, err := time.Parse(layout, tsStr); err == nil {
					return ts
				}
			}
		}
		// Alternative: "SET timestamp=1234567890;"
		if strings.HasPrefix(line, "SET timestamp=") {
			if parts := strings.Split(line, "="); len(parts) == 2 {
				tsStr := strings.TrimSuffix(strings.TrimSpace(parts[1]), ";")
				if unixTs, err := strconv.ParseInt(tsStr, 10, 64); err == nil {
					return time.Unix(unixTs, 0)
				}
			}
		}
	default:
		// General log: "2025-08-02 12:34:56"
		if len(line) >= 19 {
			if ts, err := time.Parse("2006-01-02 15:04:05", line[:19]); err == nil {
				return ts
			}
		}
	}
	return time.Time{}
}

// forwardLogToFluentBit sends raw logs to Fluent Bit via TCP forward protocol
func (bp *BatchProcessor) forwardLogToFluentBit(ctx context.Context, logMsg LogMessage) error {
	if bp.fluentBitForwarder == nil {
		return fmt.Errorf("Fluent Bit forwarder not initialized")
	}

	slog.Info("Forwarding log to Fluent Bit", "instance_id", logMsg.InstanceID, "file", logMsg.LogFileName)
	
	// Update status to 'processing'
	if err := bp.updateLogStatus(ctx, logMsg, "processing", "", 0); err != nil {
		slog.Error("Failed to update status to processing", "error", err)
	}
	
	// Download log with streaming
	reader, err := bp.downloadLogStreaming(ctx, logMsg, "")
	if err != nil {
		// Update status to 'failed'
		if statusErr := bp.updateLogStatus(ctx, logMsg, "failed", fmt.Sprintf("Download failed: %v", err), 0); statusErr != nil {
			slog.Error("Failed to update status to failed", "error", statusErr)
		}
		return err
	}
	defer reader.Close()
	
	// Determine tag based on log type
	tag := fmt.Sprintf("aurora.%s", logMsg.LogType)
	
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024) // 64KB initial, 1MB max
	
	lineCount := 0
	batchCount := 0
	batch := make([]map[string]interface{}, 0, 100)
	
	// For passthrough mode, we still need to extract timestamp from first line
	var logTimestamp time.Time
	timestampExtracted := false
	
	for scanner.Scan() {
		line := scanner.Text()
		lineCount++
		
		// Try to extract timestamp from first few lines
		if !timestampExtracted && lineCount <= 10 {
			ts := extractTimestampFromLine(line, logMsg.LogType)
			if !ts.IsZero() {
				logTimestamp = ts
				timestampExtracted = true
				slog.Debug("Extracted timestamp from log", "timestamp", logTimestamp)
			}
		}
		
		// Use extracted timestamp or current time
		entryTime := logTimestamp
		if entryTime.IsZero() {
			entryTime = time.Now()
		}
		
		// Create minimal record with raw log line
		record := map[string]interface{}{
			"message":       line,
			"log_type":      logMsg.LogType,
			"instance_id":   logMsg.InstanceID,
			"cluster_id":    logMsg.ClusterID,
			"log_file_name": logMsg.LogFileName,
			"line_number":   lineCount,
		}
		
		batch = append(batch, record)
		
		// Send batch when full
		if len(batch) >= 100 {
			for _, entry := range batch {
				if err := bp.fluentBitForwarder.Forward(tag, entryTime, entry); err != nil {
					slog.Warn("Failed to forward to Fluent Bit", "error", err)
				}
			}
			batchCount++
			batch = batch[:0] // Reset batch
		}
	}
	
	// Send remaining batch
	if len(batch) > 0 {
		entryTime := logTimestamp
		if entryTime.IsZero() {
			entryTime = time.Now()
		}
		for _, entry := range batch {
			if err := bp.fluentBitForwarder.Forward(tag, entryTime, entry); err != nil {
				slog.Warn("Failed to forward to Fluent Bit", "error", err)
			}
		}
		batchCount++
	}
	
	if err := scanner.Err(); err != nil {
		// Update status to 'failed'
		if statusErr := bp.updateLogStatus(ctx, logMsg, "failed", fmt.Sprintf("Scanner error: %v", err), lineCount); statusErr != nil {
			slog.Error("Failed to update status to failed", "error", statusErr)
		}
		return fmt.Errorf("error reading log file: %w", err)
	}
	
	// Update status to 'completed'
	if err := bp.updateLogStatus(ctx, logMsg, "completed", "", lineCount); err != nil {
		slog.Error("Failed to update status to completed", "error", err)
	}
	
	slog.Info("Forwarding completed", 
		"instance_id", logMsg.InstanceID,
		"file", logMsg.LogFileName,
		"total_lines", lineCount,
		"batches_sent", batchCount)
	
	return nil
}

func (bp *BatchProcessor) processLogOptimized(ctx context.Context, logMsg LogMessage) error {
	startTime := time.Now()
	defer func() {
		bp.metricsExporter.RecordDuration("log_processing_duration", time.Since(startTime))
	}()
	
	slog.Info("Processing log", "instance_id", logMsg.InstanceID, "file", logMsg.LogFileName, "size", logMsg.Size)
	
	// Check if we should forward to Fluent Bit
	if bp.config.LogForwardEnabled && bp.config.ParsingMode == "passthrough" {
		return bp.forwardLogToFluentBit(ctx, logMsg)
	}
	
	// Check for existing checkpoint
	checkpointMarker, err := bp.getCheckpoint(ctx, logMsg)
	if err != nil {
		slog.Warn("Failed to get checkpoint", "error", err)
		// Continue without checkpoint
	}
	
	if checkpointMarker != "" {
		slog.Info("Resuming from checkpoint", "marker", checkpointMarker)
	}
	
	// Update status to 'processing'
	if err := bp.updateLogStatus(ctx, logMsg, "processing", "", 0); err != nil {
		slog.Error("Failed to update status to processing", "error", err)
	}
	
	// Download log with streaming from checkpoint
	reader, err := bp.downloadLogStreaming(ctx, logMsg, checkpointMarker)
	if err != nil {
		// Update status to 'failed'
		if statusErr := bp.updateLogStatus(ctx, logMsg, "failed", fmt.Sprintf("Download failed: %v", err), 0); statusErr != nil {
			slog.Error("Failed to update status to failed", "error", statusErr)
		}
		return fmt.Errorf("download failed: %w", err)
	}
	defer func() {
		if err := reader.Close(); err != nil {
			slog.Error("Failed to close reader", "error", err)
		}
	}()
	
	// Create a channel to receive markers from download goroutine
	markerChan := make(chan string, 100)
	doneChan := make(chan struct{})
	
	// Start marker tracking goroutine if reader supports it
	if mtr, ok := reader.(*markerTrackingReader); ok {
		go bp.trackDownloadMarkers(ctx, logMsg, mtr, markerChan, doneChan)
	}
	
	// Parse and process log
	parser := bp.getParser(logMsg.LogType)
	batch := make([]ParsedLogEntry, 0, 1000)
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 0, 64*1024), 10*1024*1024) // 10MB max line
	
	lineCount := 0
	parsedCount := 0
	lastCheckpointLines := 0
	currentMarker := checkpointMarker
	
	for scanner.Scan() {
		line := scanner.Text()
		lineCount++
		
		// Check for new marker
		select {
		case newMarker := <-markerChan:
			currentMarker = newMarker
		default:
		}
		
		// Parse line
		entry := parser(line)
		if entry != nil {
			// Add metadata
			entry["log_type"] = logMsg.LogType
			entry["instance_id"] = logMsg.InstanceID
			entry["cluster_id"] = logMsg.ClusterID
			entry["log_file_name"] = logMsg.LogFileName
			
			// Use the log's original timestamp if available, otherwise use current time
			if ts, ok := entry["timestamp"].(string); ok && ts != "" {
				// Parse and convert timestamp to OpenObserve format
				if parsedTime := parseLogTimestamp(ts, logMsg.LogType); !parsedTime.IsZero() {
					entry["_timestamp"] = parsedTime.UnixMilli() // OpenObserve uses milliseconds
					entry["@timestamp"] = parsedTime.Format(time.RFC3339)
				} else {
					entry["_timestamp"] = time.Now().UnixMilli()
					entry["@timestamp"] = time.Now().Format(time.RFC3339)
				}
			} else {
				entry["_timestamp"] = time.Now().UnixMilli()
				entry["@timestamp"] = time.Now().Format(time.RFC3339)
			}
			
			parsedCount++
			batch = append(batch, entry)
			
			// Send batch when full
			if len(batch) >= 1000 {
				if err := bp.sendBatch(ctx, logMsg, batch); err != nil {
					slog.Warn("Failed to send batch", "error", err)
				}
				batch = make([]ParsedLogEntry, 0, 1000)
				
				// Save checkpoint every 10000 lines
				if lineCount-lastCheckpointLines >= 10000 && currentMarker != "" {
					if err := bp.saveCheckpoint(ctx, logMsg, currentMarker, lineCount); err != nil {
						slog.Warn("Failed to save checkpoint", "error", err)
					}
					lastCheckpointLines = lineCount
				}
			}
		}
	}
	
	close(doneChan)
	
	if err := scanner.Err(); err != nil {
		// Update status to 'failed'
		if statusErr := bp.updateLogStatus(ctx, logMsg, "failed", fmt.Sprintf("Scanner error: %v", err), lineCount); statusErr != nil {
			slog.Error("Failed to update status to failed", "error", statusErr)
		}
		return fmt.Errorf("error reading log file: %w", err)
	}
	
	// Send final batch
	if len(batch) > 0 {
		if err := bp.sendBatch(ctx, logMsg, batch); err != nil {
			slog.Warn("Failed to send final batch", "error", err)
		}
	}
	
	// Delete checkpoint on successful completion
	if err := bp.deleteCheckpoint(ctx, logMsg); err != nil {
		slog.Warn("Failed to delete checkpoint", "error", err)
	}
	
	// Update status to 'completed'
	if err := bp.updateLogStatus(ctx, logMsg, "completed", "", lineCount); err != nil {
		slog.Error("Failed to update status to completed", "error", err)
		// Don't fail the whole process if status update fails
	}
	
	slog.Info("Processing completed", 
		"instance_id", logMsg.InstanceID,
		"file", logMsg.LogFileName,
		"total_lines", lineCount,
		"parsed_entries", parsedCount,
		"log_type", logMsg.LogType)
	
	return nil
}

// Custom reader that tracks markers
type markerTrackingReader struct {
	*io.PipeReader
	markerChan chan string
}

func (r *markerTrackingReader) SendMarker(marker string) {
	select {
	case r.markerChan <- marker:
	default:
		// Channel full, skip this marker
	}
}

// Streaming download implementation with marker tracking
func (bp *BatchProcessor) downloadLogStreaming(ctx context.Context, logMsg LogMessage, startMarker string) (io.ReadCloser, error) {
	pr, pw := io.Pipe()
	
	// Create custom reader that exposes marker channel
	mtr := &markerTrackingReader{
		PipeReader: pr,
		markerChan: make(chan string, 100),
	}
	
	go func() {
		defer func() {
			if err := pw.Close(); err != nil {
				slog.Error("Failed to close pipe writer", "error", err)
			}
			close(mtr.markerChan)
		}()
		
		marker := startMarker
		if marker == "" || marker == "end" {
			marker = "0"
		}
		
		for {
			select {
			case <-ctx.Done():
				pw.CloseWithError(ctx.Err())
				return
			default:
			}
			
			output, err := bp.rdsClient.DownloadDBLogFilePortion(ctx, &rds.DownloadDBLogFilePortionInput{
				DBInstanceIdentifier: &logMsg.InstanceID,
				LogFileName:          &logMsg.LogFileName,
				Marker:               &marker,
				NumberOfLines:        aws.Int32(10000), // Download in chunks
			})
			
			if err != nil {
				pw.CloseWithError(err)
				return
			}
			
			if output.LogFileData != nil && len(*output.LogFileData) > 0 {
				if _, err := pw.Write([]byte(*output.LogFileData)); err != nil {
					pw.CloseWithError(err)
					return
				}
			}
			
			// Update marker and send to tracking channel
			if output.Marker != nil {
				marker = *output.Marker
				// Send marker for checkpoint tracking
				select {
				case mtr.markerChan <- marker:
				default:
					// Channel full, skip
				}
			}
			
			// Check if done
			if output.AdditionalDataPending == nil || !*output.AdditionalDataPending {
				return
			}
		}
	}()
	
	return mtr, nil
}

// Track download markers for checkpointing
func (bp *BatchProcessor) trackDownloadMarkers(ctx context.Context, logMsg LogMessage, mtr *markerTrackingReader, markerChan chan<- string, doneChan <-chan struct{}) {
	for {
		select {
		case <-ctx.Done():
			return
		case <-doneChan:
			return
		case marker, ok := <-mtr.markerChan:
			if !ok {
				return
			}
			// Forward marker to processing goroutine
			select {
			case markerChan <- marker:
			default:
			}
		}
	}
}


func (bp *BatchProcessor) updateLogStatus(ctx context.Context, logMsg LogMessage, status string, errorMessage string, lineCount int) error {
	updateExpr := "SET #status = :status, #updated_at = :updated_at"
	exprNames := map[string]string{
		"#status":     "status",
		"#updated_at": "updated_at",
	}
	exprValues := map[string]dynamoTypes.AttributeValue{
		":status":     &dynamoTypes.AttributeValueMemberS{Value: status},
		":updated_at": &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)},
	}
	
	// Add specific fields based on status
	switch status {
	case "processing":
		updateExpr += ", processing_started_at = :processing_started_at"
		exprValues[":processing_started_at"] = &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)}
	case "completed":
		updateExpr += ", processing_completed_at = :processing_completed_at, lines_processed = :lines_processed"
		exprValues[":processing_completed_at"] = &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)}
		exprValues[":lines_processed"] = &dynamoTypes.AttributeValueMemberN{Value: strconv.Itoa(lineCount)}
	case "failed":
		updateExpr += ", error_message = :error_message, processing_failed_at = :processing_failed_at"
		exprValues[":error_message"] = &dynamoTypes.AttributeValueMemberS{Value: errorMessage}
		exprValues[":processing_failed_at"] = &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)}
	}
	
	_, err := bp.dynamoClient.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: &bp.config.TrackingTable,
		Key: map[string]dynamoTypes.AttributeValue{
			"instance_id":   &dynamoTypes.AttributeValueMemberS{Value: logMsg.InstanceID},
			"log_file_name": &dynamoTypes.AttributeValueMemberS{Value: logMsg.LogFileName},
		},
		UpdateExpression:          &updateExpr,
		ExpressionAttributeNames:  exprNames,
		ExpressionAttributeValues: exprValues,
	})
	
	return err
}

func (bp *BatchProcessor) sendBatch(ctx context.Context, logMsg LogMessage, batch []ParsedLogEntry) error {
	httpClient := bp.httpPool.Get()
	defer bp.httpPool.Put(httpClient)
	
	// Convert batch to JSON array
	jsonData, err := json.Marshal(batch)
	if err != nil {
		return fmt.Errorf("failed to marshal batch: %w", err)
	}
	
	// Use different streams based on log type
	streamName := bp.config.OpenObserveStream
	switch logMsg.LogType {
	case "error":
		streamName = "aurora_error_logs"
	case "slowquery":
		streamName = "aurora_slowquery_logs"
	}
	
	url := fmt.Sprintf("%s/api/default/%s/_json", bp.config.OpenObserveURL, streamName)
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(jsonData))
	if err != nil {
		return err
	}
	
	req.SetBasicAuth(bp.config.OpenObserveUser, bp.config.OpenObservePass)
	req.Header.Set("Content-Type", "application/json")
	
	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer func() {
		if err := resp.Body.Close(); err != nil {
			slog.Error("Failed to close response body", "error", err)
		}
	}()
	
	if resp.StatusCode >= 400 {
		return fmt.Errorf("HTTP error: %d", resp.StatusCode)
	}
	
	return nil
}

func (bp *BatchProcessor) getParser(logType string) func(string) ParsedLogEntry {
	switch logType {
	case "error":
		return parseErrorLog
	case "slowquery":
		return parseSlowQueryLog
	default:
		return parseGenericLog
	}
}

// parseLogTimestamp parses timestamps from different log formats
func parseLogTimestamp(timestamp string, logType string) time.Time {
	var layouts []string
	
	switch logType {
	case "error":
		// MySQL error log format: 2025-08-02 12:34:56
		layouts = []string{
			"2006-01-02 15:04:05",
			"2006-01-02T15:04:05Z",
			"2006-01-02T15:04:05.000Z",
		}
	case "slowquery":
		// MySQL slow query format variations
		layouts = []string{
			"2006-01-02T15:04:05.000000Z",
			"2006-01-02 15:04:05",
			"060102 15:04:05", // Older MySQL format
			time.RFC3339,
		}
	default:
		// General log formats
		layouts = []string{
			"2006-01-02 15:04:05",
			"2006-01-02T15:04:05Z",
			time.RFC3339,
			time.RFC3339Nano,
		}
	}
	
	// Try each layout
	for _, layout := range layouts {
		if t, err := time.Parse(layout, timestamp); err == nil {
			return t
		}
	}
	
	// If no layout matches, return zero time
	return time.Time{}
}

// Parser functions
func parseErrorLog(line string) ParsedLogEntry {
	// Skip empty lines
	if strings.TrimSpace(line) == "" {
		return nil
	}
	
	// Aurora MySQL error log format: YYYY-MM-DD HH:MM:SS [Note/Warning/ERROR] message
	// Example: 2025-08-02 12:34:56 140234567890 [ERROR] Access denied for user...
	if len(line) > 19 && line[4] == '-' && line[7] == '-' && line[10] == ' ' && line[13] == ':' && line[16] == ':' {
		timestamp := line[:19]
		remainder := line[19:]
		
		// Extract level
		level := "INFO"
		message := remainder
		
		if idx := strings.Index(remainder, "[ERROR]"); idx != -1 {
			level = "ERROR"
			message = strings.TrimSpace(remainder[idx+7:])
		} else if idx := strings.Index(remainder, "[Warning]"); idx != -1 {
			level = "WARNING"
			message = strings.TrimSpace(remainder[idx+9:])
		} else if idx := strings.Index(remainder, "[Note]"); idx != -1 {
			level = "INFO"
			message = strings.TrimSpace(remainder[idx+6:])
		}
		
		return ParsedLogEntry{
			"timestamp": timestamp,
			"level":     level,
			"message":   message,
			"raw_line":  line,
		}
	}
	
	// If can't parse, return raw line
	return ParsedLogEntry{
		"message":  line,
		"raw_line": line,
	}
}

func parseSlowQueryLog(line string) ParsedLogEntry {
	// Skip empty lines
	if strings.TrimSpace(line) == "" {
		return nil
	}
	
	// MySQL slow query log parsing
	if strings.HasPrefix(line, "# Time:") {
		timestamp := strings.TrimSpace(strings.TrimPrefix(line, "# Time:"))
		return ParsedLogEntry{
			"timestamp": timestamp,
			"event_type": "query_start",
		}
	}
	
	// Alternative timestamp format (SET timestamp=unix_timestamp)
	if strings.HasPrefix(line, "SET timestamp=") {
		if parts := strings.Split(line, "="); len(parts) == 2 {
			tsStr := strings.TrimSuffix(strings.TrimSpace(parts[1]), ";")
			if unixTs, err := strconv.ParseInt(tsStr, 10, 64); err == nil {
				return ParsedLogEntry{
					"timestamp": time.Unix(unixTs, 0).Format("2006-01-02 15:04:05"),
					"event_type": "query_timestamp",
				}
			}
		}
	}
	
	if strings.HasPrefix(line, "# User@Host:") {
		userHost := strings.TrimSpace(strings.TrimPrefix(line, "# User@Host:"))
		// Parse user and host
		if match := strings.Contains(userHost, "["); match {
			parts := strings.Split(userHost, "[")
			userPart := strings.TrimSpace(parts[0])
			hostPart := ""
			if len(parts) > 1 {
				hostPart = strings.TrimSuffix(parts[1], "]")
			}
			return ParsedLogEntry{
				"user_host": userHost,
				"user": userPart,
				"host": hostPart,
				"event_type": "query_metadata",
			}
		}
		return ParsedLogEntry{
			"user_host": userHost,
			"event_type": "query_metadata",
		}
	}
	
	if strings.HasPrefix(line, "# Query_time:") {
		parts := strings.Fields(line)
		result := ParsedLogEntry{
			"event_type": "query_stats",
		}
		
		// Parse key-value pairs
		for i := 0; i < len(parts)-1; i++ {
			if strings.HasSuffix(parts[i], ":") {
				key := strings.ToLower(strings.TrimSuffix(parts[i], ":"))
				key = strings.TrimPrefix(key, "#")
				key = strings.TrimSpace(key)
				if i+1 < len(parts) {
					value := parts[i+1]
					// Try to parse numeric values
					if floatVal, err := strconv.ParseFloat(value, 64); err == nil {
						result[key] = floatVal
					} else {
						result[key] = value
					}
				}
			}
		}
		return result
	}
	
	// Handle SQL statements (non-comment lines)
	if !strings.HasPrefix(line, "#") && strings.TrimSpace(line) != "" {
		return ParsedLogEntry{
			"sql_statement": line,
			"event_type": "query_sql",
		}
	}
	
	return nil
}

func parseGenericLog(line string) ParsedLogEntry {
	if strings.TrimSpace(line) == "" {
		return nil
	}
	
	// Try to extract timestamp from the beginning of the line
	// Common formats: "2025-08-02 12:34:56" or "2025-08-02T12:34:56"
	var timestamp string
	var message string
	
	// Check for ISO-like timestamp at the beginning
	if len(line) > 19 {
		possibleTS := line[:19]
		if strings.Count(possibleTS, "-") == 2 && (strings.Count(possibleTS, ":") == 2 || strings.Count(possibleTS, "T") == 1) {
			timestamp = possibleTS
			message = strings.TrimSpace(line[19:])
		}
	}
	
	// If no timestamp found, check for Unix timestamp
	if timestamp == "" && strings.HasPrefix(line, "[") {
		if end := strings.Index(line, "]"); end > 1 && end < 20 {
			tsStr := line[1:end]
			if unixTs, err := strconv.ParseInt(tsStr, 10, 64); err == nil && unixTs > 1000000000 {
				timestamp = time.Unix(unixTs, 0).Format("2006-01-02 15:04:05")
				message = strings.TrimSpace(line[end+1:])
			}
		}
	}
	
	// Build result
	result := ParsedLogEntry{
		"raw_line": line,
	}
	
	if timestamp != "" {
		result["timestamp"] = timestamp
		result["message"] = message
	} else {
		result["message"] = line
	}
	
	return result
}

// ============================================================================
// Checkpoint and Recovery Functions
// ============================================================================

func (bp *BatchProcessor) getCheckpoint(ctx context.Context, logMsg LogMessage) (string, error) {
	result, err := bp.dynamoClient.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: &bp.config.CheckpointTable,
		Key: map[string]dynamoTypes.AttributeValue{
			"instance_id":   &dynamoTypes.AttributeValueMemberS{Value: logMsg.InstanceID},
			"log_file_name": &dynamoTypes.AttributeValueMemberS{Value: logMsg.LogFileName},
		},
	})
	
	if err != nil {
		return "", err
	}
	
	if result.Item == nil {
		return "", nil
	}
	
	if marker, ok := result.Item["marker"]; ok {
		if markerVal, ok := marker.(*dynamoTypes.AttributeValueMemberS); ok {
			return markerVal.Value, nil
		}
	}
	
	return "", nil
}

func (bp *BatchProcessor) saveCheckpoint(ctx context.Context, logMsg LogMessage, marker string, lineCount int) error {
	_, err := bp.dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: &bp.config.CheckpointTable,
		Item: map[string]dynamoTypes.AttributeValue{
			"instance_id":   &dynamoTypes.AttributeValueMemberS{Value: logMsg.InstanceID},
			"log_file_name": &dynamoTypes.AttributeValueMemberS{Value: logMsg.LogFileName},
			"marker":        &dynamoTypes.AttributeValueMemberS{Value: marker},
			"line_count":    &dynamoTypes.AttributeValueMemberN{Value: strconv.Itoa(lineCount)},
			"updated_at":    &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)},
		},
	})
	return err
}

func (bp *BatchProcessor) deleteCheckpoint(ctx context.Context, logMsg LogMessage) error {
	_, err := bp.dynamoClient.DeleteItem(ctx, &dynamodb.DeleteItemInput{
		TableName: &bp.config.CheckpointTable,
		Key: map[string]dynamoTypes.AttributeValue{
			"instance_id":   &dynamoTypes.AttributeValueMemberS{Value: logMsg.InstanceID},
			"log_file_name": &dynamoTypes.AttributeValueMemberS{Value: logMsg.LogFileName},
		},
	})
	return err
}

// ============================================================================
// Dead Letter Queue Functions
// ============================================================================

func (bp *BatchProcessor) sendToDLQ(ctx context.Context, item BatchItem, processingError error) error {
	_, err := bp.dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: &bp.config.DLQTable,
		Item: map[string]dynamoTypes.AttributeValue{
			"message_id":     &dynamoTypes.AttributeValueMemberS{Value: fmt.Sprintf("%s-%s-%d", item.LogMsg.InstanceID, item.LogMsg.LogFileName, time.Now().UnixNano())},
			"instance_id":    &dynamoTypes.AttributeValueMemberS{Value: item.LogMsg.InstanceID},
			"log_file_name":  &dynamoTypes.AttributeValueMemberS{Value: item.LogMsg.LogFileName},
			"cluster_id":     &dynamoTypes.AttributeValueMemberS{Value: item.LogMsg.ClusterID},
			"log_type":       &dynamoTypes.AttributeValueMemberS{Value: item.LogMsg.LogType},
			"error":          &dynamoTypes.AttributeValueMemberS{Value: processingError.Error()},
			"retry_count":    &dynamoTypes.AttributeValueMemberN{Value: strconv.Itoa(bp.config.MaxRetries)},
			"failed_at":      &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)},
			"kafka_partition": &dynamoTypes.AttributeValueMemberN{Value: strconv.Itoa(item.Message.Partition)},
			"kafka_offset":   &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(item.Message.Offset, 10)},
			"original_message": &dynamoTypes.AttributeValueMemberS{Value: string(item.Message.Value)},
		},
	})
	return err
}