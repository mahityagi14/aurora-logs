# Use ARM64 platform explicitly - Kafka 4.0
# NOTE: Kafka 4.0 requires Java 17 which is included in the bitnami/kafka:4.0 image
FROM --platform=linux/arm64 bitnami/kafka:4.0

USER root

# Install tini for proper signal handling
RUN install_packages tini

# Copy custom start script with execute permissions
COPY --chmod=755 start-kafka.sh /opt/bitnami/scripts/kafka/start-kafka.sh

# Fix permissions for all Bitnami directories that Kafka needs to write to
# The issue is that /opt/bitnami/kafka/config is a symlink to /bitnami/kafka/config
RUN mkdir -p /bitnami/kafka/data /bitnami/kafka/metadata /bitnami/kafka/config /bitnami/kafka/logs && \
    chown -R 1001:1001 /bitnami && \
    chown -R 1001:1001 /opt/bitnami && \
    chmod -R 775 /bitnami/kafka && \
    chmod -R 775 /opt/bitnami/kafka

# Ensure the startup scripts directory is writable
RUN chmod -R 755 /opt/bitnami/scripts/kafka/

USER 1001

# Set JVM options for container environment
ENV KAFKA_HEAP_OPTS="-Xmx2G -Xms2G"
ENV JMX_PORT=""

# Health check for Kafka 4.0 with KRaft mode
# Using kafka-broker-api-versions.sh as it's more reliable for health checks
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
  CMD kafka-broker-api-versions.sh --bootstrap-server localhost:9092 || exit 1

# Use tini as init system for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/bitnami/scripts/kafka/start-kafka.sh"]
