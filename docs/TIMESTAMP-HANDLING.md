# Timestamp Handling in Aurora Log System

## Overview

The Aurora Log System preserves the original timestamps from Aurora MySQL logs when ingesting into OpenObserve. This ensures that logs appear at their actual creation time rather than the processing time.

## Implementation Details

### 1. Timestamp Extraction

The processor service extracts timestamps from different log types:

#### Error Logs
- Format: `2025-08-02 12:34:56`
- Extracted from the beginning of each log line
- Alternative formats supported:
  - `2006-01-02T15:04:05Z`
  - `2006-01-02T15:04:05.000Z`

#### Slow Query Logs
- Primary format: `# Time: 2025-08-02T15:04:05.000000Z`
- Alternative format: `SET timestamp=1234567890;`
- Supports both ISO format and Unix timestamps

#### General Logs
- Attempts to extract timestamps from the beginning of lines
- Supports ISO-8601 format: `2025-08-02 12:34:56`
- Also handles Unix timestamps in brackets: `[1234567890]`

### 2. Timestamp Conversion

The processor converts extracted timestamps to:
- `_timestamp`: Unix milliseconds (for OpenObserve indexing)
- `@timestamp`: RFC3339 format (for display and compatibility)

### 3. OpenObserve Integration

When sending logs to OpenObserve:
```json
{
  "_timestamp": 1701234567890,  // Unix milliseconds - used for indexing
  "@timestamp": "2025-08-02T12:34:56Z",  // RFC3339 - for display
  "timestamp": "2025-08-02 12:34:56",  // Original format from log
  "message": "Log message content",
  "log_type": "error",
  // ... other fields
}
```

### 4. Fallback Behavior

If timestamp extraction fails:
- Uses current time as fallback
- Still populates both `_timestamp` and `@timestamp` fields
- Logs warning for debugging

## Benefits

1. **Accurate Timeline**: Logs appear at their actual occurrence time
2. **Time-based Queries**: Can search for logs from specific time periods
3. **Correlation**: Easy to correlate events across different log types
4. **Debugging**: Maintains chronological order of events

## Querying in OpenObserve

When querying logs in OpenObserve:
- Logs are indexed by their original Aurora timestamp
- Time range filters work on actual event time
- Can sort and group by original timestamps

Example query:
```sql
SELECT _timestamp, message, log_type 
FROM aurora_logs 
WHERE _timestamp >= '2025-08-02T00:00:00Z' 
  AND _timestamp < '2025-08-03T00:00:00Z'
ORDER BY _timestamp DESC
```

## Configuration

No additional configuration needed. The processor automatically:
1. Extracts timestamps from supported formats
2. Converts to OpenObserve format
3. Preserves original timestamp in the log entry

## Supported Timestamp Formats

| Log Type | Format Examples |
|----------|----------------|
| Error | `2025-08-02 12:34:56` |
| Slow Query | `2025-08-02T15:04:05.000000Z`, `SET timestamp=1234567890` |
| General | `2025-08-02 12:34:56`, `[1234567890]` |

## Troubleshooting

If timestamps are not being preserved:
1. Check log format matches supported patterns
2. Verify `_timestamp` field is present in OpenObserve
3. Ensure processor logs show successful timestamp parsing
4. Check OpenObserve stream settings for timestamp field configuration