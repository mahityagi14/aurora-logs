# Aurora Log System - Fixes Applied

## Issues Fixed

### 1. Service Discovery Registration
**Problem**: ECS services were not registering with AWS Service Discovery, causing DNS resolution failures.
**Fix**: Added `service_registries` blocks to all ECS service definitions in `terraform/ecs-services.tf`:
- Discovery service
- Processor service  
- Kafka service
- OpenObserve service

### 2. Valkey Connection URL
**Problem**: Redis connection URL was missing the port number (`:6379`).
**Fix**: Updated the `VALKEY_URL` environment variable in the Discovery service task definition to include the port:
```
redis://${endpoint}:6379
```

### 3. Discovery Service DynamoDB Operations
**Problem**: Discovery service was trying to save cluster-only data to the instance table, which requires both `cluster_id` and `instance_id` as keys.
**Fix**: Commented out the `saveClusterDetails` call in `discovery/main.go`. Cluster information is now saved along with instance data.

### 4. Dependencies
**Fix**: Added explicit dependencies on Service Discovery resources in all ECS service definitions to ensure proper resource creation order.

## Next Steps

1. Run `terraform plan` to review the changes
2. Run `terraform apply` to apply the fixes
3. The services will automatically redeploy with the new configuration
4. Service Discovery will enable inter-service communication
5. Discovery service will start discovering Aurora instances and publishing to Kafka
6. Processor service will consume from Kafka and send logs to OpenObserve

## Expected Outcome

After applying these changes:
- Services will be able to resolve DNS names like `kafka.aurora-logs.local`
- Discovery service will connect to Valkey for caching
- Aurora instance metadata will be properly stored in DynamoDB
- Log processing pipeline will function end-to-end