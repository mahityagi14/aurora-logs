# Phase 4: EKS Cluster Creation and Service Deployment - Implementation Guide (2025)

## Overview
This phase covers creating the EKS cluster using AWS Console with custom configuration, deploying all services, and configuring the complete system for the Aurora MySQL Log Processing POC. Based on our analysis of 316 RDS instances with 6.67 TB accumulated logs, this guide includes both POC and production configurations.

**Key Architecture Updates:**
- EKS 1.32 (latest stable as of 2025)
- Node groups sized for actual workload
- No IRSA/OIDC - using node IAM roles
- No CloudWatch - all logs to OpenObserve
- Incremental log fetching implemented
- Production scaling guidelines included
- Jenkins CI/CD integration for ARM64 builds

## POC vs Production Configuration Summary

| Component | POC Configuration | Production Configuration | Scaling Factor |
|-----------|------------------|-------------------------|----------------|
| **EKS Nodes** | 3x t4g.large (2 vCPU, 8GB) | 20x m6i.8xlarge (32 vCPU, 128GB) | 213x compute |
| **Kafka Brokers** | 1 with 100GB | 3-5 with 1TB each | 30x storage |
| **Discovery Service** | 1 replica | 10 replicas (sharded) | 10x capacity |
| **Processor Service** | 2 replicas | 30-50 replicas | 25x throughput |
| **OpenObserve** | 1 instance, local storage | 3-node cluster, S3 backend | HA + unlimited |
| **Total Monthly Cost** | ~$300 | ~$15,000 | 50x |

## Variable Placeholders Reference
Final variables from all phases:

| Placeholder | Description | Source |
|------------|-------------|---------|
| [region] | Your AWS region | Phase 1 |
| [account-id] | Your 12-digit AWS account ID | Phase 1 |
| [vpc-id] | Your existing VPC ID | Phase 1 |
| [public-subnet-1] | First public subnet ID | Phase 1 |
| [public-subnet-2] | Second public subnet ID | Phase 1 |
| [public-subnet-3] | Third public subnet ID | Phase 1 |
| [cache-id] | ElastiCache cluster ID | Phase 2 |

## Step 1: Create EKS Cluster via Console

### 1.1 Start Cluster Creation

1. Navigate to **Amazon EKS Console** → **Clusters** → **Create cluster**
2. **Step 1: Configure cluster**:
   - **EKS Auto Mode**: Toggle **OFF** (we want custom configuration)
   - **Cluster configuration**:
     - Name: `aurora-logs-poc-cluster`
     - Kubernetes version: **1.32** (latest stable)
     - Cluster service role: Select `eksClusterRole` (from Phase 1)
   - Click **Next**

### 1.2 Specify Networking

3. **Step 2: Specify networking**:
   - **Networking**:
     - VPC: [vpc-id]
     - Subnets: Select all public subnets:
       - [public-subnet-1]
       - [public-subnet-2]  
     - Security groups: Leave empty (EKS will create default)
   - **Cluster endpoint access**:
     - Select **Public and private**
     - Public access source allowlist: Keep **0.0.0.0/0** (for POC)
   - **Control plane logging**: Leave all unchecked (logs will go to OpenObserve)
   - **Secrets encryption**: Leave disabled (for POC simplicity)
   - Click **Next**

### 1.3 Configure Add-ons

4. **Step 3: Select add-ons**:
   - Keep default add-ons:
     - ✓ **Amazon VPC CNI** (latest version)
     - ✓ **CoreDNS** (latest version)
     - ✓ **kube-proxy** (latest version)
     - ✓ **Amazon EBS CSI Driver** (latest version)
   - Click **Next**

5. **Step 4: Configure selected add-ons**:
   - For **Amazon EBS CSI Driver**:
     - Version: Select latest
     - IAM role: **Inherit from node** 
   - Leave other add-ons with default settings
   - Click **Next**

### 1.4 Review and Create

6. **Step 5: Review and create**:
   - Review all settings
   - Click **Create**

Wait for cluster creation (10-15 minutes). The **Status** should show **Active** when ready.

### 1.5 Configure kubectl Access

Once cluster is active:

```bash
# Update kubeconfig (in CloudShell or local terminal)
aws eks update-kubeconfig --region [region] --name aurora-logs-poc-cluster

# Verify connection
kubectl get svc
```

## Step 2: Create Managed Node Group

### Node Group Configuration Comparison

| Setting | POC Configuration | Production Configuration | Rationale |
|---------|------------------|-------------------------|-----------|
| **Instance Type** | t4g.large | m6i.8xlarge | Cost vs Performance |
| **Node Count** | 3 (min: 2, max: 6) | 20 (min: 10, max: 50) | Handle 316+ instances |
| **Disk Size** | 100 GB | 500 GB | Log processing space |
| **Disk Type** | gp3 | gp3 with 16K IOPS | I/O performance |

### 2.1 Create Node Group via Console

1. In **EKS Console** → Select your cluster → **Compute** tab → **Add node group**
2. **Step 1: Configure node group**:
   - **Node group configuration**:
     - Name: `aurora-logs-ng`
     - Node IAM role: Select `eksNodeGroupRole` (from Phase 1)
   - **Launch template**: Use Amazon EKS optimized AMI (default)
   - Click **Next**

3. **Step 2: Set compute and scaling configuration**:
   
   **POC Configuration:**
   - AMI type: **Amazon Linux 2023 (AL2023_ARM_64_STANDARD)**
   - Capacity type: **On-Demand**
   - Instance types: **t4g.large** (Graviton 2)
   - Disk size: **100** GiB
   - Desired size: **3**
   - Minimum size: **2**
   - Maximum size: **6**
   
   **Production Alternative:**
   - Instance types: **m6i.8xlarge**
   - Disk size: **500** GiB
   - Desired size: **20**
   - Minimum size: **10**
   - Maximum size: **50**

4. **Step 3: Specify networking**:
   - Subnets: Select all public subnets
   - Configure SSH access: **Disable**
   - Click **Next** → **Create**

Wait for node group to become **Active** (5-10 minutes).

## Step 3: Install AWS Load Balancer Controller

```bash
# Download IAM policy
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.10.0/docs/install/iam_policy.json

# Create policy
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json

# Attach to node role
aws iam attach-role-policy \
    --role-name eksNodeGroupRole \
    --policy-arn arn:aws:iam::[account-id]:policy/AWSLoadBalancerControllerIAMPolicy

# Install controller with Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=aurora-logs-poc-cluster \
  --set serviceAccount.create=true \
  --set region=[region] \
  --set vpcId=[vpc-id]
```

## Step 4: Deploy Storage Class

```bash
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
```

## Step 4.5: Configure Application Environment

### Environment Variables for DynamoDB Tables

The application uses three DynamoDB tables created in Phase 2. Ensure the ConfigMap includes:

```yaml
# k8s/configmaps/app-config.yaml
data:
  INSTANCE_TABLE: "aurora-instance-metadata"     # Stores RDS metadata
  TRACKING_TABLE: "aurora-log-file-tracking"     # Maintains processing state
  JOBS_TABLE: "aurora-log-processing-jobs"       # Tracks job history
```

### Service Data Flow with DynamoDB:

1. **Discovery Service**:
   - Reads from `TRACKING_TABLE` to check if logs are new
   - Writes RDS cluster/instance metadata to `INSTANCE_TABLE`
   - Uses Valkey to cache RDS API responses

2. **Processor Service**:
   - Creates job entries in `JOBS_TABLE` when starting
   - Updates `TRACKING_TABLE` with processing position
   - Updates job status in `JOBS_TABLE` when complete
   - Exposes HTTP endpoints for querying tables

## Step 5: Deploy Application

### 5.1 Apply Namespace and Core Resources

```bash
# Clone repository (if not already done)
git clone https://github.com/anshtyagi14/aurora-log-system.git
cd aurora-log-system

# Apply setup (namespaces and service accounts)
kubectl apply -f k8s/setup.yaml

# Update ConfigMaps with your values
sed -i "s/\[region\]/$REGION/g" k8s/configmaps/app-config.yaml
sed -i "s/\[cache-id\]/$CACHE_ID/g" k8s/configmaps/app-config.yaml
kubectl apply -f k8s/configmaps/

# Apply services
kubectl apply -f k8s/services/
```

### 5.2 Deploy Fluent Bit

```bash
# Apply Fluent Bit DaemonSet
kubectl apply -f k8s/daemonsets/fluent-bit-daemonset.yaml

# Verify Fluent Bit is running
kubectl get pods -n fluent-bit
```

### 5.3 Deploy Kafka First

```bash
# Update Kafka deployment with your ECR repository
sed -i "s/\[account-id\]/$ACCOUNT_ID/g" k8s/deployments/kafka-deployment.yaml
sed -i "s/\[region\]/$REGION/g" k8s/deployments/kafka-deployment.yaml

kubectl apply -f k8s/deployments/kafka-deployment.yaml

# Wait for Kafka to be ready
kubectl wait --for=condition=ready pod -l app=kafka -n aurora-logs --timeout=300s

# Initialize topics
KAFKA_POD=$(kubectl get pod -n aurora-logs -l app=kafka -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $KAFKA_POD -n aurora-logs -- bash -c "
  kafka-topics.sh --create --bootstrap-server localhost:9092 \
    --topic aurora-logs-slowquery --partitions 10 --replication-factor 1 \
    --config retention.ms=604800000 --config compression.type=snappy
  
  kafka-topics.sh --create --bootstrap-server localhost:9092 \
    --topic aurora-logs-error --partitions 10 --replication-factor 1 \
    --config retention.ms=604800000 --config compression.type=snappy
  
  kafka-topics.sh --list --bootstrap-server localhost:9092
"
```

### 5.4 Deploy OpenObserve

```bash
# Update OpenObserve deployment
sed -i "s/\[account-id\]/$ACCOUNT_ID/g" k8s/deployments/openobserve-deployment.yaml
sed -i "s/\[region\]/$REGION/g" k8s/deployments/openobserve-deployment.yaml

kubectl apply -f k8s/deployments/openobserve-deployment.yaml

# Wait for OpenObserve to be ready
kubectl wait --for=condition=ready pod -l app=openobserve -n aurora-logs --timeout=300s
```

### 5.5 Deploy Application Services

**POC Deployment:**
```bash
# Update deployments with ECR repository
sed -i "s/\[account-id\]/$ACCOUNT_ID/g" k8s/deployments/discovery-deployment.yaml
sed -i "s/\[region\]/$REGION/g" k8s/deployments/discovery-deployment.yaml

sed -i "s/\[account-id\]/$ACCOUNT_ID/g" k8s/deployments/processor-deployment.yaml
sed -i "s/\[region\]/$REGION/g" k8s/deployments/processor-deployment.yaml

# Deploy Discovery (1 instance)
kubectl apply -f k8s/deployments/discovery-deployment.yaml

# Deploy Processor (2 instances)
kubectl apply -f k8s/deployments/processor-deployment.yaml
```

**Production Deployment (for 316+ instances):**
```bash
# Scale Discovery with sharding
for i in {0..9}; do
  cat k8s/deployments/discovery-deployment.yaml | \
    sed "s/name: discovery/name: discovery-shard-$i/g" | \
    sed "s/app: discovery/app: discovery-shard-$i/g" | \
    sed "s/SHARD_ID: \"0\"/SHARD_ID: \"$i\"/g" | \
    sed "s/TOTAL_SHARDS: \"1\"/TOTAL_SHARDS: \"10\"/g" | \
    kubectl apply -f -
done

# Scale Processor
kubectl scale deployment processor -n aurora-logs --replicas=30
```

### 5.6 Deploy Ingress

```bash
kubectl apply -f k8s/ingress/openobserve-ingress.yaml

# Wait for ALB to be provisioned
sleep 60

# Get ALB DNS
ALB_DNS=$(kubectl get ingress -n aurora-logs openobserve-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "OpenObserve URL: http://$ALB_DNS"
```

## Step 6: Configure Monitoring

### 6.1 Install Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify metrics server
kubectl get deployment metrics-server -n kube-system
```

### 6.2 Create Horizontal Pod Autoscaler

```bash
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: processor-hpa
  namespace: aurora-logs
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: processor
  minReplicas: 2    # Production: 30
  maxReplicas: 10   # Production: 50
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
EOF
```

## Step 7: Configure OpenObserve

### 7.1 Access OpenObserve UI

```bash
# Get ALB DNS
ALB_DNS=$(kubectl get ingress -n aurora-logs openobserve-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "OpenObserve URL: http://$ALB_DNS"

# Default credentials
echo "Username: admin@poc.com"
echo "Password: admin123"
```

### 7.2 Create Log Streams

1. Navigate to **Logs** → **Streams**
2. You should see these streams automatically created:
   - `kubernetes` (from Fluent Bit)
   - `aurora-slowquery` (when first logs arrive)
   - `aurora-error` (when first logs arrive)

3. Configure retention (Production):
   - Navigate to **Settings** → **Streams**
   - Set retention policies:
     - Kubernetes logs: 7 days
     - Aurora logs: 30 days

## Step 8: Test the System

### 8.1 Verify Component Health

```bash
# Check all pods
kubectl get pods -n aurora-logs
kubectl get pods -n fluent-bit

# Check Discovery logs
kubectl logs -f deployment/discovery -n aurora-logs

# Check Processor logs  
kubectl logs -f deployment/processor -n aurora-logs

# Check Kafka consumer groups
KAFKA_POD=$(kubectl get pod -n aurora-logs -l app=kafka -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $KAFKA_POD -n aurora-logs -- \
  kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list

# View consumer lag
kubectl exec -it $KAFKA_POD -n aurora-logs -- \
  kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group aurora-processor-group --describe
```

### 8.2 Generate Test Load

```bash
# Connect to Aurora MySQL
mysql -h aurora-mysql-poc-01.cluster-[xxx].[region].rds.amazonaws.com \
  -u admin -p --ssl-mode=DISABLED

# Generate slow queries
USE mydb;

# Create test table
CREATE TABLE IF NOT EXISTS test_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

# Insert test data
INSERT INTO test_data (data) 
SELECT CONCAT('Test data ', FLOOR(RAND() * 1000000)) 
FROM information_schema.tables t1, information_schema.tables t2 
LIMIT 1000;

# Generate slow queries
SELECT SLEEP(2), COUNT(*) FROM test_data;
SELECT BENCHMARK(10000000, MD5('test'));
SELECT * FROM test_data WHERE data LIKE '%999%' ORDER BY RAND();

# Generate error
SELECT * FROM non_existent_table;

EXIT;
```

### 8.3 Monitor Processing

Watch logs being processed:

```bash
# Monitor Discovery finding new logs
kubectl logs -f deployment/discovery -n aurora-logs | grep "Starting log discovery"

# Monitor Processor activity
kubectl logs -f deployment/processor -n aurora-logs | grep "Processing log"

# Check DynamoDB tables
# 1. Verify instance registry is populated
aws dynamodb scan --table-name aurora-instance-metadata \
  --query "Count" --output text

# 2. Check tracking table for processed files
aws dynamodb scan --table-name aurora-log-file-tracking \
  --query "Count" --output text

# 3. View recent jobs
aws dynamodb query --table-name aurora-log-processing-jobs \
  --key-condition-expression "pk = :pk" \
  --expression-attribute-values '{":pk":{"S":"DATE#'$(date +%Y-%m-%d)'"}}' \
  --query "Items[*].status.S" --output text

# 4. Access processor API endpoints
PROCESSOR_POD=$(kubectl get pod -n aurora-logs -l app=processor -o jsonpath='{.items[0].metadata.name}')
# Get instance info
kubectl exec -n aurora-logs $PROCESSOR_POD -- curl -s localhost:8080/api/instances/YOUR_INSTANCE_ID
# Get job stats
kubectl exec -n aurora-logs $PROCESSOR_POD -- curl -s localhost:8080/api/jobs/stats
```

### 8.4 View Logs in OpenObserve

1. Access OpenObserve UI at `http://$ALB_DNS`
2. Navigate to **Logs** → **Explore**
3. Select stream `aurora-slowquery`
4. Set time range to last 1 hour
5. Run query to see processed slow queries

Example queries:
```sql
-- Find slowest queries
SELECT cluster_id, instance_id, query_time, sql 
FROM aurora-slowquery 
WHERE query_time > 1 
ORDER BY query_time DESC 
LIMIT 10

-- Count queries by instance
SELECT instance_id, COUNT(*) as query_count 
FROM aurora-slowquery 
GROUP BY instance_id 
ORDER BY query_count DESC
```

## Step 9: Production Optimization

### 9.1 For 316+ RDS Instances

```bash
# Update Discovery for sharding
kubectl set env deployment/discovery -n aurora-logs \
  TOTAL_SHARDS=10 \
  RATE_LIMIT_PER_SEC=200 \
  DISCOVERY_INTERVAL_MIN=3

# Scale Processor
kubectl scale deployment processor -n aurora-logs --replicas=30

# Update HPA for production
kubectl patch hpa processor-hpa -n aurora-logs --type merge -p '
{
  "spec": {
    "minReplicas": 30,
    "maxReplicas": 50
  }
}'

# Configure Kafka for production
kubectl exec -it $KAFKA_POD -n aurora-logs -- bash -c "
  kafka-configs.sh --bootstrap-server localhost:9092 \
    --entity-type brokers --entity-default \
    --alter --add-config num.network.threads=16,num.io.threads=16
"
```

### 9.2 Performance Tuning

**DynamoDB Optimization:**
```bash
# Enable auto-scaling alarms
aws cloudwatch put-metric-alarm \
  --alarm-name aurora-log-tracking-throttle \
  --alarm-description "DynamoDB throttling detected" \
  --metric-name UserErrors \
  --namespace AWS/DynamoDB \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=TableName,Value=aurora-log-file-tracking
```

**Kafka Partition Increase:**
```bash
kubectl exec -it $KAFKA_POD -n aurora-logs -- bash -c "
  kafka-topics.sh --bootstrap-server localhost:9092 \
    --alter --topic aurora-logs-slowquery \
    --partitions 50
  
  kafka-topics.sh --bootstrap-server localhost:9092 \
    --alter --topic aurora-logs-error \
    --partitions 50
"
```

## Step 10: Monitoring Dashboard

### 10.1 Create OpenObserve Dashboard

1. Navigate to **Dashboards** → **Create Dashboard**
2. Add panels for:

**System Health Panel:**
```sql
SELECT 
  namespace,
  pod_name,
  container_name,
  MAX(processed_timestamp) as last_seen
FROM kubernetes
WHERE namespace = 'aurora-logs'
GROUP BY namespace, pod_name, container_name
```

**Processing Rate Panel:**
```sql
SELECT 
  date_trunc('minute', _timestamp) as time,
  COUNT(*) as logs_processed
FROM aurora-slowquery
GROUP BY time
ORDER BY time DESC
```

**Error Rate Panel:**
```sql
SELECT 
  date_trunc('minute', _timestamp) as time,
  COUNT(*) as errors
FROM kubernetes
WHERE level = 'ERROR' AND namespace = 'aurora-logs'
GROUP BY time
```

### 10.2 Key Metrics to Monitor

| Metric | POC Target | Production Target | Alert Threshold |
|--------|------------|-------------------|-----------------|
| **RDS API Rate** | <100/sec | <1000/sec | 80% of limit |
| **Kafka Lag** | <1000 | <10000 | Growing trend |
| **Processing Rate** | 10 MB/s | 100 MB/s | <50% of target |
| **S3 Upload Rate** | 5 MB/s | 50 MB/s | Errors > 1% |
| **Memory Usage** | <80% | <70% | >90% |
| **Pod Restarts** | 0 | <5/hour | >10/hour |

## Production Readiness Checklist

### DynamoDB TTL Configuration
Before going to production, ensure TTL is properly configured:

```bash
# Enable TTL on instance-metadata table (7-day retention)
aws dynamodb update-time-to-live \
  --table-name aurora-instance-metadata \
  --time-to-live-specification "Enabled=true,AttributeName=ttl"

# Enable TTL on jobs table (30-day retention)  
aws dynamodb update-time-to-live \
  --table-name aurora-log-processing-jobs \
  --time-to-live-specification "Enabled=true,AttributeName=ttl"

# Verify TTL is enabled
aws dynamodb describe-time-to-live --table-name aurora-instance-metadata
aws dynamodb describe-time-to-live --table-name aurora-log-processing-jobs
```

**Note**: The tracking table should NOT have TTL as it maintains processing state.

### Complete Production Checklist:
- [ ] DynamoDB TTL enabled on instance-metadata and jobs tables
- [ ] All pods running with resource limits
- [ ] HPA configured for auto-scaling
- [ ] Valkey cache hit rate >70%
- [ ] Kafka partitions increased to 50
- [ ] Network policies applied
- [ ] Security scanning enabled
- [ ] Monitoring dashboards created
- [ ] Backup procedures documented
- [ ] Cost optimization verified

## Cleanup

To remove all resources:

```bash
# Delete application
kubectl delete namespace aurora-logs
kubectl delete namespace fluent-bit

# Delete node group (AWS Console)
# EKS Console → Cluster → Compute → Node groups → Delete

# Delete EKS cluster (AWS Console)
# EKS Console → Clusters → Delete

# Delete other resources
aws s3 rm s3://company-aurora-logs-poc --recursive
aws s3 rb s3://company-aurora-logs-poc

aws dynamodb delete-table --table-name aurora-instance-metadata
aws dynamodb delete-table --table-name aurora-log-file-tracking
aws dynamodb delete-table --table-name aurora-log-processing-jobs

# Delete Aurora cluster, ElastiCache, ALB via Console
```

### Debug Commands:
```bash
# Pod issues
kubectl describe pod <pod-name> -n aurora-logs
kubectl logs <pod-name> -n aurora-logs --previous

# Resource usage
kubectl top nodes
kubectl top pods -n aurora-logs

# Service discovery
kubectl get endpoints -n aurora-logs

# Storage issues
kubectl get pvc -n aurora-logs
```