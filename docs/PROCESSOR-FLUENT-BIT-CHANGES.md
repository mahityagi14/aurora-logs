# Processor Service - Fluent Bit Integration Changes

## Overview

The processor service has been updated to support forwarding raw logs to Fluent Bit via TCP forward protocol, allowing flexible log parsing without code changes.

## Code Changes

### 1. Configuration (Config struct)

Added new fields:
```go
type Config struct {
    // ... existing fields ...
    
    // Fluent Bit forwarding configuration
    LogForwardEnabled    bool   // Enable/disable forwarding
    LogForwardHost       string // Fluent Bit host (default: localhost)
    LogForwardPort       string // Fluent Bit port (default: 24224)
    ParsingMode          string // passthrough, minimal, or full
}
```

### 2. TCP Forward Client

Added `FluentBitForwarder` type:
```go
type FluentBitForwarder struct {
    address      string
    conn         net.Conn
    mu           sync.Mutex
    connected    bool
    reconnectCh  chan struct{}
}
```

Key methods:
- `Connect()`: Establishes TCP connection to Fluent Bit
- `Forward()`: Sends log entries using Fluent Bit forward protocol
- `Close()`: Closes the connection

### 3. Processing Logic

Modified `processLogOptimized()` to check forwarding mode:
```go
// Check if we should forward to Fluent Bit
if bp.config.LogForwardEnabled && bp.config.ParsingMode == "passthrough" {
    return bp.forwardLogToFluentBit(ctx, logMsg)
}
```

### 4. New Forwarding Method

Added `forwardLogToFluentBit()` that:
- Downloads log files from S3/RDS
- Sends raw log lines to Fluent Bit
- Includes minimal metadata (instance_id, log_type, etc.)
- Updates DynamoDB tracking status

## Environment Variables

New environment variables:
- `LOG_FORWARD_ENABLED`: Set to "true" to enable forwarding
- `LOG_FORWARD_HOST`: Fluent Bit host (default: localhost)
- `LOG_FORWARD_PORT`: Fluent Bit port (default: 24224)
- `PARSING_MODE`: Options are:
  - `passthrough`: Send raw logs to Fluent Bit
  - `minimal`: Extract basic fields, forward rest
  - `full`: Use processor parsing (default/fallback)

## Data Flow

### With Fluent Bit (passthrough mode):
```
Kafka → Processor → TCP Forward → Fluent Bit → OpenObserve
                    (raw logs)     (parsing)
```

### Without Fluent Bit (full mode):
```
Kafka → Processor → OpenObserve
        (parsing)
```

## Fluent Bit Forward Protocol

The processor sends data in Fluent Bit's forward protocol format:
```json
[
  "aurora.error",           // tag
  [
    [
      1234567890,          // timestamp (Unix seconds)
      {                    // record
        "message": "log line",
        "log_type": "error",
        "instance_id": "aurora-instance-1",
        "cluster_id": "aurora-cluster-1",
        "log_file_name": "error/mysql-error.log",
        "line_number": 1
      }
    ]
  ]
]
```

## Benefits

1. **No Code Changes for New Formats**: Update Fluent Bit parsers via ConfigMap
2. **Better Performance**: Fluent Bit is optimized for parsing
3. **Flexibility**: Can handle different Aurora versions/formats
4. **Gradual Migration**: Can run both modes simultaneously

## Deployment

The processor automatically detects Fluent Bit configuration from environment variables. When deployed with the Fluent Bit sidecar and proper environment variables, it will forward logs instead of parsing them.

## Backward Compatibility

The original parsing logic remains intact. To use processor parsing:
- Set `LOG_FORWARD_ENABLED=false`
- Or set `PARSING_MODE=full`

## Testing

Test TCP forwarding locally:
```bash
# Start a TCP listener
nc -l 24224

# Set environment variables
export LOG_FORWARD_ENABLED=true
export LOG_FORWARD_HOST=localhost
export LOG_FORWARD_PORT=24224
export PARSING_MODE=passthrough

# Run processor
./processor
```