# Build stage
FROM golang:1.23-alpine AS builder

RUN apk add --no-cache git ca-certificates

WORKDIR /app

# Copy discovery module files
COPY discovery/go.mod discovery/*.go discovery/

WORKDIR /app/discovery

# Download dependencies and tidy
RUN go mod tidy

# Build without -a flag for faster builds
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build \
    -ldflags="-w -s" \
    -o discovery .

# Final stage
FROM alpine:3.22

# Install ca-certificates and tzdata
RUN apk --no-cache add ca-certificates tzdata

# Create non-root user
RUN adduser -D -u 1000 appuser

WORKDIR /app
COPY --from=builder /app/discovery/discovery .
RUN chown -R appuser:appuser /app

USER appuser

# Set GOMAXPROCS to match ECS CPU allocation
ENV GOMAXPROCS=2

# Health check with longer start period for initialization
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD ["./discovery", "-health"]

# Use exec form for proper signal forwarding
# The Go binary can handle signals directly
ENTRYPOINT ["./discovery"]