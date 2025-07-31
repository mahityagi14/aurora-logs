# Build stage
FROM golang:1.23-alpine AS builder

RUN apk add --no-cache git ca-certificates

WORKDIR /app

# Copy processor module files
COPY processor/go.mod processor/*.go processor/

WORKDIR /app/processor

# Download dependencies and tidy
RUN go mod tidy

# Build without -a flag for faster builds
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build \
    -ldflags="-w -s" \
    -o processor .

# Final stage
FROM alpine:3.22

# Install ca-certificates, tzdata, and tini for proper signal handling
RUN apk --no-cache add ca-certificates tzdata tini

# Create non-root user
RUN adduser -D -u 1000 appuser

WORKDIR /app
COPY --from=builder /app/processor/processor .
RUN chown -R appuser:appuser /app

USER appuser

# Set GOMAXPROCS to match ECS CPU allocation
ENV GOMAXPROCS=2

# Health check with longer start period for initialization
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD ["./processor", "-health"]

# Use tini as PID 1 for proper signal handling
ENTRYPOINT ["/sbin/tini", "--"]

# Use exec form for proper signal forwarding
CMD ["./processor"]