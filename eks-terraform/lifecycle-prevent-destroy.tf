# This file documents which resources are protected from destruction during terraform destroy

# Note: The following resources are already protected because we're using data sources:
# - VPC and Subnets (using data sources)
# - Security Groups (using data sources)
# - IAM Roles and Users (using data sources)
# - RDS Subnet Group (part of existing RDS cluster)
# - ECR Repository (using data source)
# - EKS Cluster (using data source)
# - Aurora RDS Cluster (using data source)
# - DynamoDB tables (using data sources - tables should be emptied manually)
# - S3 aurora-logs bucket (using data source)

# Resources that WILL be destroyed on terraform destroy:
# - Kubernetes namespace
# - S3 k8s-logs bucket (force_destroy=true allows deletion with objects)
#
# Resources protected with lifecycle prevent_destroy:
# - ElastiCache Valkey cluster (per user request to reuse it)

# IMPORTANT: Before destroy, empty DynamoDB tables using one of these scripts:
# Option 1: ./scripts/empty-dynamodb-tables.sh (bash script)
# Option 2: python3 ./scripts/empty-dynamodb-tables.py (faster for large tables)
#
# These scripts will delete all data from:
# - aurora-instance-metadata
# - aurora-log-file-tracking  
# - aurora-log-processing-jobs
#
# The table structures will be preserved for reuse.