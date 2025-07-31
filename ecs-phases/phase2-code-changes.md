# Phase 2: Code Changes - Valkey 8.1 Upgrade

## Overview
This document highlights the specific changes made in Phase 2 for the Valkey 8.1 upgrade.

## Changed Sections

### Section 3.2: Create Valkey Cluster

**Before (Old Version):**
```markdown
### 3.2 Create Valkey Cluster

1. Navigate to **Redis OSS caches** → **Create Redis OSS cache**
2. **Deployment option**: **Design your own cache**
3. **Creation method**: **Easy create**
4. **Configuration**:
   - Configuration name: **aurora-log-cache-poc**
   - Node type: **cache.t4g.micro** (0.5 GiB)
   - Number of replicas: **1**
   - Multi-AZ: **Enable**
```

**After (Updated to Valkey 8.1):**
```markdown
### 3.2 Create Valkey 8.1 Cluster - UPDATED

**Important Update**: We're now using Valkey 8.1 which provides:
- Native Bloom filter support (98% less memory for lookups)
- 10% throughput improvement with pipelining
- 20% memory reduction for key/value patterns
- COMMANDLOG feature for better observability

1. Navigate to **Redis OSS caches** → **Create Redis OSS cache**
2. **Deployment option**: **Design your own cache**
3. **Creation method**: **Easy create**
4. **Configuration**:
   - Configuration name: **aurora-log-cache-poc**
   - **Engine version**: **8.1** (Valkey 8.1 - Latest)
   - Node type: **cache.t4g.micro** (0.5 GiB)
   - Number of replicas: **1**
   - Multi-AZ: **Enable**
```

### Additional Configuration for Valkey 8.1

**Added in Logs Section:**
```markdown
8. **Logs**:
   - Slow log: **Enable**
   - Slow log destination: **CloudWatch Logs**
   - Log format: **JSON**
   - **NEW - Command log**: **Enable** (Valkey 8.1 feature)
   - Command log destination: **CloudWatch Logs**
```

**Added Advanced Settings:**
```markdown
10. **Advanced Valkey 8.1 settings** (if available):
    - Enable Bloom filter module: **Yes**
    - Hash table optimization: **Enable**
```

### Section 7: Verify Infrastructure

**Added Valkey 8.1 Verification:**
```bash
# Verify Valkey 8.1 version
redis-cli -h aurora-log-cache-poc.[cache-id].ng.0001.[region].cache.amazonaws.com INFO server | grep version

# Test Bloom filter support (Valkey 8.1 feature)
redis-cli -h aurora-log-cache-poc.[cache-id].ng.0001.[region].cache.amazonaws.com
> BF.ADD mybloom item1
> BF.EXISTS mybloom item1
```

### Summary Section Update

**Before:**
```markdown
### Valkey Cache:
- 1 Redis-compatible cache cluster with 1 replica
- Multi-AZ enabled
```

**After:**
```markdown
### Valkey Cache (UPDATED):
- 1 Redis-compatible cache cluster running **Valkey 8.1**
- Multi-AZ enabled
- New features: Bloom filters, improved performance, COMMANDLOG
```

## Impact on Application Code

### Discovery Service (main.go)

No code changes required. The Redis client is compatible with Valkey 8.1. However, you can optionally leverage new features:

**Optional: Using Bloom Filters for Duplicate Detection**
```go
// Add to RDSCacheClient methods
func (c *RDSCacheClient) CheckDuplicate(ctx context.Context, key string) (bool, error) {
    // Use Valkey 8.1 Bloom filter for efficient duplicate checking
    exists, err := c.redisClient.Do(ctx, "BF.EXISTS", "processed_logs", key).Bool()
    if err != nil {
        return false, err
    }
    return exists, nil
}

func (c *RDSCacheClient) MarkProcessed(ctx context.Context, key string) error {
    // Add to Bloom filter
    return c.redisClient.Do(ctx, "BF.ADD", "processed_logs", key).Err()
}
```

### Processor Service

No changes required. The processor service doesn't directly interact with Valkey.

## Configuration Updates

### Environment Variables

No changes to environment variables. The Valkey URL remains the same:
```bash
VALKEY_URL="redis://aurora-log-cache-poc.[cache-id].ng.0001.[region].cache.amazonaws.com:6379"
```

## Benefits of Valkey 8.1 Upgrade

1. **Performance Improvements**:
   - 10% throughput increase for pipelined operations
   - 20% memory reduction for hash tables

2. **New Features**:
   - Bloom filters for memory-efficient set membership testing
   - COMMANDLOG for debugging and monitoring command execution
   - Improved hash table implementation

3. **Operational Benefits**:
   - Better observability with command logging
   - More efficient memory usage
   - Backward compatible with existing Redis clients

## Testing the Upgrade

After deploying Valkey 8.1, run these tests:

```bash
# Performance test with redis-benchmark
redis-benchmark -h aurora-log-cache-poc.[cache-id].ng.0001.[region].cache.amazonaws.com \
  -t get,set -n 100000 -P 16

# Test Bloom filter operations
redis-cli -h aurora-log-cache-poc.[cache-id].ng.0001.[region].cache.amazonaws.com
> BF.RESERVE test_bloom 0.01 100000
> BF.ADD test_bloom "item1"
> BF.EXISTS test_bloom "item1"
> BF.MEXISTS test_bloom "item1" "item2" "item3"

# Check command log
> CONFIG SET commandlog-enabled yes
> COMMANDLOG GET
```

## Rollback Plan

If issues arise with Valkey 8.1:

1. Create a new ElastiCache cluster with Valkey 7.2
2. Update the Valkey endpoint in environment variables
3. Restart ECS services
4. Delete the Valkey 8.1 cluster

Note: Valkey 8.1 is backward compatible, so rollback should rarely be necessary.