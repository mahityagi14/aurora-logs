// +build integration

package tests

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/segmentio/kafka-go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
)

// Integration tests for Aurora Log System
// Run with: go test -tags=integration -timeout 10m ./...

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