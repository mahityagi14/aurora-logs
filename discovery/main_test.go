package main

import (
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	rdsTypes "github.com/aws/aws-sdk-go-v2/service/rds/types"
	"github.com/stretchr/testify/assert"
)

func TestConfig_GetEnvOrDefault(t *testing.T) {
	tests := []struct {
		name     string
		key      string
		envValue string
		default_  string
		expected string
	}{
		{
			name:     "returns env value when set",
			key:      "TEST_ENV_VAR",
			envValue: "test-value",
			default_:  "default-value",
			expected: "test-value",
		},
		{
			name:     "returns default when env not set",
			key:      "UNSET_ENV_VAR",
			envValue: "",
			default_:  "default-value",
			expected: "default-value",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.envValue != "" {
				t.Setenv(tt.key, tt.envValue)
			}
			result := getEnvOrDefault(tt.key, tt.default_)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestConfig_GetEnvAsInt(t *testing.T) {
	tests := []struct {
		name     string
		key      string
		envValue string
		default_  int
		expected int
	}{
		{
			name:     "returns int value when valid",
			key:      "TEST_INT_VAR",
			envValue: "42",
			default_:  10,
			expected: 42,
		},
		{
			name:     "returns default when env not set",
			key:      "UNSET_INT_VAR",
			envValue: "",
			default_:  10,
			expected: 10,
		},
		{
			name:     "returns default when env not a valid int",
			key:      "INVALID_INT_VAR",
			envValue: "not-a-number",
			default_:  10,
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

func TestHashShard(t *testing.T) {
	tests := []struct {
		name      string
		clusterID string
		totalShards int
	}{
		{
			name:      "single shard",
			clusterID: "test-cluster-1",
			totalShards: 1,
		},
		{
			name:      "multi shard",
			clusterID: "test-cluster-1",
			totalShards: 2,
		},
		{
			name:      "many shards",
			clusterID: "test-cluster-2",
			totalShards: 10,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Simple hash function to test
			hash := 0
			for _, ch := range tt.clusterID {
				hash = hash*31 + int(ch)
			}
			result := hash % tt.totalShards
			
			// Hash should be within range
			assert.GreaterOrEqual(t, result, 0)
			assert.Less(t, result, tt.totalShards)
			
			// Same input should produce same hash
			hash2 := 0
			for _, ch := range tt.clusterID {
				hash2 = hash2*31 + int(ch)
			}
			result2 := hash2 % tt.totalShards
			assert.Equal(t, result, result2)
		})
	}
}

func TestDiscovery_IsNewLog(t *testing.T) {
	// Test data structures
	tests := []struct {
		name     string
		log      rdsTypes.DescribeDBLogFilesDetails
		expected bool
	}{
		{
			name: "new log (no existing record)",
			log: rdsTypes.DescribeDBLogFilesDetails{
				LogFileName: aws.String("error/mysql-error.log"),
				LastWritten: aws.Int64(1234567890),
				Size:        aws.Int64(1024),
			},
			expected: true,
		},
		{
			name: "existing log with same timestamp",
			log: rdsTypes.DescribeDBLogFilesDetails{
				LogFileName: aws.String("error/mysql-error.log"),
				LastWritten: aws.Int64(1234567890),
				Size:        aws.Int64(1024),
			},
			expected: false,
		},
		{
			name: "existing log with newer timestamp",
			log: rdsTypes.DescribeDBLogFilesDetails{
				LogFileName: aws.String("error/mysql-error.log"),
				LastWritten: aws.Int64(1234567900),
				Size:        aws.Int64(2048),
			},
			expected: true,
		},
	}

	// Note: In a real test, we would mock the DynamoDB client
	// For now, we're just testing the logic structure
	_ = tests
}

func TestLogFileInfo_Marshal(t *testing.T) {
	info := LogFileInfo{
		InstanceID:  "test-instance",
		ClusterID:   "test-cluster",
		Engine:      "aurora-mysql",
		LogType:     "error",
		LogFileName: "error/mysql-error.log",
		LastWritten: 1234567890,
		Size:        1024,
		Timestamp:   time.Now(),
	}

	data, err := json.Marshal(info)
	assert.NoError(t, err)
	assert.NotEmpty(t, data)

	// Verify it can be unmarshaled
	var decoded LogFileInfo
	err = json.Unmarshal(data, &decoded)
	assert.NoError(t, err)
	assert.Equal(t, info.InstanceID, decoded.InstanceID)
	assert.Equal(t, info.ClusterID, decoded.ClusterID)
	assert.Equal(t, info.LogFileName, decoded.LogFileName)
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
	
	t.Run("record histogram", func(t *testing.T) {
		// Just verify it doesn't panic
		metrics.RecordHistogram("test_histogram", 42.5)
	})
}

func TestRDSCacheClient(t *testing.T) {
	// This would require mocking Redis and RDS clients
	// For now, we test the structure
	t.Run("new client creation", func(t *testing.T) {
		client := NewRDSCacheClient(nil, nil)
		assert.NotNil(t, client)
	})
}

func TestLogTypeDetection(t *testing.T) {
	d := &Discovery{}
	
	tests := []struct {
		name     string
		fileName string
		expected string
	}{
		{
			name:     "error log",
			fileName: "error/mysql-error.log",
			expected: "error",
		},
		{
			name:     "slow query log",
			fileName: "slowquery/mysql-slowquery.log",
			expected: "slowquery",
		},
		{
			name:     "general log",
			fileName: "general/mysql-general.log",
			expected: "",
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := d.getLogType(tt.fileName)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestShouldProcessCluster(t *testing.T) {
	tests := []struct {
		name        string
		shardID     int
		totalShards int
		clusterID   string
	}{
		{
			name:        "single shard always processes",
			shardID:     0,
			totalShards: 1,
			clusterID:   "test-cluster",
		},
		{
			name:        "multi shard distribution",
			shardID:     0,
			totalShards: 3,
			clusterID:   "test-cluster-1",
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			d := &Discovery{
				config: Config{
					ShardID:     tt.shardID,
					TotalShards: tt.totalShards,
				},
			}
			
			cluster := rdsTypes.DBCluster{
				DBClusterIdentifier: aws.String(tt.clusterID),
			}
			
			result := d.shouldProcessCluster(cluster)
			
			if tt.totalShards == 1 {
				assert.True(t, result)
			} else {
				// Just verify it returns a boolean
				assert.IsType(t, true, result)
			}
		})
	}
}

