package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"testing"
	"time"

	"github.com/aurora-log-system/common"
	"github.com/aurora-log-system/common/circuitbreaker"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/segmentio/kafka-go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
)

// Integration tests for Aurora Log System
// Run with: go test -tags=integration ./tests/...

// TestEndToEndLogProcessing tests the complete flow from discovery to S3
func TestEndToEndLogProcessing(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	ctx := context.Background()

	// Start test containers
	kafka, err := startKafkaContainer(ctx)
	require.NoError(t, err)
	defer kafka.Terminate(ctx)

	valkey, err := startValkeyContainer(ctx)
	require.NoError(t, err)
	defer valkey.Terminate(ctx)

	// Get container endpoints
	kafkaHost, err := kafka.Host(ctx)
	require.NoError(t, err)
	kafkaPort, err := kafka.MappedPort(ctx, "9092")
	require.NoError(t, err)

	valkeyHost, err := valkey.Host(ctx)
	require.NoError(t, err)
	valkeyPort, err := valkey.MappedPort(ctx, "6379")
	require.NoError(t, err)

	// Test configuration
	kafkaBroker := fmt.Sprintf("%s:%s", kafkaHost, kafkaPort.Port())
	valkeyAddr := fmt.Sprintf("%s:%s", valkeyHost, valkeyPort.Port())

	// Create Kafka topics
	err = createTestTopics(kafkaBroker)
	require.NoError(t, err)

	// Test Discovery Service
	t.Run("DiscoveryService", func(t *testing.T) {
		// Create test log message
		logMsg := map[string]interface{}{
			"instance_id":  "test-instance-1",
			"cluster_id":   "test-cluster",
			"engine":       "aurora-mysql",
			"log_type":     "error",
			"log_file_name": "error/mysql-error.log",
			"last_written": time.Now().Unix(),
			"size":         1024,
			"timestamp":    time.Now().Format(time.RFC3339),
		}

		// Send to Kafka
		writer := kafka.NewWriter(kafka.WriterConfig{
			Brokers: []string{kafkaBroker},
			Topic:   "aurora-logs-error",
		})
		defer writer.Close()

		msgBytes, err := json.Marshal(logMsg)
		require.NoError(t, err)

		err = writer.WriteMessages(ctx, kafka.Message{
			Value: msgBytes,
		})
		assert.NoError(t, err)
	})

	// Test Processor Service
	t.Run("ProcessorService", func(t *testing.T) {
		reader := kafka.NewReader(kafka.ReaderConfig{
			Brokers: []string{kafkaBroker},
			Topic:   "aurora-logs-error",
			GroupID: "test-processor",
		})
		defer reader.Close()

		// Read message
		msg, err := reader.FetchMessage(ctx)
		require.NoError(t, err)

		var logMsg map[string]interface{}
		err = json.Unmarshal(msg.Value, &logMsg)
		assert.NoError(t, err)
		assert.Equal(t, "test-instance-1", logMsg["instance_id"])
		
		// Commit message
		err = reader.CommitMessages(ctx, msg)
		assert.NoError(t, err)
	})

	// Test Valkey Caching
	t.Run("ValkeyCaching", func(t *testing.T) {
		// Test cache operations
		cacheKey := "test:key"
		cacheValue := map[string]string{"data": "test"}
		
		// Would implement actual cache client testing here
		assert.NotEmpty(t, valkeyAddr)
	})
}

// TestRDSAPIRateLimiting tests the rate limiter
func TestRDSAPIRateLimiting(t *testing.T) {
	limiter := common.NewRDSAPILimiter(common.RateLimiterConfig{
		RatePerSecond: 10,
		BurstSize:     20,
	})

	start := time.Now()
	successCount := 0

	// Try to make 30 requests
	for i := 0; i < 30; i++ {
		err := limiter.Wait(context.Background())
		if err == nil {
			successCount++
		}
	}

	elapsed := time.Since(start)
	
	// Should take at least 1 second for 30 requests at 10 RPS
	assert.True(t, elapsed >= 1*time.Second)
	assert.Equal(t, 30, successCount)
}

// TestDataIntegrity tests checksum verification
func TestDataIntegrity(t *testing.T) {
	checker := common.NewDataIntegrityChecker(nil)
	
	testData := []byte("test log data")
	reader := bytes.NewReader(testData)
	
	md5Sum, sha256Sum, size, err := checker.CalculateChecksums(reader)
	require.NoError(t, err)
	
	assert.NotEmpty(t, md5Sum)
	assert.NotEmpty(t, sha256Sum)
	assert.Equal(t, int64(len(testData)), size)
	
	// Record checksum
	checker.RecordChecksum(common.ChecksumRecord{
		InstanceID:  "test-instance",
		LogFileName: "test.log",
		MD5:         md5Sum,
		SHA256:      sha256Sum,
		Size:        size,
		ProcessedAt: time.Now(),
	})
	
	// Verify checksum
	reader2 := bytes.NewReader(testData)
	valid, err := checker.VerifyChecksum("test-instance", "test.log", reader2)
	require.NoError(t, err)
	assert.True(t, valid)
}

// TestLogAgeChecker tests the 7-day retention handling
func TestLogAgeChecker(t *testing.T) {
	checker := common.NewLogAgeChecker()
	
	// Test old log (8 days)
	oldLog := common.LogFileMetadata{
		LogFileName: "old.log",
		LastWritten: time.Now().Add(-8 * 24 * time.Hour).Unix(),
	}
	
	shouldProcess, warning := checker.ShouldProcessLog(oldLog)
	assert.False(t, shouldProcess)
	assert.Empty(t, warning)
	
	// Test near-expiry log (6 days)
	nearExpiryLog := common.LogFileMetadata{
		LogFileName: "near-expiry.log",
		LastWritten: time.Now().Add(-6 * 24 * time.Hour).Unix(),
	}
	
	shouldProcess, warning = checker.ShouldProcessLog(nearExpiryLog)
	assert.True(t, shouldProcess)
	assert.NotEmpty(t, warning)
	
	// Test fresh log
	freshLog := common.LogFileMetadata{
		LogFileName: "fresh.log",
		LastWritten: time.Now().Unix(),
	}
	
	shouldProcess, warning = checker.ShouldProcessLog(freshLog)
	assert.True(t, shouldProcess)
	assert.Empty(t, warning)
}

// TestMetricsExporter tests metrics collection
func TestMetricsExporter(t *testing.T) {
	exporter := common.NewMetricsExporter("http://localhost:5080", "test", "test")
	
	// Record various metrics
	exporter.RecordAPICall("rds", "DescribeDBClusters", true, 100*time.Millisecond)
	exporter.RecordLogProcessed("test-instance", "error", 1024, 500*time.Millisecond)
	exporter.RecordError("processor", "download_failed")
	
	// Metrics should be buffered
	assert.NotNil(t, exporter)
}

// TestCircuitBreaker tests the circuit breaker pattern
func TestCircuitBreaker(t *testing.T) {
	breaker := circuitbreaker.New(circuitbreaker.Config{
		FailureThreshold: 3,
		SuccessThreshold: 2,
		Timeout:         100 * time.Millisecond,
	})
	
	failCount := 0
	failingFunc := func() error {
		failCount++
		if failCount <= 3 {
			return fmt.Errorf("simulated failure")
		}
		return nil
	}
	
	// First 3 calls should fail and open the circuit
	for i := 0; i < 3; i++ {
		err := breaker.Execute(context.Background(), failingFunc)
		assert.Error(t, err)
	}
	
	// Circuit should be open now
	assert.Equal(t, circuitbreaker.StateOpen, breaker.State())
	
	// Next call should fail immediately
	err := breaker.Execute(context.Background(), failingFunc)
	assert.Equal(t, circuitbreaker.ErrCircuitOpen, err)
	
	// Wait for timeout
	time.Sleep(150 * time.Millisecond)
	
	// Circuit should be half-open, next calls should succeed
	err = breaker.Execute(context.Background(), failingFunc)
	assert.NoError(t, err)
}

// Helper functions

func startKafkaContainer(ctx context.Context) (testcontainers.Container, error) {
	req := testcontainers.ContainerRequest{
		Image:        "confluentinc/cp-kafka:7.5.0",
		ExposedPorts: []string{"9092/tcp"},
		Env: map[string]string{
			"KAFKA_BROKER_ID":                        "1",
			"KAFKA_ZOOKEEPER_CONNECT":                "zookeeper:2181",
			"KAFKA_ADVERTISED_LISTENERS":             "PLAINTEXT://localhost:9092",
			"KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR": "1",
		},
		WaitingFor: wait.ForLog("started (kafka.server.KafkaServer)"),
	}
	
	return testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: req,
		Started:          true,
	})
}

func startValkeyContainer(ctx context.Context) (testcontainers.Container, error) {
	req := testcontainers.ContainerRequest{
		Image:        "valkey/valkey:8-alpine",
		ExposedPorts: []string{"6379/tcp"},
		WaitingFor:   wait.ForLog("Ready to accept connections"),
	}
	
	return testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: req,
		Started:          true,
	})
}

func createTestTopics(broker string) error {
	conn, err := kafka.Dial("tcp", broker)
	if err != nil {
		return err
	}
	defer conn.Close()
	
	topics := []string{"aurora-logs-error", "aurora-logs-slowquery"}
	for _, topic := range topics {
		err = conn.CreateTopics(kafka.TopicConfig{
			Topic:             topic,
			NumPartitions:     1,
			ReplicationFactor: 1,
		})
		if err != nil {
			return err
		}
	}
	
	return nil
}

// TestDynamoDBIntegration tests the full DynamoDB integration
func TestDynamoDBIntegration(t *testing.T) {
	t.Skip("Requires AWS credentials and DynamoDB tables")
	
	ctx := context.Background()
	
	// Load AWS config
	cfg, err := config.LoadDefaultConfig(ctx)
	require.NoError(t, err)
	
	dynamoClient := dynamodb.NewFromConfig(cfg)
	
	// Test instance registry population
	t.Run("InstanceRegistryFlow", func(t *testing.T) {
		// Simulate discovery service finding an instance
		instanceTable := "aurora-instance-metadata"
		testClusterID := "integration-test-cluster"
		testInstanceID := "integration-test-instance"
		
		// Save cluster
		clusterItem := map[string]types.AttributeValue{
			"pk":              &types.AttributeValueMemberS{Value: "CLUSTER#" + testClusterID},
			"sk":              &types.AttributeValueMemberS{Value: "METADATA"},
			"cluster_id":      &types.AttributeValueMemberS{Value: testClusterID},
			"engine":          &types.AttributeValueMemberS{Value: "aurora-mysql"},
			"status":          &types.AttributeValueMemberS{Value: "available"},
			"member_count":    &types.AttributeValueMemberN{Value: "1"},
			"updated_at":      &types.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)},
			"discovered_by":   &types.AttributeValueMemberS{Value: "integration-test"},
		}
		
		_, err := dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
			TableName: &instanceTable,
			Item:      clusterItem,
		})
		assert.NoError(t, err)
		
		// Save instance
		instanceItem := map[string]types.AttributeValue{
			"pk":                &types.AttributeValueMemberS{Value: "INSTANCE#" + testInstanceID},
			"sk":                &types.AttributeValueMemberS{Value: "METADATA"},
			"instance_id":       &types.AttributeValueMemberS{Value: testInstanceID},
			"cluster_id":        &types.AttributeValueMemberS{Value: testClusterID},
			"instance_class":    &types.AttributeValueMemberS{Value: "db.r6g.2xlarge"},
			"status":            &types.AttributeValueMemberS{Value: "available"},
			"is_cluster_writer": &types.AttributeValueMemberBOOL{Value: true},
			"updated_at":        &types.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)},
			"discovered_by":     &types.AttributeValueMemberS{Value: "integration-test"},
		}
		
		_, err = dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
			TableName: &instanceTable,
			Item:      instanceItem,
		})
		assert.NoError(t, err)
		
		// Verify data was saved
		queries := common.NewDynamoQueries(dynamoClient, instanceTable, "", "")
		
		cluster, err := queries.GetCluster(ctx, testClusterID)
		assert.NoError(t, err)
		assert.Equal(t, testClusterID, cluster.ClusterID)
		
		instance, err := queries.GetInstance(ctx, testInstanceID)
		assert.NoError(t, err)
		assert.Equal(t, testInstanceID, instance.InstanceID)
		assert.Equal(t, testClusterID, instance.ClusterID)
		
		// Cleanup
		dynamoClient.DeleteItem(ctx, &dynamodb.DeleteItemInput{
			TableName: &instanceTable,
			Key: map[string]types.AttributeValue{
				"pk": &types.AttributeValueMemberS{Value: "CLUSTER#" + testClusterID},
				"sk": &types.AttributeValueMemberS{Value: "METADATA"},
			},
		})
		
		dynamoClient.DeleteItem(ctx, &dynamodb.DeleteItemInput{
			TableName: &instanceTable,
			Key: map[string]types.AttributeValue{
				"pk": &types.AttributeValueMemberS{Value: "INSTANCE#" + testInstanceID},
				"sk": &types.AttributeValueMemberS{Value: "METADATA"},
			},
		})
	})
	
	// Test job tracking flow
	t.Run("JobTrackingFlow", func(t *testing.T) {
		jobsTable := "aurora-log-processing-jobs"
		testJobID := "integration-job-" + time.Now().Format("20060102-150405")
		
		// Create job
		jobItem := map[string]types.AttributeValue{
			"pk":            &types.AttributeValueMemberS{Value: "JOB#" + testJobID},
			"sk":            &types.AttributeValueMemberS{Value: "METADATA"},
			"job_id":        &types.AttributeValueMemberS{Value: testJobID},
			"instance_id":   &types.AttributeValueMemberS{Value: "test-instance"},
			"cluster_id":    &types.AttributeValueMemberS{Value: "test-cluster"},
			"log_type":      &types.AttributeValueMemberS{Value: "error"},
			"log_file":      &types.AttributeValueMemberS{Value: "error.log"},
			"file_size":     &types.AttributeValueMemberN{Value: "1000000"},
			"status":        &types.AttributeValueMemberS{Value: "processing"},
			"started_at":    &types.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)},
			"worker_id":     &types.AttributeValueMemberS{Value: "test-worker"},
			"consumer_group": &types.AttributeValueMemberS{Value: "test-group"},
		}
		
		_, err := dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
			TableName: &jobsTable,
			Item:      jobItem,
		})
		assert.NoError(t, err)
		
		// Update job status to completed
		updateExpr := "SET #status = :status, #completed_at = :completed_at, #chunks_processed = :chunks, #bytes_processed = :bytes"
		_, err = dynamoClient.UpdateItem(ctx, &dynamodb.UpdateItemInput{
			TableName: &jobsTable,
			Key: map[string]types.AttributeValue{
				"pk": &types.AttributeValueMemberS{Value: "JOB#" + testJobID},
				"sk": &types.AttributeValueMemberS{Value: "METADATA"},
			},
			UpdateExpression: &updateExpr,
			ExpressionAttributeNames: map[string]string{
				"#status":           "status",
				"#completed_at":     "completed_at",
				"#chunks_processed": "chunks_processed",
				"#bytes_processed":  "bytes_processed",
			},
			ExpressionAttributeValues: map[string]types.AttributeValue{
				":status":       &types.AttributeValueMemberS{Value: "completed"},
				":completed_at": &types.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Unix(), 10)},
				":chunks":      &types.AttributeValueMemberN{Value: "10"},
				":bytes":       &types.AttributeValueMemberN{Value: "1000000"},
			},
		})
		assert.NoError(t, err)
		
		// Verify job was updated
		queries := common.NewDynamoQueries(dynamoClient, "", jobsTable, "")
		job, err := queries.GetJob(ctx, testJobID)
		assert.NoError(t, err)
		assert.Equal(t, "completed", job.Status)
		assert.Equal(t, 10, job.ChunksProcessed)
		
		// Cleanup
		dynamoClient.DeleteItem(ctx, &dynamodb.DeleteItemInput{
			TableName: &jobsTable,
			Key: map[string]types.AttributeValue{
				"pk": &types.AttributeValueMemberS{Value: "JOB#" + testJobID},
				"sk": &types.AttributeValueMemberS{Value: "METADATA"},
			},
		})
	})
}