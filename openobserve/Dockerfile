# Use ARM64 platform explicitly with latest version
FROM --platform=linux/arm64 openobserve/openobserve:v0.15.0-rc4

# Environment variables for configuration
ENV ZO_DATA_DIR="/data" \
    ZO_HTTP_PORT="5080" \
    ZO_HTTP_ADDR="0.0.0.0" \
    ZO_TELEMETRY_ENABLED="false" \
    ZO_NODE_ROLE="all" \
    ZO_LOCAL_MODE="true"

# Health check using wget (more likely to be available than curl)
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:5080/healthz || exit 1
