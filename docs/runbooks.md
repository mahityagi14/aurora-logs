# Aurora Log System - Operational Runbooks

This document contains runbooks for common operational issues with the Aurora Log System.

## Table of Contents

1. [System Health Check](#system-health-check)
2. [Common Issues](#common-issues)
   - [Processor Not Processing Logs](#processor-not-processing-logs)
   - [High Memory Usage](#high-memory-usage)
   - [Kafka Consumer Lag](#kafka-consumer-lag)
   - [DynamoDB Throttling](#dynamodb-throttling)
   - [Circuit Breaker Open](#circuit-breaker-open)
3. [Emergency Procedures](#emergency-procedures)
4. [Recovery Procedures](#recovery-procedures)

---

## System Health Check

### Quick Health Check Commands

```bash
# Check all pods status
kubectl get pods -n aurora-logs

# Check service logs
kubectl logs -n aurora-logs -l app=discovery --tail=100
kubectl logs -n aurora-logs -l app=processor --tail=100

# Check Kafka consumer lag
kubectl exec -n aurora-logs kafka-0 -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group aurora-processor-group \
  --describe

# Check DynamoDB tables
aws dynamodb describe-table --table-name aurora-log-file-tracking
aws dynamodb describe-table --table-name aurora-log-checkpoints
aws dynamodb describe-table --table-name aurora-log-dlq
```

---

## Common Issues

### Processor Not Processing Logs

**Symptoms:**
- Logs are discovered but not processed
- Consumer lag increasing
- No new entries in OpenObserve

**Investigation Steps:**

1. Check processor pod status:
```bash
kubectl get pods -n aurora-logs -l app=processor
kubectl describe pod -n aurora-logs <processor-pod-name>
```

2. Check processor logs for errors:
```bash
kubectl logs -n aurora-logs -l app=processor --tail=200 | grep -E "(ERROR|WARN)"
```

3. Check if processor can reach OpenObserve:
```bash
kubectl exec -n aurora-logs <processor-pod> -- curl -I http://openobserve-service:5080/healthz
```

4. Check DynamoDB tracking table:
```bash
aws dynamodb scan --table-name aurora-log-file-tracking \
  --filter-expression "#s = :status" \
  --expression-attribute-names '{"#s": "status"}' \
  --expression-attribute-values '{":status": {"S": "processing"}}' \
  --max-items 10
```

**Resolution:**

1. If pod is crashed/restarting:
```bash
# Delete pod to force restart
kubectl delete pod -n aurora-logs <processor-pod-name>

# Scale down and up
kubectl scale deployment processor -n aurora-logs --replicas=0
kubectl scale deployment processor -n aurora-logs --replicas=2
```

2. If OpenObserve is unreachable:
```bash
# Check OpenObserve service
kubectl get svc openobserve-service -n aurora-logs
kubectl get endpoints openobserve-service -n aurora-logs

# Restart OpenObserve if needed
kubectl rollout restart deployment openobserve -n aurora-logs
```

3. If logs are stuck in processing:
```bash
# Check for checkpoints
aws dynamodb scan --table-name aurora-log-checkpoints --max-items 10

# Manual reset if needed (use with caution)
aws dynamodb update-item \
  --table-name aurora-log-file-tracking \
  --key '{"instance_id": {"S": "INSTANCE_ID"}, "log_file_name": {"S": "LOG_FILE"}}' \
  --update-expression "SET #s = :status" \
  --expression-attribute-names '{"#s": "status"}' \
  --expression-attribute-values '{":status": {"S": "discovered"}}'
```

### High Memory Usage

**Symptoms:**
- Pods getting OOMKilled
- Slow processing
- High memory metrics

**Investigation Steps:**

1. Check resource usage:
```bash
kubectl top pods -n aurora-logs
kubectl describe node <node-name> | grep -A5 "Allocated resources"
```

2. Check for memory leaks:
```bash
# Get memory profile (if profiling enabled)
kubectl port-forward -n aurora-logs <pod-name> 6060:6060
go tool pprof -http=:8080 http://localhost:6060/debug/pprof/heap
```

**Resolution:**

1. Increase memory limits:
```yaml
# Edit deployment
kubectl edit deployment processor -n aurora-logs
# Update resources.limits.memory
```

2. Reduce batch sizes:
```bash
kubectl set env deployment/processor -n aurora-logs BATCH_SIZE=500
kubectl set env deployment/processor -n aurora-logs MAX_CONCURRENCY=3
```

3. Rolling restart:
```bash
kubectl rollout restart deployment processor -n aurora-logs
kubectl rollout status deployment processor -n aurora-logs
```

### Kafka Consumer Lag

**Symptoms:**
- Increasing consumer lag
- Delayed log processing
- Messages timing out

**Investigation Steps:**

1. Check consumer group status:
```bash
kubectl exec -n aurora-logs kafka-0 -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group aurora-processor-group \
  --describe
```

2. Check topic details:
```bash
kubectl exec -n aurora-logs kafka-0 -- kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --describe \
  --topic aurora-logs-error
```

**Resolution:**

1. Scale up processors:
```bash
kubectl scale deployment processor -n aurora-logs --replicas=5
```

2. Reset consumer offset (if needed):
```bash
# Stop processors first
kubectl scale deployment processor -n aurora-logs --replicas=0

# Reset to earliest
kubectl exec -n aurora-logs kafka-0 -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group aurora-processor-group \
  --topic aurora-logs-error \
  --reset-offsets \
  --to-earliest \
  --execute

# Start processors
kubectl scale deployment processor -n aurora-logs --replicas=2
```

### DynamoDB Throttling

**Symptoms:**
- ThrottledRequests in CloudWatch
- Slow discovery/processing
- Errors in logs about DynamoDB

**Investigation Steps:**

1. Check CloudWatch metrics:
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ThrottledRequests \
  --dimensions Name=TableName,Value=aurora-log-file-tracking \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

2. Check table capacity:
```bash
aws dynamodb describe-table --table-name aurora-log-file-tracking | jq '.Table.BillingModeSummary'
```

**Resolution:**

1. For on-demand tables experiencing throttling:
```bash
# DynamoDB auto-scales but may need time
# Reduce request rate temporarily
kubectl set env deployment/discovery -n aurora-logs DISCOVERY_BATCH_SIZE=50
kubectl set env deployment/discovery -n aurora-logs RDS_API_RATE_LIMIT=5
```

2. Add jitter to requests:
```bash
# Already implemented in circuit breaker
# Increase circuit breaker timeout if needed
kubectl set env deployment/processor -n aurora-logs CIRCUIT_BREAKER_TIMEOUT_SEC=60
```

### Circuit Breaker Open

**Symptoms:**
- "circuit breaker is open" errors in logs
- No processing happening
- Services appear healthy but not working

**Investigation Steps:**

1. Check logs for circuit breaker state:
```bash
kubectl logs -n aurora-logs -l app=processor --tail=1000 | grep -i "circuit"
```

2. Identify root cause:
```bash
# Check for repeated failures
kubectl logs -n aurora-logs -l app=processor --tail=1000 | grep -E "(ERROR|failed)" | tail -20
```

**Resolution:**

1. Fix underlying issue first (network, permissions, etc.)

2. Wait for automatic recovery (30 seconds by default)

3. Force reset by restarting pods:
```bash
kubectl rollout restart deployment processor -n aurora-logs
```

4. Adjust circuit breaker settings if needed:
```bash
kubectl set env deployment/processor -n aurora-logs CIRCUIT_BREAKER_MAX_FAILURES=10
kubectl set env deployment/processor -n aurora-logs CIRCUIT_BREAKER_TIMEOUT_SEC=15
```

---

## Emergency Procedures

### Complete System Stop

```bash
# Stop all processing
kubectl scale deployment discovery processor -n aurora-logs --replicas=0

# Stop Kafka consumers
kubectl exec -n aurora-logs kafka-0 -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group aurora-processor-group \
  --timeout 30000 \
  --command-config /dev/null \
  --delete
```

### Data Recovery from DLQ

```bash
# List DLQ entries
aws dynamodb scan --table-name aurora-log-dlq \
  --max-items 100 \
  --projection-expression "message_id,instance_id,log_file_name,failed_at,error"

# Reprocess specific message
# 1. Get the original message from DLQ
# 2. Send to Kafka topic again
# 3. Delete from DLQ after successful processing
```

### Roll Back Deployment

```bash
# Check rollout history
kubectl rollout history deployment processor -n aurora-logs

# Roll back to previous version
kubectl rollout undo deployment processor -n aurora-logs

# Roll back to specific revision
kubectl rollout undo deployment processor -n aurora-logs --to-revision=2
```

---

## Recovery Procedures

### After Outage Recovery

1. **Check system health:**
```bash
./deploy.sh poc status
```

2. **Clear any stuck processing states:**
```bash
# Find stuck items
aws dynamodb scan --table-name aurora-log-file-tracking \
  --filter-expression "#s = :status AND #u < :old_time" \
  --expression-attribute-names '{"#s": "status", "#u": "updated_at"}' \
  --expression-attribute-values '{
    ":status": {"S": "processing"},
    ":old_time": {"N": "'$(date -d '1 hour ago' +%s)'"}
  }'
```

3. **Resume processing gradually:**
```bash
# Start with single replica
kubectl scale deployment discovery -n aurora-logs --replicas=1
kubectl scale deployment processor -n aurora-logs --replicas=1

# Monitor for 5 minutes
sleep 300

# Scale up if healthy
kubectl scale deployment discovery -n aurora-logs --replicas=2
kubectl scale deployment processor -n aurora-logs --replicas=3
```

### Checkpoint Recovery

If processing was interrupted:

1. **Check existing checkpoints:**
```bash
aws dynamodb scan --table-name aurora-log-checkpoints --max-items 20
```

2. **Processing will automatically resume from checkpoints**

3. **Monitor progress:**
```bash
kubectl logs -n aurora-logs -l app=processor -f | grep -i "checkpoint"
```

### Manual Checkpoint Cleanup

For checkpoints older than 7 days (if TTL fails):

```bash
# List old checkpoints
aws dynamodb scan --table-name aurora-log-checkpoints \
  --filter-expression "#u < :old_time" \
  --expression-attribute-names '{"#u": "updated_at"}' \
  --expression-attribute-values '{":old_time": {"N": "'$(date -d '7 days ago' +%s)'"}}'

# Delete specific checkpoint
aws dynamodb delete-item \
  --table-name aurora-log-checkpoints \
  --key '{"instance_id": {"S": "INSTANCE_ID"}, "log_file_name": {"S": "LOG_FILE"}}'
```

---

## Monitoring Commands

### Quick Monitoring Dashboard

```bash
# Create a monitoring script
cat > monitor.sh << 'EOF'
#!/bin/bash
clear
echo "=== Aurora Log System Monitor ==="
echo "Time: $(date)"
echo ""
echo "=== Pod Status ==="
kubectl get pods -n aurora-logs
echo ""
echo "=== Kafka Lag ==="
kubectl exec -n aurora-logs kafka-0 -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group aurora-processor-group \
  --describe 2>/dev/null | grep -E "(TOPIC|aurora-logs)"
echo ""
echo "=== Recent Errors ==="
kubectl logs -n aurora-logs -l app=processor --since=5m --tail=10 | grep ERROR || echo "No errors"
echo ""
echo "=== Processing Status ==="
aws dynamodb scan --table-name aurora-log-file-tracking \
  --projection-expression "#s" \
  --expression-attribute-names '{"#s": "status"}' \
  --query 'Items[*].status.S' \
  --output text | sort | uniq -c
EOF

chmod +x monitor.sh
watch -n 30 ./monitor.sh
```

---

## Contact Information

**Escalation Path:**
1. On-call SRE
2. Platform Team Lead
3. Aurora DBA Team (for RDS issues)
4. AWS Support (for service issues)

**Key Dashboards:**
- OpenObserve: http://openobserve-alb-355407172.us-east-1.elb.amazonaws.com
- CloudWatch: https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=aurora-logs
- Kubernetes Dashboard: `kubectl proxy` then http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/