.PHONY: all build test clean docker-build docker-push deploy

# Variables
REGISTRY ?= your-registry.com
VERSION ?= latest
GOOS ?= linux
GOARCH ?= arm64

# Build targets
all: test build

build: build-discovery build-processor

build-discovery:
	cd discovery && \
	CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH) go build -ldflags="-w -s" -o discovery .

build-processor:
	cd processor && \
	CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH) go build -ldflags="-w -s" -o processor .

# Test targets
test: test-discovery test-processor test-common

test-discovery:
	cd discovery && go test -v -race -coverprofile=coverage.out ./...

test-processor:
	cd processor && go test -v -race -coverprofile=coverage.out ./...

test-common:
	cd common && go test -v -race -coverprofile=coverage.out ./...

test-integration:
	@echo "Running integration tests..."
	# Add integration test commands here

# Docker targets
docker-build: docker-build-discovery docker-build-processor docker-build-kafka docker-build-openobserve

docker-build-discovery:
	docker build -t $(REGISTRY)/aurora-log-system:discovery-$(VERSION) discovery/

docker-build-processor:
	docker build -t $(REGISTRY)/aurora-log-system:processor-$(VERSION) processor/

docker-build-kafka:
	docker build -t $(REGISTRY)/aurora-log-system:kafka-$(VERSION) kafka/

docker-build-openobserve:
	docker build -t $(REGISTRY)/aurora-log-system:openobserve-$(VERSION) openobserve/

docker-push:
	docker push $(REGISTRY)/aurora-log-system:discovery-$(VERSION)
	docker push $(REGISTRY)/aurora-log-system:processor-$(VERSION)
	docker push $(REGISTRY)/aurora-log-system:kafka-$(VERSION)
	docker push $(REGISTRY)/aurora-log-system:openobserve-$(VERSION)

# Kubernetes targets
deploy:
	cd k8s && ./apply-with-values.sh values.yaml

deploy-dry-run:
	cd k8s && kubectl apply --dry-run=client -f .

# Development targets
run-local-kafka:
	cd kafka && ./start-kafka.sh

run-local-openobserve:
	cd openobserve && ./start.sh

# Cleanup
clean:
	rm -f discovery/discovery processor/processor
	rm -f discovery/coverage.out processor/coverage.out common/coverage.out

# Code quality
lint:
	golangci-lint run ./...

fmt:
	go fmt ./...

vet:
	go vet ./...

# Performance testing
bench:
	cd discovery && go test -bench=. -benchmem ./...
	cd processor && go test -bench=. -benchmem ./...

# Load testing
load-test:
	@echo "Running load tests..."
	# Add load test commands here (e.g., using k6 or vegeta)