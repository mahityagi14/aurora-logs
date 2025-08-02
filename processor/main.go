package main

import (
	"bufio"
	"bytes"
	"compress/gzip"
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
	"github.com/aws/aws-sdk-go-v2/feature/s3/manager"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	dynamoTypes "github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/rds"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/segmentio/kafka-go"
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

// Buffer and Gzip pools for performance
var (
	bufferPool = sync.Pool{
		New: func() interface{} {
			return new(bytes.Buffer)
		},
	}
	gzipWriterPool = sync.Pool{
		New: func() interface{} {
			return gzip.NewWriter(nil)
		},
	}
)

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
	S3Bucket         string
	OpenObserveURL   string
	OpenObserveUser  string
	OpenObservePass  string
	ConsumerGroup    string
	MaxConcurrency   int
	BatchSize        int
	BatchTimeout     time.Duration
	Region           string
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

type LogPosition struct {
	LastMarker string
	UpdatedAt  time.Time
}

type ParsedLogEntry map[string]interface{}

// Batch Processor with optimizations
type BatchProcessor struct {
	config           Config
	rdsClient        *rds.Client
	s3Client         *s3.Client
	s3Uploader       *manager.Uploader
	dynamoClient     *dynamodb.Client
	kafkaReader      *kafka.Reader
	httpPool         *HTTPConnectionPool
	metricsExporter  *MetricsExporter
	integrityChecker *DataIntegrityChecker
	circuitBreaker   *CircuitBreaker
	shutdownChan     chan struct{}
	workerCount      int
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
		S3Bucket:         os.Getenv("S3_BUCKET"),
		OpenObserveURL:   os.Getenv("OPENOBSERVE_URL"),
		OpenObserveUser:  os.Getenv("OPENOBSERVE_USER"),
		OpenObservePass:  os.Getenv("OPENOBSERVE_PASS"),
		ConsumerGroup:    getEnvOrDefault("CONSUMER_GROUP", "aurora-processor-group"),
		MaxConcurrency:   getEnvAsInt("MAX_CONCURRENCY", 10),
		BatchSize:        getEnvAsInt("BATCH_SIZE", 100),
		BatchTimeout:     time.Duration(getEnvAsInt("BATCH_TIMEOUT_SEC", 5)) * time.Second,
		Region:           os.Getenv("AWS_REGION"),
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

	processor := &BatchProcessor{
		config:           cfg,
		rdsClient:        rds.NewFromConfig(awsCfg),
		s3Client:         s3.NewFromConfig(awsCfg),
		s3Uploader:       manager.NewUploader(s3.NewFromConfig(awsCfg)),
		dynamoClient:     dynamodb.NewFromConfig(awsCfg),
		kafkaReader:      kafkaReader,
		httpPool:         NewHTTPConnectionPool(20, 30*time.Second),
		metricsExporter:  metricsExporter,
		integrityChecker: NewDataIntegrityChecker(metricsExporter),
		circuitBreaker:   NewCircuitBreaker(5, 30*time.Second),
		shutdownChan:     make(chan struct{}),
		workerCount:      cfg.MaxConcurrency,
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
	// Get reusable buffers
	buf := bufferPool.Get().(*bytes.Buffer)
	defer func() {
		buf.Reset()
		bufferPool.Put(buf)
	}()
	
	gz := gzipWriterPool.Get().(*gzip.Writer)
	defer func() {
		gz.Reset(nil)
		gzipWriterPool.Put(gz)
	}()
	
	for {
		select {
		case item, ok := <-itemsChan:
			if !ok {
				return
			}
			
			// Process with circuit breaker
			err := bp.circuitBreaker.Call(func() error {
				return bp.processLogOptimized(ctx, item.LogMsg, buf, gz)
			})
			
			if err != nil {
				slog.Error("Failed to process log", 
					"worker", workerID,
					"instance", item.LogMsg.InstanceID,
					"file", item.LogMsg.LogFileName,
					"error", err)
				bp.metricsExporter.RecordError("processor", "processing_failed")
			}
			
			// Commit message
			if err := bp.kafkaReader.CommitMessages(ctx, item.Message); err != nil {
				slog.Error("Failed to commit message", "error", err)
			}
			
			// Reset buffers for reuse
			buf.Reset()
			gz.Reset(buf)
			
		case <-ctx.Done():
			return
		}
	}
}

func (bp *BatchProcessor) processLogOptimized(ctx context.Context, logMsg LogMessage, buf *bytes.Buffer, gz *gzip.Writer) error {
	startTime := time.Now()
	defer func() {
		bp.metricsExporter.RecordDuration("log_processing_duration", time.Since(startTime))
	}()
	
	slog.Info("Processing log", "instance_id", logMsg.InstanceID, "file", logMsg.LogFileName, "size", logMsg.Size)
	
	// Get position
	position := bp.getPosition(ctx, logMsg)
	
	// Download log with streaming
	reader, err := bp.downloadLogStreaming(ctx, logMsg, position.LastMarker)
	if err != nil {
		return fmt.Errorf("download failed: %w", err)
	}
	defer func() {
		if err := reader.Close(); err != nil {
			slog.Error("Failed to close reader", "error", err)
		}
	}()
	
	// Setup gzip writer
	gz.Reset(buf)
	
	// Parse and process log
	parser := bp.getParser(logMsg.LogType)
	batch := make([]ParsedLogEntry, 0, 1000)
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 0, 64*1024), 10*1024*1024) // 10MB max line
	
	lineCount := 0
	var lastMarker string
	
	for scanner.Scan() {
		line := scanner.Text()
		lineCount++
		
		// Update marker periodically
		if lineCount%1000 == 0 {
			lastMarker = fmt.Sprintf("%d", lineCount)
			bp.updatePosition(ctx, logMsg, lastMarker)
		}
		
		// Write to compressed buffer
		if _, err := gz.Write([]byte(line)); err != nil {
			return fmt.Errorf("failed to write line to gzip: %w", err)
		}
		if _, err := gz.Write([]byte("\n")); err != nil {
			return fmt.Errorf("failed to write newline to gzip: %w", err)
		}
		
		// Parse line
		entry := parser(line)
		if entry != nil {
			batch = append(batch, entry)
			
			// Send batch when full
			if len(batch) >= 1000 {
				if err := bp.sendBatch(ctx, logMsg, batch); err != nil {
					slog.Warn("Failed to send batch", "error", err)
				}
				batch = make([]ParsedLogEntry, 0, 1000)
			}
		}
	}
	
	// Close gzip writer
	if err := gz.Close(); err != nil {
		return fmt.Errorf("gzip close failed: %w", err)
	}
	
	// Upload to S3
	s3Key := fmt.Sprintf("%s/%s/%s/%s.gz",
		logMsg.LogType,
		logMsg.ClusterID,
		logMsg.InstanceID,
		strings.ReplaceAll(logMsg.LogFileName, "/", "_"))
	
	if _, err := bp.s3Uploader.Upload(ctx, &s3.PutObjectInput{
		Bucket: &bp.config.S3Bucket,
		Key:    &s3Key,
		Body:   bytes.NewReader(buf.Bytes()),
	}); err != nil {
		return fmt.Errorf("S3 upload failed: %w", err)
	}
	
	// Send final batch
	if len(batch) > 0 {
		if err := bp.sendBatch(ctx, logMsg, batch); err != nil {
			slog.Warn("Failed to send final batch", "error", err)
		}
	}
	
	// Verify integrity
	bp.integrityChecker.VerifyAndRecord(logMsg.LogType, logMsg.LogFileName, lineCount, int(logMsg.Size))
	
	// Update final position
	bp.updatePosition(ctx, logMsg, "end")
	
	slog.Info("Completed processing", 
		"instance_id", logMsg.InstanceID,
		"file", logMsg.LogFileName,
		"lines", lineCount,
		"s3_key", s3Key)
	
	return nil
}

// Streaming download implementation
func (bp *BatchProcessor) downloadLogStreaming(ctx context.Context, logMsg LogMessage, startMarker string) (io.ReadCloser, error) {
	pr, pw := io.Pipe()
	
	go func() {
		defer func() {
			if err := pw.Close(); err != nil {
				slog.Error("Failed to close pipe writer", "error", err)
			}
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
			
			// Update marker
			if output.Marker != nil {
				marker = *output.Marker
			}
			
			// Check if done
			if output.AdditionalDataPending == nil || !*output.AdditionalDataPending {
				return
			}
		}
	}()
	
	return pr, nil
}

func (bp *BatchProcessor) getPosition(ctx context.Context, logMsg LogMessage) LogPosition {
	result, err := bp.dynamoClient.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: &bp.config.TrackingTable,
		Key: map[string]dynamoTypes.AttributeValue{
			"instance_id":   &dynamoTypes.AttributeValueMemberS{Value: logMsg.InstanceID},
			"log_file_name": &dynamoTypes.AttributeValueMemberS{Value: logMsg.LogFileName},
		},
	})
	
	if err != nil || result.Item == nil {
		return LogPosition{LastMarker: "0"}
	}
	
	position := LogPosition{}
	if marker, ok := result.Item["last_marker"]; ok {
		if s, ok := marker.(*dynamoTypes.AttributeValueMemberS); ok {
			position.LastMarker = s.Value
		}
	}
	
	return position
}

func (bp *BatchProcessor) updatePosition(ctx context.Context, logMsg LogMessage, marker string) {
	item := map[string]dynamoTypes.AttributeValue{
		"instance_id":   &dynamoTypes.AttributeValueMemberS{Value: logMsg.InstanceID},
		"log_file_name": &dynamoTypes.AttributeValueMemberS{Value: logMsg.LogFileName},
		"last_marker":   &dynamoTypes.AttributeValueMemberS{Value: marker},
		"last_written":  &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(logMsg.LastWritten, 10)},
		"updated_at":    &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)},
	}
	
	if _, err := bp.dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: &bp.config.TrackingTable,
		Item:      item,
	}); err != nil {
		slog.Error("Failed to update position", "error", err)
	}
}

func (bp *BatchProcessor) sendBatch(ctx context.Context, logMsg LogMessage, batch []ParsedLogEntry) error {
	httpClient := bp.httpPool.Get()
	defer bp.httpPool.Put(httpClient)
	
	var buf bytes.Buffer
	for _, entry := range batch {
		if err := json.NewEncoder(&buf).Encode(entry); err != nil {
			return err
		}
	}
	
	url := fmt.Sprintf("%s/api/default/%s/_json", bp.config.OpenObserveURL, logMsg.LogType)
	req, err := http.NewRequestWithContext(ctx, "POST", url, &buf)
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

// Parser functions
func parseErrorLog(line string) ParsedLogEntry {
	// MySQL error log format: YYYY-MM-DD HH:MM:SS [ERROR] message
	parts := strings.SplitN(line, " ", 3)
	if len(parts) < 3 {
		return nil
	}
	
	return ParsedLogEntry{
		"timestamp": parts[0] + " " + parts[1],
		"level":     "ERROR",
		"message":   parts[2],
	}
}

func parseSlowQueryLog(line string) ParsedLogEntry {
	// MySQL slow query log parsing
	if strings.HasPrefix(line, "# Time:") {
		return ParsedLogEntry{
			"timestamp": strings.TrimPrefix(line, "# Time: "),
		}
	}
	if strings.HasPrefix(line, "# User@Host:") {
		return ParsedLogEntry{
			"user_host": strings.TrimPrefix(line, "# User@Host: "),
		}
	}
	if strings.HasPrefix(line, "# Query_time:") {
		parts := strings.Fields(line)
		result := ParsedLogEntry{}
		for i := 0; i < len(parts)-1; i++ {
			if strings.HasSuffix(parts[i], ":") {
				key := strings.ToLower(strings.TrimSuffix(parts[i], ":"))
				if i+1 < len(parts) {
					result[key] = parts[i+1]
				}
			}
		}
		return result
	}
	// Handle SQL statements (non-comment lines)
	if !strings.HasPrefix(line, "#") && strings.TrimSpace(line) != "" {
		return ParsedLogEntry{
			"sql": line,
		}
	}
	return nil
}

func parseGenericLog(line string) ParsedLogEntry {
	return ParsedLogEntry{
		"line": line,
		"timestamp": time.Now().Format(time.RFC3339),
	}
}