package tests

import (
	"context"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/aurora-log-system/common"
)

func TestDynamoDBTables(t *testing.T) {
	ctx := context.Background()
	
	// Load AWS config
	cfg, err := config.LoadDefaultConfig(ctx)
	require.NoError(t, err)
	
	dynamoClient := dynamodb.NewFromConfig(cfg)
	
	// Test table names
	instanceTable := "aurora-instance-metadata"
	jobsTable := "aurora-log-processing-jobs"
	trackingTable := "aurora-log-file-tracking"
	
	// Create DynamoDB queries helper
	queries := common.NewDynamoQueries(dynamoClient, instanceTable, jobsTable, trackingTable)
	
	t.Run("TestInstanceRegistryOperations", func(t *testing.T) {
		// Test data
		testClusterID := "test-cluster-001"
		testInstanceID := "test-instance-001"
		
		// Create cluster entry
		clusterItem := map[string]types.AttributeValue{
			"pk":              &types.AttributeValueMemberS{Value: "CLUSTER#" + testClusterID},
			"sk":              &types.AttributeValueMemberS{Value: "METADATA"},
			"cluster_id":      &types.AttributeValueMemberS{Value: testClusterID},
			"engine":          &types.AttributeValueMemberS{Value: "aurora-mysql"},
			"engine_version":  &types.AttributeValueMemberS{Value: "8.0.mysql_aurora.3.04.0"},
			"status":          &types.AttributeValueMemberS{Value: "available"},
			"endpoint":        &types.AttributeValueMemberS{Value: testClusterID + ".cluster-abc123.us-east-1.rds.amazonaws.com"},
			"reader_endpoint": &types.AttributeValueMemberS{Value: testClusterID + ".cluster-ro-abc123.us-east-1.rds.amazonaws.com"},
			"multi_az":        &types.AttributeValueMemberBOOL{Value: true},
			"member_count":    &types.AttributeValueMemberN{Value: "2"},
			"updated_at":      &types.AttributeValueMemberN{Value: "1234567890"},
		}
		
		_, err := dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
			TableName: &instanceTable,
			Item:      clusterItem,
		})
		assert.NoError(t, err)
		
		// Create instance entry
		instanceItem := map[string]types.AttributeValue{
			"pk":                  &types.AttributeValueMemberS{Value: "INSTANCE#" + testInstanceID},
			"sk":                  &types.AttributeValueMemberS{Value: "METADATA"},
			"instance_id":         &types.AttributeValueMemberS{Value: testInstanceID},
			"cluster_id":          &types.AttributeValueMemberS{Value: testClusterID},
			"instance_class":      &types.AttributeValueMemberS{Value: "db.r6g.2xlarge"},
			"engine":              &types.AttributeValueMemberS{Value: "aurora-mysql"},
			"engine_version":      &types.AttributeValueMemberS{Value: "8.0.mysql_aurora.3.04.0"},
			"status":              &types.AttributeValueMemberS{Value: "available"},
			"availability_zone":   &types.AttributeValueMemberS{Value: "us-east-1a"},
			"is_cluster_writer":   &types.AttributeValueMemberBOOL{Value: true},
			"promotion_tier":      &types.AttributeValueMemberN{Value: "1"},
			"publicly_accessible": &types.AttributeValueMemberBOOL{Value: false},
			"storage_encrypted":   &types.AttributeValueMemberBOOL{Value: true},
			"monitoring_interval": &types.AttributeValueMemberN{Value: "60"},
			"updated_at":          &types.AttributeValueMemberN{Value: "1234567890"},
		}
		
		_, err = dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
			TableName: &instanceTable,
			Item:      instanceItem,
		})
		assert.NoError(t, err)
		
		// Test GetCluster
		cluster, err := queries.GetCluster(ctx, testClusterID)
		assert.NoError(t, err)
		assert.NotNil(t, cluster)
		assert.Equal(t, testClusterID, cluster.ClusterID)
		assert.Equal(t, "aurora-mysql", cluster.Engine)
		assert.Equal(t, "available", cluster.Status)
		assert.True(t, cluster.MultiAZ)
		assert.Equal(t, 2, cluster.MemberCount)
		
		// Test GetInstance
		instance, err := queries.GetInstance(ctx, testInstanceID)
		assert.NoError(t, err)
		assert.NotNil(t, instance)
		assert.Equal(t, testInstanceID, instance.InstanceID)
		assert.Equal(t, testClusterID, instance.ClusterID)
		assert.Equal(t, "db.r6g.2xlarge", instance.InstanceClass)
		assert.True(t, instance.IsClusterWriter)
		
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
	
	t.Run("TestJobsTableOperations", func(t *testing.T) {
		// Test data
		testJobID := "test-job-" + time.Now().Format("20060102-150405")
		testInstanceID := "test-instance-001"
		
		// Create job entry
		jobItem := map[string]types.AttributeValue{
			"pk":              &types.AttributeValueMemberS{Value: "JOB#" + testJobID},
			"sk":              &types.AttributeValueMemberS{Value: "METADATA"},
			"job_id":          &types.AttributeValueMemberS{Value: testJobID},
			"instance_id":     &types.AttributeValueMemberS{Value: testInstanceID},
			"cluster_id":      &types.AttributeValueMemberS{Value: "test-cluster-001"},
			"log_type":        &types.AttributeValueMemberS{Value: "error"},
			"log_file":        &types.AttributeValueMemberS{Value: "error/mysql-error.log"},
			"file_size":       &types.AttributeValueMemberN{Value: "1024000"},
			"status":          &types.AttributeValueMemberS{Value: "completed"},
			"started_at":      &types.AttributeValueMemberN{Value: "1234567890"},
			"completed_at":    &types.AttributeValueMemberN{Value: "1234567900"},
			"chunks_processed": &types.AttributeValueMemberN{Value: "5"},
			"bytes_processed": &types.AttributeValueMemberN{Value: "1024000"},
			"worker_id":       &types.AttributeValueMemberS{Value: "processor-pod-abc123"},
		}
		
		_, err := dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
			TableName: &jobsTable,
			Item:      jobItem,
		})
		assert.NoError(t, err)
		
		// Create time index entry
		timeIndexItem := map[string]types.AttributeValue{
			"pk":          &types.AttributeValueMemberS{Value: "DATE#" + time.Now().Format("2006-01-02")},
			"sk":          &types.AttributeValueMemberS{Value: "TIME#" + time.Now().Format("15:04:05") + "#" + testJobID},
			"job_id":      &types.AttributeValueMemberS{Value: testJobID},
			"instance_id": &types.AttributeValueMemberS{Value: testInstanceID},
			"log_type":    &types.AttributeValueMemberS{Value: "error"},
			"status":      &types.AttributeValueMemberS{Value: "completed"},
		}
		
		_, err = dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
			TableName: &jobsTable,
			Item:      timeIndexItem,
		})
		assert.NoError(t, err)
		
		// Test GetJob
		job, err := queries.GetJob(ctx, testJobID)
		assert.NoError(t, err)
		assert.NotNil(t, job)
		assert.Equal(t, testJobID, job.JobID)
		assert.Equal(t, testInstanceID, job.InstanceID)
		assert.Equal(t, "completed", job.Status)
		assert.Equal(t, 5, job.ChunksProcessed)
		assert.Equal(t, int64(1024000), job.BytesProcessed)
		
		// Test GetRecentJobs
		jobs, err := queries.GetRecentJobs(ctx, 1)
		assert.NoError(t, err)
		assert.GreaterOrEqual(t, len(jobs), 1)
		
		// Test GetJobStats
		stats, err := queries.GetJobStats(ctx, 1)
		assert.NoError(t, err)
		assert.NotNil(t, stats)
		assert.GreaterOrEqual(t, stats["total_jobs"].(int), 1)
		assert.GreaterOrEqual(t, stats["completed_jobs"].(int), 1)
		
		// Cleanup
		dynamoClient.DeleteItem(ctx, &dynamodb.DeleteItemInput{
			TableName: &jobsTable,
			Key: map[string]types.AttributeValue{
				"pk": &types.AttributeValueMemberS{Value: "JOB#" + testJobID},
				"sk": &types.AttributeValueMemberS{Value: "METADATA"},
			},
		})
		
		dynamoClient.DeleteItem(ctx, &dynamodb.DeleteItemInput{
			TableName: &jobsTable,
			Key: map[string]types.AttributeValue{
				"pk": timeIndexItem["pk"],
				"sk": timeIndexItem["sk"],
			},
		})
	})
	
	t.Run("TestTrackingTableOperations", func(t *testing.T) {
		// Test data
		testInstanceID := "test-instance-001"
		testLogFile := "error/mysql-error-20250127.log"
		
		// Create tracking entry
		trackingItem := map[string]types.AttributeValue{
			"instance_id":    &types.AttributeValueMemberS{Value: testInstanceID},
			"log_file_name":  &types.AttributeValueMemberS{Value: testLogFile},
			"last_marker":    &types.AttributeValueMemberS{Value: "1000"},
			"last_written":   &types.AttributeValueMemberN{Value: "1234567890"},
			"processed_size": &types.AttributeValueMemberN{Value: "512000"},
			"updated_at":     &types.AttributeValueMemberN{Value: "1234567890"},
		}
		
		_, err := dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
			TableName: &trackingTable,
			Item:      trackingItem,
		})
		assert.NoError(t, err)
		
		// Test GetItem
		result, err := dynamoClient.GetItem(ctx, &dynamodb.GetItemInput{
			TableName: &trackingTable,
			Key: map[string]types.AttributeValue{
				"instance_id":   &types.AttributeValueMemberS{Value: testInstanceID},
				"log_file_name": &types.AttributeValueMemberS{Value: testLogFile},
			},
		})
		assert.NoError(t, err)
		assert.NotNil(t, result.Item)
		
		// Verify data
		marker, ok := result.Item["last_marker"].(*types.AttributeValueMemberS)
		assert.True(t, ok)
		assert.Equal(t, "1000", marker.Value)
		
		size, ok := result.Item["processed_size"].(*types.AttributeValueMemberN)
		assert.True(t, ok)
		assert.Equal(t, "512000", size.Value)
		
		// Cleanup
		dynamoClient.DeleteItem(ctx, &dynamodb.DeleteItemInput{
			TableName: &trackingTable,
			Key: map[string]types.AttributeValue{
				"instance_id":   &types.AttributeValueMemberS{Value: testInstanceID},
				"log_file_name": &types.AttributeValueMemberS{Value: testLogFile},
			},
		})
	})
}

func TestDynamoDBDataIntegrity(t *testing.T) {
	ctx := context.Background()
	
	// Load AWS config
	cfg, err := config.LoadDefaultConfig(ctx)
	require.NoError(t, err)
	
	dynamoClient := dynamodb.NewFromConfig(cfg)
	
	t.Run("TestConcurrentWrites", func(t *testing.T) {
		// Test concurrent updates to tracking table
		trackingTable := "aurora-log-file-tracking"
		testInstanceID := "test-concurrent-001"
		testLogFile := "error/mysql-error-concurrent.log"
		
		// Create initial entry
		item := map[string]types.AttributeValue{
			"instance_id":    &types.AttributeValueMemberS{Value: testInstanceID},
			"log_file_name":  &types.AttributeValueMemberS{Value: testLogFile},
			"last_marker":    &types.AttributeValueMemberS{Value: "0"},
			"last_written":   &types.AttributeValueMemberN{Value: "1234567890"},
			"processed_size": &types.AttributeValueMemberN{Value: "0"},
			"updated_at":     &types.AttributeValueMemberN{Value: "1234567890"},
		}
		
		_, err := dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
			TableName: &trackingTable,
			Item:      item,
		})
		assert.NoError(t, err)
		
		// Simulate concurrent updates
		done := make(chan bool, 3)
		
		for i := 0; i < 3; i++ {
			go func(id int) {
				defer func() { done <- true }()
				
				// Update with different markers
				updateItem := map[string]types.AttributeValue{
					"instance_id":    &types.AttributeValueMemberS{Value: testInstanceID},
					"log_file_name":  &types.AttributeValueMemberS{Value: testLogFile},
					"last_marker":    &types.AttributeValueMemberS{Value: string(rune('A' + id))},
					"last_written":   &types.AttributeValueMemberN{Value: "1234567890"},
					"processed_size": &types.AttributeValueMemberN{Value: string(rune('1' + id)) + "00000"},
					"updated_at":     &types.AttributeValueMemberN{Value: string(rune('1' + id)) + "234567890"},
				}
				
				dynamoClient.PutItem(ctx, &dynamodb.PutItemInput{
					TableName: &trackingTable,
					Item:      updateItem,
				})
			}(i)
		}
		
		// Wait for all updates
		for i := 0; i < 3; i++ {
			<-done
		}
		
		// Verify final state
		result, err := dynamoClient.GetItem(ctx, &dynamodb.GetItemInput{
			TableName: &trackingTable,
			Key: map[string]types.AttributeValue{
				"instance_id":   &types.AttributeValueMemberS{Value: testInstanceID},
				"log_file_name": &types.AttributeValueMemberS{Value: testLogFile},
			},
		})
		assert.NoError(t, err)
		assert.NotNil(t, result.Item)
		
		// One of the updates should have won
		marker, ok := result.Item["last_marker"].(*types.AttributeValueMemberS)
		assert.True(t, ok)
		assert.Contains(t, []string{"A", "B", "C"}, marker.Value)
		
		// Cleanup
		dynamoClient.DeleteItem(ctx, &dynamodb.DeleteItemInput{
			TableName: &trackingTable,
			Key: map[string]types.AttributeValue{
				"instance_id":   &types.AttributeValueMemberS{Value: testInstanceID},
				"log_file_name": &types.AttributeValueMemberS{Value: testLogFile},
			},
		})
	})
}