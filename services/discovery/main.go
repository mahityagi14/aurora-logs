package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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
	rdsTypes "github.com/aws/aws-sdk-go-v2/service/rds/types"
	"github.com/redis/go-redis/v9"
	"github.com/segmentio/kafka-go"
	"golang.org/x/sync/errgroup"
	"golang.org/x/time/rate"
)

// ============================================================================
// Helper Functions
// ============================================================================

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

// ============================================================================
// RDS Cache Client - Caches RDS API responses in Redis
// ============================================================================

// RDSClientInterface defines the interface for RDS operations
type RDSClientInterface interface {
	DescribeDBClusters(ctx context.Context, params *rds.DescribeDBClustersInput, optFns ...func(*rds.Options)) (*rds.DescribeDBClustersOutput, error)
	DescribeDBInstances(ctx context.Context, params *rds.DescribeDBInstancesInput, optFns ...func(*rds.Options)) (*rds.DescribeDBInstancesOutput, error)
	DescribeDBLogFiles(ctx context.Context, params *rds.DescribeDBLogFilesInput, optFns ...func(*rds.Options)) (*rds.DescribeDBLogFilesOutput, error)
}

// DynamoDBClientInterface defines the interface for DynamoDB operations
type DynamoDBClientInterface interface {
	GetItem(ctx context.Context, params *dynamodb.GetItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error)
	PutItem(ctx context.Context, params *dynamodb.PutItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error)
	Query(ctx context.Context, params *dynamodb.QueryInput, optFns ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error)
	UpdateItem(ctx context.Context, params *dynamodb.UpdateItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error)
}

type RDSCacheClient struct {
	rdsClient   RDSClientInterface
	redisClient *redis.Client
}

func NewRDSCacheClient(rdsClient RDSClientInterface, redisClient *redis.Client) *RDSCacheClient {
	return &RDSCacheClient{
		rdsClient:   rdsClient,
		redisClient: redisClient,
	}
}

// DescribeDBClusters fetches all DB clusters with caching
func (c *RDSCacheClient) DescribeDBClusters(ctx context.Context) ([]rdsTypes.DBCluster, error) {
	cacheKey := "rds:api:clusters:list"
	
	// Try cache first
	if c.redisClient != nil {
		if cached := c.getFromCache(ctx, cacheKey); cached != nil {
			var clusters []rdsTypes.DBCluster
			if err := json.Unmarshal(cached, &clusters); err == nil {
				slog.Debug("RDS API cache hit", "key", cacheKey, "count", len(clusters))
				return clusters, nil
			}
		}
	}
	
	// Cache miss - fetch from API
	slog.Debug("RDS API cache miss", "key", cacheKey)
	var allClusters []rdsTypes.DBCluster
	
	paginator := rds.NewDescribeDBClustersPaginator(c.rdsClient, nil)
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return nil, fmt.Errorf("failed to describe clusters: %w", err)
		}
		allClusters = append(allClusters, page.DBClusters...)
	}
	
	// Cache the response
	if len(allClusters) > 0 {
		c.setCache(ctx, cacheKey, allClusters, 5*time.Minute)
	}
	
	return allClusters, nil
}

// DescribeDBInstances fetches instance details with caching
func (c *RDSCacheClient) DescribeDBInstances(ctx context.Context, instanceID string) (*rdsTypes.DBInstance, error) {
	cacheKey := fmt.Sprintf("rds:api:instance:%s", instanceID)
	
	// Try cache first
	if c.redisClient != nil {
		if cached := c.getFromCache(ctx, cacheKey); cached != nil {
			var instance rdsTypes.DBInstance
			if err := json.Unmarshal(cached, &instance); err == nil {
				slog.Debug("RDS API cache hit", "key", cacheKey)
				return &instance, nil
			}
		}
	}
	
	// Cache miss - fetch from API
	slog.Debug("RDS API cache miss", "key", cacheKey)
	output, err := c.rdsClient.DescribeDBInstances(ctx, &rds.DescribeDBInstancesInput{
		DBInstanceIdentifier: &instanceID,
	})
	
	if err != nil {
		return nil, fmt.Errorf("failed to describe instance %s: %w", instanceID, err)
	}
	
	if len(output.DBInstances) == 0 {
		return nil, fmt.Errorf("instance %s not found", instanceID)
	}
	
	instance := &output.DBInstances[0]
	
	// Cache the response
	c.setCache(ctx, cacheKey, instance, 5*time.Minute)
	
	return instance, nil
}

// DescribeDBLogFiles fetches log files for an instance with caching
func (c *RDSCacheClient) DescribeDBLogFiles(ctx context.Context, instanceID string) ([]rdsTypes.DescribeDBLogFilesDetails, error) {
	cacheKey := fmt.Sprintf("rds:api:logfiles:%s", instanceID)
	
	// Try cache first
	if c.redisClient != nil {
		if cached := c.getFromCache(ctx, cacheKey); cached != nil {
			var logFiles []rdsTypes.DescribeDBLogFilesDetails
			if err := json.Unmarshal(cached, &logFiles); err == nil {
				slog.Debug("RDS API cache hit", "key", cacheKey, "count", len(logFiles))
				return logFiles, nil
			}
		}
	}
	
	// Cache miss - fetch from API
	slog.Debug("RDS API cache miss", "key", cacheKey)
	var allLogFiles []rdsTypes.DescribeDBLogFilesDetails
	
	paginator := rds.NewDescribeDBLogFilesPaginator(c.rdsClient, &rds.DescribeDBLogFilesInput{
		DBInstanceIdentifier: &instanceID,
	})
	
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return nil, fmt.Errorf("failed to describe log files for %s: %w", instanceID, err)
		}
		allLogFiles = append(allLogFiles, page.DescribeDBLogFiles...)
	}
	
	// Cache for shorter duration (log files change frequently)
	if len(allLogFiles) > 0 {
		c.setCache(ctx, cacheKey, allLogFiles, 1*time.Minute)
	}
	
	return allLogFiles, nil
}

// Helper methods for cache operations
func (c *RDSCacheClient) getFromCache(ctx context.Context, key string) []byte {
	if c.redisClient == nil {
		return nil
	}
	
	data, err := c.redisClient.Get(ctx, key).Bytes()
	if err != nil && err != redis.Nil {
		slog.Debug("Cache error", "error", err, "key", key)
	}
	return data
}

func (c *RDSCacheClient) setCache(ctx context.Context, key string, value interface{}, ttl time.Duration) {
	if c.redisClient == nil {
		return
	}
	
	data, err := json.Marshal(value)
	if err != nil {
		slog.Debug("Failed to marshal for cache", "error", err, "key", key)
		return
	}
	
	if err := c.redisClient.Set(ctx, key, data, ttl).Err(); err != nil {
		slog.Debug("Failed to set cache", "error", err, "key", key)
	}
}

// ============================================================================
// Circuit Breaker - Protects against cascading failures
// ============================================================================

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

// ============================================================================
// Metrics Exporter - Sends metrics to OpenObserve
// ============================================================================

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

func (m *MetricsExporter) RecordHistogram(name string, value float64) {
	slog.Debug("Metric recorded", "name", name, "value", value)
}

// ============================================================================
// Main Types
// ============================================================================

type Config struct {
	KafkaBrokers      []string
	InstanceTable     string
	TrackingTable     string
	ValkeyURL         string
	LogLevel          string
	ShardID           int
	TotalShards       int
	DiscoveryInterval time.Duration
	RateLimitPerSec   int
	Region            string
}

type LogFileInfo struct {
	InstanceID   string    `json:"instance_id"`
	ClusterID    string    `json:"cluster_id"`
	Engine       string    `json:"engine"`
	LogType      string    `json:"log_type"`
	LogFileName  string    `json:"log_file_name"`
	LastWritten  int64     `json:"last_written"`
	Size         int64     `json:"size"`
	Timestamp    time.Time `json:"timestamp"`
}

type Discovery struct {
	config           Config
	rdsClient        *rds.Client
	rdsCacheClient   *RDSCacheClient
	dynamoClient     DynamoDBClientInterface
	kafkaWriter      *kafka.Writer
	redisClient      *redis.Client
	limiter          *rate.Limiter
	metricsExporter  *MetricsExporter
	circuitBreaker   *CircuitBreaker
	shutdownChan     chan struct{}
}

// ============================================================================
// Main Function
// ============================================================================

func main() {
	// Configure logging
	logLevel := slog.LevelInfo
	if os.Getenv("LOG_LEVEL") == "DEBUG" {
		logLevel = slog.LevelDebug
	}
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: logLevel}))
	slog.SetDefault(logger)

	slog.Info("Starting Aurora Log Discovery Service", 
		"version", "2.0",
		"go_version", runtime.Version(),
		"pid", os.Getpid())

	// Health check endpoint
	if len(os.Args) > 1 && os.Args[1] == "-health" {
		fmt.Println("OK")
		os.Exit(0)
	}

	// Load configuration
	cfg := Config{
		KafkaBrokers:      strings.Split(os.Getenv("KAFKA_BROKERS"), ","),
		InstanceTable:     os.Getenv("INSTANCE_TABLE"),
		TrackingTable:     os.Getenv("TRACKING_TABLE"),
		ValkeyURL:         os.Getenv("VALKEY_URL"),
		LogLevel:          getEnvOrDefault("LOG_LEVEL", "INFO"),
		ShardID:           getEnvAsInt("SHARD_ID", 0),
		TotalShards:       getEnvAsInt("TOTAL_SHARDS", 1),
		DiscoveryInterval: time.Duration(getEnvAsInt("DISCOVERY_INTERVAL_MIN", 5)) * time.Minute,
		RateLimitPerSec:   getEnvAsInt("RDS_API_RATE_LIMIT", 10),
		Region:            os.Getenv("AWS_REGION"),
	}

	// Configure AWS SDK
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

	// Initialize Kafka writer
	kafkaWriter := kafka.NewWriter(kafka.WriterConfig{
		Brokers:      cfg.KafkaBrokers,
		Async:        true,
		BatchSize:    100,
		BatchTimeout: 1 * time.Second,
		ErrorLogger: kafka.LoggerFunc(func(msg string, args ...interface{}) {
			slog.Error("Kafka error", "msg", fmt.Sprintf(msg, args...))
		}),
	})
	defer kafkaWriter.Close()

	// Initialize Redis client
	rdsClient := rds.NewFromConfig(awsCfg)
	dynamoClient := dynamodb.NewFromConfig(awsCfg)
	
	redisClient := redis.NewClient(&redis.Options{
		Addr:            strings.TrimPrefix(cfg.ValkeyURL, "redis://"),
		DialTimeout:     2 * time.Second,
		ReadTimeout:     2 * time.Second,
		WriteTimeout:    2 * time.Second,
		MaxRetries:      1,
		MinRetryBackoff: 100 * time.Millisecond,
		MaxRetryBackoff: 500 * time.Millisecond,
	})
	
	// Test Redis connection but don't fail if unavailable
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := redisClient.Ping(ctx).Err(); err != nil {
		slog.Warn("Redis/Valkey not available, will operate without cache", "error", err)
	}
	
	// Initialize services
	metricsExporter := NewMetricsExporter(
		os.Getenv("OPENOBSERVE_URL"),
		os.Getenv("OPENOBSERVE_USER"),
		os.Getenv("OPENOBSERVE_PASS"),
	)
	
	rdsCacheClient := NewRDSCacheClient(rdsClient, redisClient)

	discovery := &Discovery{
		config:          cfg,
		rdsClient:       rdsClient,
		rdsCacheClient:  rdsCacheClient,
		dynamoClient:    dynamoClient,
		kafkaWriter:     kafkaWriter,
		redisClient:     redisClient,
		limiter:         rate.NewLimiter(rate.Limit(cfg.RateLimitPerSec), cfg.RateLimitPerSec),
		metricsExporter: metricsExporter,
		circuitBreaker:  NewCircuitBreaker(5, 30*time.Second),
		shutdownChan:    make(chan struct{}),
	}

	// Handle graceful shutdown
	ctx, cancelFunc := context.WithCancel(context.Background())
	defer cancelFunc()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		sig := <-sigChan
		slog.Info("Received shutdown signal", "signal", sig)
		close(discovery.shutdownChan)
		cancelFunc()
	}()

	// Start discovery
	if err := discovery.Start(ctx); err != nil {
		slog.Error("Discovery failed", "error", err)
		os.Exit(1)
	}
}

// ============================================================================
// Discovery Methods
// ============================================================================

func (d *Discovery) Start(ctx context.Context) error {
	slog.Info("Discovery service started", 
		"shard_id", d.config.ShardID,
		"total_shards", d.config.TotalShards,
		"discovery_interval", d.config.DiscoveryInterval)

	// Run discovery immediately
	d.discoverClusters(ctx)

	// Schedule periodic discovery
	ticker := time.NewTicker(d.config.DiscoveryInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			slog.Info("Discovery service stopping")
			return ctx.Err()
		case <-d.shutdownChan:
			slog.Info("Discovery service shutdown requested")
			return nil
		case <-ticker.C:
			d.discoverClusters(ctx)
		}
	}
}

func (d *Discovery) discoverClusters(ctx context.Context) {
	startTime := time.Now()
	defer func() {
		d.metricsExporter.RecordHistogram("discovery_duration_seconds", time.Since(startTime).Seconds())
	}()

	// Rate limit RDS API calls
	if err := d.limiter.Wait(ctx); err != nil {
		slog.Error("Rate limiter error", "error", err)
		return
	}

	// Fetch all clusters using cached client
	clusters, err := d.rdsCacheClient.DescribeDBClusters(ctx)
	if err != nil {
		slog.Error("Failed to describe clusters", "error", err)
		d.metricsExporter.IncrementCounter("discovery_errors", 1)
		return
	}

	slog.Info("Discovered clusters", "count", len(clusters))
	d.metricsExporter.IncrementCounter("clusters_discovered", int64(len(clusters)))

	// Process clusters in parallel
	eg, ctx := errgroup.WithContext(ctx)
	eg.SetLimit(10) // Limit concurrent processing

	for _, cluster := range clusters {
		cluster := cluster // Capture range variable
		if d.shouldProcessCluster(cluster) {
			eg.Go(func() error {
				return d.processCluster(ctx, cluster)
			})
		}
	}

	if err := eg.Wait(); err != nil {
		slog.Error("Error processing clusters", "error", err)
	}
}

func (d *Discovery) shouldProcessCluster(cluster rdsTypes.DBCluster) bool {
	// Only process Aurora clusters
	if !strings.HasPrefix(aws.ToString(cluster.Engine), "aurora") {
		return false
	}
	
	// Simple sharding based on cluster ID
	clusterID := aws.ToString(cluster.DBClusterIdentifier)
	hash := 0
	for _, c := range clusterID {
		hash = (hash*31 + int(c)) % d.config.TotalShards
	}
	
	return hash == d.config.ShardID
}

func (d *Discovery) processCluster(ctx context.Context, cluster rdsTypes.DBCluster) error {
	clusterID := aws.ToString(cluster.DBClusterIdentifier)
	
	// Save cluster details
	if err := d.saveClusterDetails(ctx, cluster); err != nil {
		slog.Error("Failed to save cluster details", "error", err, "cluster_id", clusterID)
	}
	
	// Process each cluster member
	for _, member := range cluster.DBClusterMembers {
		if err := d.processInstance(ctx, aws.ToString(member.DBInstanceIdentifier), clusterID, member); err != nil {
			slog.Error("Failed to process instance", 
				"error", err, 
				"instance_id", aws.ToString(member.DBInstanceIdentifier))
		}
	}
	
	return nil
}

func (d *Discovery) processInstance(ctx context.Context, instanceID, clusterID string, member rdsTypes.DBClusterMember) error {
	// Rate limit
	if err := d.limiter.Wait(ctx); err != nil {
		return err
	}

	// Get log files using cached client
	logFiles, err := d.rdsCacheClient.DescribeDBLogFiles(ctx, instanceID)
	if err != nil {
		return fmt.Errorf("failed to describe log files: %w", err)
	}

	slog.Debug("Found log files", "instance_id", instanceID, "count", len(logFiles))

	// Process each log file
	for _, logFile := range logFiles {
		logType := d.getLogType(aws.ToString(logFile.LogFileName))
		if logType == "" {
			continue // Skip non-error/slowquery logs
		}

		logInfo := LogFileInfo{
			InstanceID:  instanceID,
			ClusterID:   clusterID,
			Engine:      "aurora-mysql",
			LogType:     logType,
			LogFileName: aws.ToString(logFile.LogFileName),
			LastWritten: aws.ToInt64(logFile.LastWritten),
			Size:        aws.ToInt64(logFile.Size),
			Timestamp:   time.Now(),
		}

		// Check if we should process this log file
		if d.shouldProcessLog(ctx, logInfo) {
			if err := d.publishLogInfo(ctx, logInfo); err != nil {
				slog.Error("Failed to publish log info", "error", err, "file", logInfo.LogFileName)
			}
		}
	}

	// Save instance details
	return d.saveInstanceDetails(ctx, instanceID, clusterID, member)
}

func (d *Discovery) getLogType(fileName string) string {
	if strings.Contains(fileName, "error") {
		return "error"
	}
	if strings.Contains(fileName, "slowquery") || strings.Contains(fileName, "slow") {
		return "slowquery"
	}
	return ""
}

func (d *Discovery) shouldProcessLog(ctx context.Context, logInfo LogFileInfo) bool {
	// Check tracking table
	result, err := d.dynamoClient.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: &d.config.TrackingTable,
		Key: map[string]dynamoTypes.AttributeValue{
			"instance_id":   &dynamoTypes.AttributeValueMemberS{Value: logInfo.InstanceID},
			"log_file_name": &dynamoTypes.AttributeValueMemberS{Value: logInfo.LogFileName},
		},
	})

	if err != nil {
		slog.Error("Failed to check tracking table", "error", err)
		return true // Process on error
	}

	if result.Item == nil {
		// New file - write to tracking table with 'discovered' status
		d.writeTrackingEntry(ctx, logInfo, "discovered")
		return true
	}

	// Check status
	if statusAttr, ok := result.Item["status"]; ok {
		if statusVal, ok := statusAttr.(*dynamoTypes.AttributeValueMemberS); ok {
			if statusVal.Value == "completed" {
				// Check if file has been modified
				if lastWrittenAttr, ok := result.Item["last_written"]; ok {
					if lastWrittenVal, ok := lastWrittenAttr.(*dynamoTypes.AttributeValueMemberN); ok {
						lastWritten, _ := strconv.ParseInt(lastWrittenVal.Value, 10, 64)
						if logInfo.LastWritten > lastWritten {
							// File modified - update to 'discovered' status
							d.updateTrackingStatus(ctx, logInfo, "discovered")
							return true
						}
						return false // File not modified
					}
				}
			} else if statusVal.Value == "processing" || statusVal.Value == "discovered" {
				return false // Already being processed
			}
		}
	}

	return true
}

func (d *Discovery) writeTrackingEntry(ctx context.Context, logInfo LogFileInfo, status string) {
	item := map[string]dynamoTypes.AttributeValue{
		"instance_id":   &dynamoTypes.AttributeValueMemberS{Value: logInfo.InstanceID},
		"log_file_name": &dynamoTypes.AttributeValueMemberS{Value: logInfo.LogFileName},
		"cluster_id":    &dynamoTypes.AttributeValueMemberS{Value: logInfo.ClusterID},
		"log_type":      &dynamoTypes.AttributeValueMemberS{Value: logInfo.LogType},
		"status":        &dynamoTypes.AttributeValueMemberS{Value: status},
		"discovered_at": &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)},
		"last_written":  &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(logInfo.LastWritten, 10)},
		"file_size":     &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(logInfo.Size, 10)},
	}
	
	if _, err := d.dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: &d.config.TrackingTable,
		Item:      item,
	}); err != nil {
		slog.Error("Failed to write tracking entry", "error", err)
	}
}

func (d *Discovery) updateTrackingStatus(ctx context.Context, logInfo LogFileInfo, status string) {
	updateExpr := "SET #status = :status, discovered_at = :discovered_at, last_written = :last_written, file_size = :file_size"
	
	_, err := d.dynamoClient.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: &d.config.TrackingTable,
		Key: map[string]dynamoTypes.AttributeValue{
			"instance_id":   &dynamoTypes.AttributeValueMemberS{Value: logInfo.InstanceID},
			"log_file_name": &dynamoTypes.AttributeValueMemberS{Value: logInfo.LogFileName},
		},
		UpdateExpression: &updateExpr,
		ExpressionAttributeNames: map[string]string{
			"#status": "status",
		},
		ExpressionAttributeValues: map[string]dynamoTypes.AttributeValue{
			":status":        &dynamoTypes.AttributeValueMemberS{Value: status},
			":discovered_at": &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)},
			":last_written":  &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(logInfo.LastWritten, 10)},
			":file_size":     &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(logInfo.Size, 10)},
		},
	})
	
	if err != nil {
		slog.Error("Failed to update tracking entry", "error", err)
	}
}

func (d *Discovery) publishLogInfo(ctx context.Context, logInfo LogFileInfo) error {
	data, err := json.Marshal(logInfo)
	if err != nil {
		return err
	}

	topic := fmt.Sprintf("aurora-logs-%s", logInfo.LogType)
	return d.kafkaWriter.WriteMessages(ctx, kafka.Message{
		Topic: topic,
		Key:   []byte(logInfo.InstanceID),
		Value: data,
	})
}

func (d *Discovery) saveClusterDetails(ctx context.Context, cluster rdsTypes.DBCluster) error {
	item := map[string]dynamoTypes.AttributeValue{
		"cluster_id": &dynamoTypes.AttributeValueMemberS{Value: aws.ToString(cluster.DBClusterIdentifier)},
		"engine":     &dynamoTypes.AttributeValueMemberS{Value: aws.ToString(cluster.Engine)},
		"status":     &dynamoTypes.AttributeValueMemberS{Value: aws.ToString(cluster.Status)},
		"endpoint":   &dynamoTypes.AttributeValueMemberS{Value: aws.ToString(cluster.Endpoint)},
		"updated_at": &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)},
	}

	_, err := d.dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: &d.config.InstanceTable,
		Item:      item,
	})
	return err
}

func (d *Discovery) saveInstanceDetails(ctx context.Context, instanceID, clusterID string, member rdsTypes.DBClusterMember) error {
	// Get instance details using cached client
	instance, err := d.rdsCacheClient.DescribeDBInstances(ctx, instanceID)
	if err != nil {
		return err
	}

	item := map[string]dynamoTypes.AttributeValue{
		"instance_id":       &dynamoTypes.AttributeValueMemberS{Value: instanceID},
		"cluster_id":        &dynamoTypes.AttributeValueMemberS{Value: clusterID},
		"instance_class":    &dynamoTypes.AttributeValueMemberS{Value: aws.ToString(instance.DBInstanceClass)},
		"is_cluster_writer": &dynamoTypes.AttributeValueMemberBOOL{Value: aws.ToBool(member.IsClusterWriter)},
		"status":            &dynamoTypes.AttributeValueMemberS{Value: aws.ToString(instance.DBInstanceStatus)},
		"updated_at":        &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)},
	}

	_, err = d.dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: &d.config.InstanceTable,
		Item:      item,
	})
	return err
}