#!/bin/bash
set -e

# Handle SIGTERM for graceful shutdown
trap 'echo "Received SIGTERM, shutting down..."; kill -TERM $PID; wait $PID' TERM

# Default admin credentials if not provided
export ZO_ROOT_USER_EMAIL="${ZO_ROOT_USER_EMAIL:-admin@poc.com}"
export ZO_ROOT_USER_PASSWORD="${ZO_ROOT_USER_PASSWORD:-admin123}"

# S3 configuration (uses node IAM role)
export ZO_S3_PROVIDER="aws"
export ZO_S3_BUCKET_NAME="${ZO_S3_BUCKET_NAME:-company-aurora-logs-poc}"
export ZO_S3_REGION_NAME="${AWS_REGION}"
export ZO_S3_SERVER_URL="https://s3.${AWS_REGION}.amazonaws.com"

# Performance settings
export ZO_MEMORY_CACHE_ENABLED="true"
export ZO_MEMORY_CACHE_MAX_SIZE="${ZO_MEMORY_CACHE_MAX_SIZE:-2048}"
export ZO_QUERY_THREAD_NUM="${ZO_QUERY_THREAD_NUM:-4}"
export ZO_INGEST_ALLOWED_UPTO="${ZO_INGEST_ALLOWED_UPTO:-24}"
export ZO_PAYLOAD_LIMIT="${ZO_PAYLOAD_LIMIT:-209715200}"  # 200MB
export ZO_MAX_FILE_SIZE_ON_DISK="${ZO_MAX_FILE_SIZE_ON_DISK:-512}"  # 512MB

# Features
export ZO_PROMETHEUS_ENABLED="true"
export ZO_USAGE_REPORTING_ENABLED="false"
export ZO_PRINT_KEY_CONFIG="false"

echo "Starting OpenObserve v0.15 with configuration:"
echo "Data Dir: $ZO_DATA_DIR"
echo "HTTP Port: $ZO_HTTP_PORT"
echo "S3 Bucket: $ZO_S3_BUCKET_NAME"
echo "Memory Cache: $ZO_MEMORY_CACHE_MAX_SIZE MB"

# Start OpenObserve - the binary is at /app/openobserve in the base image
exec /app/openobserve
