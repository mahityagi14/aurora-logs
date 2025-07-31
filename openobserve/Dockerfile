# Use ARM64 platform explicitly with latest version
FROM --platform=linux/arm64 openobserve/openobserve:v0.15.0-rc4

# Set working directory
WORKDIR /app

# Copy custom start script with permissions
COPY --chmod=755 --chown=1000:1000 start.sh /app/start.sh

# Environment variables for configuration
ENV ZO_DATA_DIR="/data"
ENV ZO_HTTP_PORT="5080"
ENV ZO_HTTP_ADDR="0.0.0.0"
ENV ZO_TELEMETRY_ENABLED="false"

# Health check using wget (more likely to be available than curl)
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:5080/healthz || exit 1

EXPOSE 5080

VOLUME ["/data"]

# Use exec form for proper signal handling
ENTRYPOINT ["/app/start.sh"]
