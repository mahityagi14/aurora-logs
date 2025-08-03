package main

import (
	"context"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	dynamoTypes "github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/rds"
	rdsTypes "github.com/aws/aws-sdk-go-v2/service/rds/types"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

// Mock clients
type mockRDSClient struct {
	mock.Mock
}

func (m *mockRDSClient) DescribeDBClusters(ctx context.Context, params *rds.DescribeDBClustersInput, optFns ...func(*rds.Options)) (*rds.DescribeDBClustersOutput, error) {
	args := m.Called(ctx, params)
	return args.Get(0).(*rds.DescribeDBClustersOutput), args.Error(1)
}

func (m *mockRDSClient) DescribeDBInstances(ctx context.Context, params *rds.DescribeDBInstancesInput, optFns ...func(*rds.Options)) (*rds.DescribeDBInstancesOutput, error) {
	args := m.Called(ctx, params)
	return args.Get(0).(*rds.DescribeDBInstancesOutput), args.Error(1)
}

func (m *mockRDSClient) DescribeDBLogFiles(ctx context.Context, params *rds.DescribeDBLogFilesInput, optFns ...func(*rds.Options)) (*rds.DescribeDBLogFilesOutput, error) {
	args := m.Called(ctx, params)
	return args.Get(0).(*rds.DescribeDBLogFilesOutput), args.Error(1)
}

type mockDynamoClient struct {
	mock.Mock
}

func (m *mockDynamoClient) GetItem(ctx context.Context, params *dynamodb.GetItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error) {
	args := m.Called(ctx, params)
	return args.Get(0).(*dynamodb.GetItemOutput), args.Error(1)
}

func (m *mockDynamoClient) PutItem(ctx context.Context, params *dynamodb.PutItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error) {
	args := m.Called(ctx, params)
	return args.Get(0).(*dynamodb.PutItemOutput), args.Error(1)
}

func (m *mockDynamoClient) UpdateItem(ctx context.Context, params *dynamodb.UpdateItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
	args := m.Called(ctx, params)
	return args.Get(0).(*dynamodb.UpdateItemOutput), args.Error(1)
}

func (m *mockDynamoClient) Query(ctx context.Context, params *dynamodb.QueryInput, optFns ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
	args := m.Called(ctx, params)
	return args.Get(0).(*dynamodb.QueryOutput), args.Error(1)
}

// Test helper functions
func TestGetEnvOrDefault(t *testing.T) {
	tests := []struct {
		name     string
		key      string
		defVal   string
		envVal   string
		expected string
	}{
		{"returns default when env not set", "TEST_KEY", "default", "", "default"},
		{"returns env value when set", "TEST_KEY", "default", "value", "value"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.envVal != "" {
				t.Setenv(tt.key, tt.envVal)
			}
			result := getEnvOrDefault(tt.key, tt.defVal)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestGetEnvAsInt(t *testing.T) {
	tests := []struct {
		name     string
		key      string
		defVal   int
		envVal   string
		expected int
	}{
		{"returns default when env not set", "TEST_KEY", 10, "", 10},
		{"returns env value as int", "TEST_KEY", 10, "20", 20},
		{"returns default on invalid int", "TEST_KEY", 10, "invalid", 10},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.envVal != "" {
				t.Setenv(tt.key, tt.envVal)
			}
			result := getEnvAsInt(tt.key, tt.defVal)
			assert.Equal(t, tt.expected, result)
		})
	}
}

// Test Circuit Breaker
func TestCircuitBreaker(t *testing.T) {
	cb := NewCircuitBreaker(2, 100*time.Millisecond)

	// Test successful calls
	err := cb.Call(func() error { return nil })
	assert.NoError(t, err)

	// Test failure tracking
	failCount := 0
	for i := 0; i < 3; i++ {
		err = cb.Call(func() error {
			failCount++
			return assert.AnError
		})
		if i < 2 {
			assert.Error(t, err)
		}
	}

	// Circuit should be open now
	err = cb.Call(func() error { return nil })
	assert.EqualError(t, err, "circuit breaker is open")

	// Wait for reset timeout
	time.Sleep(150 * time.Millisecond)

	// Circuit should be half-open, next call should succeed
	err = cb.Call(func() error { return nil })
	assert.NoError(t, err)
}

// Test RDS Cache Client
func TestRDSCacheClient(t *testing.T) {
	mockRDS := new(mockRDSClient)
	mockRedis := redis.NewClient(&redis.Options{})
	
	client := NewRDSCacheClient(mockRDS, mockRedis)

	t.Run("DescribeDBClusters cache miss", func(t *testing.T) {
		ctx := context.Background()
		expectedClusters := []rdsTypes.DBCluster{
			{
				DBClusterIdentifier: aws.String("test-cluster"),
				Engine:             aws.String("aurora-mysql"),
			},
		}

		mockRDS.On("DescribeDBClusters", ctx, mock.Anything).Return(&rds.DescribeDBClustersOutput{
			DBClusters: expectedClusters,
		}, nil).Once()

		clusters, err := client.DescribeDBClusters(ctx)
		assert.NoError(t, err)
		assert.Len(t, clusters, 1)
		assert.Equal(t, "test-cluster", *clusters[0].DBClusterIdentifier)

		mockRDS.AssertExpectations(t)
	})
}

// Test Discovery shouldProcessCluster
func TestShouldProcessCluster(t *testing.T) {
	d := &Discovery{
		config: Config{
			ShardID:     0,
			TotalShards: 2,
		},
	}

	tests := []struct {
		name       string
		cluster    rdsTypes.DBCluster
		shouldProc bool
	}{
		{
			name: "aurora cluster in shard",
			cluster: rdsTypes.DBCluster{
				DBClusterIdentifier: aws.String("aurora-cluster-1"),
				Engine:             aws.String("aurora-mysql"),
			},
			shouldProc: true,
		},
		{
			name: "non-aurora cluster",
			cluster: rdsTypes.DBCluster{
				DBClusterIdentifier: aws.String("rds-cluster"),
				Engine:             aws.String("postgres"),
			},
			shouldProc: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := d.shouldProcessCluster(tt.cluster)
			assert.Equal(t, tt.shouldProc, result)
		})
	}
}

// Test getLogType
func TestGetLogType(t *testing.T) {
	d := &Discovery{}

	tests := []struct {
		fileName string
		expected string
	}{
		{"error/mysql-error.log", "error"},
		{"slowquery/mysql-slowquery.log", "slowquery"},
		{"general/mysql-general.log", ""},
		{"mysql-slow-query.log", "slowquery"},
	}

	for _, tt := range tests {
		t.Run(tt.fileName, func(t *testing.T) {
			result := d.getLogType(tt.fileName)
			assert.Equal(t, tt.expected, result)
		})
	}
}

// Test shouldProcessLog
func TestShouldProcessLog(t *testing.T) {
	mockDynamo := new(mockDynamoClient)
	d := &Discovery{
		config: Config{
			TrackingTable: "test-tracking",
		},
		dynamoClient: mockDynamo,
	}

	ctx := context.Background()
	logInfo := LogFileInfo{
		InstanceID:  "test-instance",
		LogFileName: "error.log",
		LastWritten: time.Now().Unix(),
	}

	t.Run("new file should be processed", func(t *testing.T) {
		mockDynamo.On("GetItem", ctx, mock.MatchedBy(func(input *dynamodb.GetItemInput) bool {
			return *input.TableName == "test-tracking"
		})).Return(&dynamodb.GetItemOutput{Item: nil}, nil).Once()

		mockDynamo.On("PutItem", ctx, mock.Anything).Return(&dynamodb.PutItemOutput{}, nil).Once()

		result := d.shouldProcessLog(ctx, logInfo)
		assert.True(t, result)
		mockDynamo.AssertExpectations(t)
	})

	t.Run("completed file should not be processed", func(t *testing.T) {
		mockDynamo.On("GetItem", ctx, mock.MatchedBy(func(input *dynamodb.GetItemInput) bool {
			return *input.TableName == "test-tracking"
		})).Return(&dynamodb.GetItemOutput{
			Item: map[string]dynamoTypes.AttributeValue{
				"status":       &dynamoTypes.AttributeValueMemberS{Value: "completed"},
				"last_written": &dynamoTypes.AttributeValueMemberN{Value: "1000"},
			},
		}, nil).Once()

		result := d.shouldProcessLog(ctx, logInfo)
		assert.False(t, result)
		mockDynamo.AssertExpectations(t)
	})
}

// Test Metrics Exporter
func TestMetricsExporter(t *testing.T) {
	exporter := NewMetricsExporter("http://localhost:5080", "user", "pass")

	// Test counter increment
	exporter.IncrementCounter("test_counter", 5)
	exporter.mu.RLock()
	value := exporter.counters["test_counter"]
	exporter.mu.RUnlock()
	assert.Equal(t, int64(5), value)

	// Test multiple increments
	exporter.IncrementCounter("test_counter", 3)
	exporter.mu.RLock()
	value = exporter.counters["test_counter"]
	exporter.mu.RUnlock()
	assert.Equal(t, int64(8), value)
}

// Benchmark tests
func BenchmarkCircuitBreaker(b *testing.B) {
	cb := NewCircuitBreaker(100, 1*time.Second)
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		cb.Call(func() error { return nil })
	}
}

func BenchmarkGetLogType(b *testing.B) {
	d := &Discovery{}
	fileName := "error/mysql-error-2024-01-01.log"
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		d.getLogType(fileName)
	}
}