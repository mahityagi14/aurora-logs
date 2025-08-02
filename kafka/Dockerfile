# Use Confluent Kafka open-source image (CP-Kafka) - ARM64 specific version 8.0.0
# This includes Apache Kafka and open-source components only
FROM confluentinc/cp-kafka:8.0.0.arm64

USER root

# Install tini for proper signal handling
RUN yum install -y https://github.com/krallin/tini/releases/download/v0.19.0/tini_0.19.0-aarch64.rpm && \
    yum clean all

# Create necessary directories
RUN mkdir -p /var/lib/kafka/data /var/lib/kafka/logs /etc/kafka && \
    chown -R appuser:appuser /var/lib/kafka /etc/kafka

# Copy custom start script with execute permissions
COPY --chmod=755 start-kafka.sh /usr/local/bin/start-kafka.sh

USER appuser

# Set JVM options for container environment
ENV KAFKA_HEAP_OPTS="-Xmx2G -Xms2G"
ENV KAFKA_JVM_PERFORMANCE_OPTS="-XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35 -XX:+ExplicitGCInvokesConcurrent"
ENV KAFKA_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/log4j.properties"

# Expose ports
EXPOSE 9092 9093

# Health check using kafka-broker-api-versions
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
  CMD kafka-broker-api-versions --bootstrap-server localhost:9092 || exit 1

# Use tini as init system for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/start-kafka.sh"]