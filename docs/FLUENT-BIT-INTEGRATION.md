# Fluent Bit Integration for Aurora Log Processing

## Overview

The Aurora Log System now supports Fluent Bit as a sidecar container for flexible log parsing. This allows production environments to handle various log formats without code changes.

## Architecture

```
Processor (raw logs) → TCP Forward → Fluent Bit (parsing) → OpenObserve
         └─────────────────────────────────────────────────┘
                          localhost:24224
```

## Implementation

### 1. Processor Configuration

The processor service is configured to send logs via TCP forward when `LOG_FORWARD_ENABLED=true`:

```yaml
env:
- name: LOG_FORWARD_ENABLED
  value: "true"
- name: LOG_FORWARD_HOST
  value: "localhost"
- name: LOG_FORWARD_PORT
  value: "24224"
- name: PARSING_MODE
  value: "passthrough"
```

### 2. Fluent Bit Sidecar

Fluent Bit runs as a sidecar container in the processor pod:
- Image: `fluent/fluent-bit:4.0.5-arm64`
- Listens on TCP port 24224 for log forwarding
- Applies Aurora-specific parsers
- Sends parsed logs to OpenObserve

### 3. Parsing Modes

- **passthrough**: Processor sends raw logs, Fluent Bit does all parsing
- **minimal**: Processor extracts basic metadata, Fluent Bit parses content
- **full**: Traditional mode - processor does all parsing (fallback)

## Configuration Files

### Fluent Bit Config (`11-fluent-bit-config.yaml`)

Contains:
- Main Fluent Bit configuration
- Parser definitions for Aurora logs
- Lua scripts for field extraction
- Output configuration for OpenObserve

### Parser Types

1. **Error Logs**
   ```
   2025-08-02 12:34:56 140234567890 [ERROR] Access denied for user...
   ```
   - Extracts: timestamp, thread_id, level, error_message

2. **Slow Query Logs**
   ```
   # Time: 2025-08-02T15:04:05.000000Z
   # User@Host: user[user] @ host [192.168.1.1]
   # Query_time: 2.5 Lock_time: 0.001 Rows_sent: 100 Rows_examined: 5000
   SET timestamp=1234567890;
   SELECT * FROM large_table WHERE...
   ```
   - Extracts: timestamp, user, host, query metrics, SQL query

3. **General Logs**
   ```
   2025-08-02 12:34:56 123 Query SELECT 1
   ```
   - Extracts: timestamp, thread_id, command, argument

### Timestamp Handling

The system preserves Aurora log timestamps through the entire pipeline:

1. **Processor**: Extracts timestamp from first few lines of log file
2. **TCP Forward**: Sends logs with extracted timestamp (not current time)
3. **Fluent Bit**: Parses and preserves timestamp in each log entry
4. **Lua Script**: Converts timestamp to `_timestamp` field (milliseconds) for OpenObserve
5. **OpenObserve**: Indexes logs using original Aurora timestamp

Result: Logs appear in OpenObserve at their actual Aurora creation time, not processing time.

## Deployment

### Option 1: Deploy with Fluent Bit (Recommended for Production)

```bash
# Deploy Fluent Bit config
kubectl apply -f 11-fluent-bit-config.yaml

# Deploy processor with Fluent Bit sidecar
kubectl apply -f 08-processor-with-fluent-bit.yaml

# Update configmap
kubectl apply -f 02-configmaps-fluent-bit.yaml
```

### Option 2: Keep Existing Setup

```bash
# Use original files without Fluent Bit
kubectl apply -f 08-processor.yaml
kubectl apply -f 02-configmaps.yaml
```

## Benefits

1. **Flexible Parsing**: Update parsers without rebuilding processor
2. **Production Ready**: Handle various Aurora versions/formats
3. **Field Extraction**: Extract custom fields (IPs, query patterns)
4. **Performance**: Fluent Bit is optimized for log parsing
5. **Hot Reload**: Update parsing rules via ConfigMap
6. **Timestamp Preservation**: Maintains original Aurora log timestamps

## Monitoring

### Fluent Bit Metrics

Access Fluent Bit metrics:
```bash
kubectl port-forward -n aurora-logs deployment/processor 2020:2020
curl http://localhost:2020/api/v1/metrics
```

### Health Check

```bash
curl http://localhost:2020/api/v1/health
```

## Customization

### Adding New Parsers

1. Edit the parser ConfigMap:
```bash
kubectl edit configmap fluent-bit-parsers -n aurora-logs
```

2. Add new parser definition:
```ini
[PARSER]
    Name              custom_aurora_format
    Format            regex
    Regex             <your-regex-pattern>
    Time_Key          timestamp
    Time_Format       %Y-%m-%d %H:%M:%S
```

3. Restart processor pods:
```bash
kubectl rollout restart deployment/processor -n aurora-logs
```

### Lua Script Customization

The Lua scripts can be modified to extract additional fields:
- `extract_query_info.lua`: Extracts query metrics and patterns
- `ensure_timestamp.lua`: Ensures proper timestamp formatting

## Troubleshooting

### Check Fluent Bit Logs
```bash
kubectl logs -n aurora-logs deployment/processor -c fluent-bit
```

### Verify TCP Forward Connection
```bash
kubectl exec -n aurora-logs deployment/processor -c processor -- netstat -an | grep 24224
```

### Test Parser
```bash
kubectl exec -n aurora-logs deployment/processor -c fluent-bit -- \
  fluent-bit -c /fluent-bit/etc/fluent-bit.conf \
  -R /fluent-bit/etc/custom_parsers.conf \
  -T "aurora_error_log" \
  -i "2025-08-02 12:34:56 123 [ERROR] Test message"
```

## Rollback

To rollback to processor-only parsing:
1. Set `LOG_FORWARD_ENABLED=false` in ConfigMap
2. Set `PARSING_MODE=full`
3. Restart processor pods

## Performance Considerations

- Fluent Bit adds ~100MB memory overhead
- CPU usage is minimal (~100m)
- Buffer storage prevents log loss
- Retry logic for OpenObserve delivery