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

// RDS Cache Client implementation
type RDSCacheClient struct {
	rdsClient   *rds.Client
	redisClient *redis.Client
}

func NewRDSCacheClient(rdsClient *rds.Client, redisClient *redis.Client) *RDSCacheClient {
	return &RDSCacheClient{
		rdsClient:   rdsClient,
		redisClient: redisClient,
	}
}

func (c *RDSCacheClient) DescribeDBClusters(ctx context.Context) ([]rdsTypes.DBCluster, error) {
	cacheKey := "rds:api:clusters:list"
	
	// Try cache first
	cachedData, err := c.redisClient.Get(ctx, cacheKey).Result()
	if err == nil {
		var clusters []rdsTypes.DBCluster
		if err := json.Unmarshal([]byte(cachedData), &clusters); err == nil {
			slog.Debug("RDS API cache hit", "key", cacheKey, "count", len(clusters))
			return clusters, nil
		}
	}
	
	// Cache miss - fetch from API
	slog.Debug("RDS API cache miss", "key", cacheKey)
	var allClusters []rdsTypes.DBCluster
	
	paginator := rds.NewDescribeDBClustersPaginator(c.rdsClient, nil)
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return nil, err
		}
		allClusters = append(allClusters, page.DBClusters...)
	}
	
	// Cache for configured duration
	cacheTTL := time.Duration(getEnvAsInt("CACHE_TTL_CLUSTERS", 300)) * time.Second
	if len(allClusters) > 0 {
		if data, err := json.Marshal(allClusters); err == nil {
			if err := c.redisClient.Set(ctx, cacheKey, data, cacheTTL).Err(); err != nil {
				slog.Error("Failed to cache RDS API response", "error", err, "key", cacheKey)
			}
		}
	}
	
	return allClusters, nil
}

func (c *RDSCacheClient) DescribeDBInstances(ctx context.Context, instanceID string) (*rdsTypes.DBInstance, error) {
	cacheKey := fmt.Sprintf("rds:api:instance:%s", instanceID)
	
	// Try cache first
	cachedData, err := c.redisClient.Get(ctx, cacheKey).Result()
	if err == nil {
		var instance rdsTypes.DBInstance
		if err := json.Unmarshal([]byte(cachedData), &instance); err == nil {
			slog.Debug("RDS API cache hit", "key", cacheKey)
			return &instance, nil
		}
	}
	
	// Cache miss - fetch from API
	slog.Debug("RDS API cache miss", "key", cacheKey)
	output, err := c.rdsClient.DescribeDBInstances(ctx, &rds.DescribeDBInstancesInput{
		DBInstanceIdentifier: &instanceID,
	})
	if err != nil {
		return nil, err
	}
	
	if len(output.DBInstances) == 0 {
		return nil, fmt.Errorf("instance not found: %s", instanceID)
	}
	
	instance := &output.DBInstances[0]
	
	// Cache for configured duration
	cacheTTL := time.Duration(getEnvAsInt("CACHE_TTL_INSTANCES", 300)) * time.Second
	if data, err := json.Marshal(instance); err == nil {
		if err := c.redisClient.Set(ctx, cacheKey, data, cacheTTL).Err(); err != nil {
			slog.Error("Failed to cache RDS API response", "error", err, "key", cacheKey)
		}
	}
	
	return instance, nil
}

func (c *RDSCacheClient) DescribeDBLogFiles(ctx context.Context, instanceID string) ([]rdsTypes.DescribeDBLogFilesDetails, error) {
	cacheKey := fmt.Sprintf("rds:api:logfiles:%s", instanceID)
	
	// Try cache first
	cachedData, err := c.redisClient.Get(ctx, cacheKey).Result()
	if err == nil {
		var logFiles []rdsTypes.DescribeDBLogFilesDetails
		if err := json.Unmarshal([]byte(cachedData), &logFiles); err == nil {
			slog.Debug("RDS API cache hit", "key", cacheKey, "count", len(logFiles))
			return logFiles, nil
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
			return nil, err
		}
		allLogFiles = append(allLogFiles, page.DescribeDBLogFiles...)
	}
	
	// Cache for configured duration (log files change frequently)
	cacheTTL := time.Duration(getEnvAsInt("CACHE_TTL_LOGFILES", 60)) * time.Second
	if len(allLogFiles) > 0 {
		if data, err := json.Marshal(allLogFiles); err == nil {
			if err := c.redisClient.Set(ctx, cacheKey, data, cacheTTL).Err(); err != nil {
				slog.Error("Failed to cache RDS API response", "error", err, "key", cacheKey)
			}
		}
	}
	
	return allLogFiles, nil
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

func (m *MetricsExporter) RecordHistogram(name string, value float64) {
	// Simplified for consolidation
	slog.Debug("Metric recorded", "name", name, "value", value)
}

// Main Discovery Service
type Config struct {
	KafkaBrokers      []string
	InstanceTable     string
	TrackingTable     string
	ValkeyURL         string
	LogLevel          string
	ShardID           int
	TotalShards       int
	Region            string
	RateLimitPerSec   int
	DiscoveryInterval time.Duration
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
	dynamoClient     *dynamodb.Client
	kafkaWriter      *kafka.Writer
	redisClient      *redis.Client
	limiter          *rate.Limiter
	metricsExporter  *MetricsExporter
	circuitBreaker   *CircuitBreaker
	shutdownChan     chan struct{}
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	slog.Info("Starting Aurora Log Discovery Service", "version", "1.0", "go_version", runtime.Version())

	if len(os.Args) > 1 && os.Args[1] == "-health" {
		fmt.Println("OK")
		os.Exit(0)
	}

	cfg := Config{
		KafkaBrokers:      strings.Split(os.Getenv("KAFKA_BROKERS"), ","),
		InstanceTable:     os.Getenv("INSTANCE_TABLE"),
		TrackingTable:     os.Getenv("TRACKING_TABLE"),
		ValkeyURL:         os.Getenv("VALKEY_URL"),
		LogLevel:          getEnvOrDefault("LOG_LEVEL", "INFO"),
		ShardID:           getEnvAsInt("SHARD_ID", 0),
		TotalShards:       getEnvAsInt("TOTAL_SHARDS", 1),
		Region:            os.Getenv("AWS_REGION"),
		RateLimitPerSec:   getEnvAsInt("RATE_LIMIT_PER_SEC", 100),
		DiscoveryInterval: time.Duration(getEnvAsInt("DISCOVERY_INTERVAL_MIN", 5)) * time.Minute,
	}

	awsCfg, err := config.LoadDefaultConfig(context.Background(), config.WithRegion(cfg.Region))
	if err != nil {
		slog.Error("Failed to load AWS config", "error", err)
		os.Exit(1)
	}

	kafkaWriter := &kafka.Writer{
		Addr:         kafka.TCP(cfg.KafkaBrokers...),
		Balancer:     &kafka.LeastBytes{},
		MaxAttempts:  3,
		BatchSize:    100,
		BatchTimeout: 1 * time.Second,
		Compression:  kafka.Snappy,
		RequiredAcks: kafka.RequireOne,
	}
	defer func() {
		if err := kafkaWriter.Close(); err != nil {
			slog.Error("Failed to close kafka writer", "error", err)
		}
	}()

	rdsClient := rds.NewFromConfig(awsCfg)
	dynamoClient := dynamodb.NewFromConfig(awsCfg)
	
	redisClient := redis.NewClient(&redis.Options{
		Addr: strings.TrimPrefix(cfg.ValkeyURL, "redis://"),
	})
	
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

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		select {
		case sig := <-sigChan:
			slog.Info("Received shutdown signal", "signal", sig)
			close(discovery.shutdownChan)
			cancel()
		case <-ctx.Done():
		}
	}()

	discovery.start(ctx)
}

func (d *Discovery) start(ctx context.Context) {
	slog.Info("Discovery service started", 
		"shard_id", d.config.ShardID, 
		"total_shards", d.config.TotalShards,
		"interval", d.config.DiscoveryInterval)

	ticker := time.NewTicker(d.config.DiscoveryInterval)
	defer ticker.Stop()

	// Run discovery immediately
	d.discover(ctx)

	for {
		select {
		case <-ticker.C:
			d.discover(ctx)
		case <-d.shutdownChan:
			slog.Info("Shutting down discovery service")
			return
		case <-ctx.Done():
			return
		}
	}
}

func (d *Discovery) discover(ctx context.Context) {
	startTime := time.Now()
	defer func() {
		d.metricsExporter.RecordHistogram("discovery_duration_seconds", time.Since(startTime).Seconds())
	}()

	// Use cached RDS API call with rate limiting
	err := d.limiter.Wait(ctx)
	if err != nil {
		slog.Error("Rate limiter error", "error", err)
		return
	}

	clusters, err := d.rdsCacheClient.DescribeDBClusters(ctx)
	if err != nil {
		slog.Error("Failed to describe clusters", "error", err)
		d.metricsExporter.IncrementCounter("discovery_errors", 1)
		return
	}

	slog.Info("Discovered clusters", "count", len(clusters))

	eg, ctx := errgroup.WithContext(ctx)
	eg.SetLimit(10) // Process up to 10 clusters concurrently

	for _, cluster := range clusters {
		cluster := cluster
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
	if d.config.TotalShards <= 1 {
		return true
	}
	clusterID := aws.ToString(cluster.DBClusterIdentifier)
	hash := 0
	for _, ch := range clusterID {
		hash = hash*31 + int(ch)
	}
	return hash%d.config.TotalShards == d.config.ShardID
}

func (d *Discovery) processCluster(ctx context.Context, cluster rdsTypes.DBCluster) error {
	clusterID := aws.ToString(cluster.DBClusterIdentifier)
	
	// Only process Aurora clusters
	if !strings.HasPrefix(aws.ToString(cluster.Engine), "aurora") {
		return nil
	}

	// Skip saving cluster-only details as the instance table requires both cluster_id and instance_id
	// Cluster information will be saved along with each instance

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
	// Use cached RDS API call
	err := d.limiter.Wait(ctx)
	if err != nil {
		return err
	}

	logFiles, err := d.rdsCacheClient.DescribeDBLogFiles(ctx, instanceID)
	if err != nil {
		return fmt.Errorf("failed to describe log files: %w", err)
	}

	// Process each log file
	for _, logFile := range logFiles {
		logType := d.getLogType(aws.ToString(logFile.LogFileName))
		if logType == "" {
			continue // Skip non-error/slow-query logs
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

		// Check if log file has been modified
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
	if strings.Contains(fileName, "slowquery") {
		return "slowquery"
	}
	return ""
}

func (d *Discovery) shouldProcessLog(ctx context.Context, logInfo LogFileInfo) bool {
	// Check tracking table to see if we've already processed this file
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
		return true // New file
	}

	// Check if file has been modified
	if lastWrittenAttr, ok := result.Item["last_written"]; ok {
		if lastWrittenVal, ok := lastWrittenAttr.(*dynamoTypes.AttributeValueMemberN); ok {
			lastWritten, _ := strconv.ParseInt(lastWrittenVal.Value, 10, 64)
			return logInfo.LastWritten > lastWritten
		}
	}

	return true
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
		"cluster_id":   &dynamoTypes.AttributeValueMemberS{Value: aws.ToString(cluster.DBClusterIdentifier)},
		"engine":       &dynamoTypes.AttributeValueMemberS{Value: aws.ToString(cluster.Engine)},
		"status":       &dynamoTypes.AttributeValueMemberS{Value: aws.ToString(cluster.Status)},
		"endpoint":     &dynamoTypes.AttributeValueMemberS{Value: aws.ToString(cluster.Endpoint)},
		"updated_at":   &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)},
		"ttl":          &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Add(time.Duration(getEnvAsInt("DYNAMODB_TTL_DAYS", 7))*24*time.Hour).Unix(), 10)},
	}

	_, err := d.dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: &d.config.InstanceTable,
		Item:      item,
	})
	return err
}

func (d *Discovery) saveInstanceDetails(ctx context.Context, instanceID, clusterID string, member rdsTypes.DBClusterMember) error {
	// Use cached RDS API call
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
		"ttl":               &dynamoTypes.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Add(time.Duration(getEnvAsInt("DYNAMODB_TTL_DAYS", 7))*24*time.Hour).Unix(), 10)},
	}

	_, err = d.dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: &d.config.InstanceTable,
		Item:      item,
	})
	return err
}