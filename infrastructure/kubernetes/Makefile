# Aurora Log System - Kubernetes Makefile
# Simple commands for managing the deployment

.PHONY: help deploy setup-iam health-check validate clean clean-iam logs-discovery logs-processor status

# Default target
help:
	@echo "Aurora Log System - Kubernetes Management"
	@echo ""
	@echo "Available commands:"
	@echo "  make deploy         - Deploy the entire system"
	@echo "  make clean          - Remove all K8s resources"
	@echo "  make status         - Show current status"
	@echo "  make health         - Run health check"
	@echo "  make logs           - Show processor logs"
	@echo "  make logs-k8s       - Show K8s log collector"
	@echo "  make cost           - Show cost optimization status"
	@echo "  make setup-iam      - Setup IAM roles (one-time)"
	@echo "  make clean-iam      - Remove IAM roles"

# Setup IAM roles
setup-iam:
	@./setup-iam.sh

# Deploy everything (cost-optimized by default)
deploy:
	@./deploy.sh

# Health check
health:
	@./health-check.sh

# Show status
status:
	@echo "=== Deployments ==="
	@kubectl get deployments -n aurora-logs
	@echo "\n=== Pods ==="
	@kubectl get pods -n aurora-logs
	@echo "\n=== Services ==="
	@kubectl get svc -n aurora-logs
	@echo "\n=== HPA Status ==="
	@kubectl get hpa -n aurora-logs

# Show processor logs
logs:
	kubectl logs -f deployment/processor -n aurora-logs -c processor

# Show Fluent Bit logs  
logs-fb:
	kubectl logs -f deployment/processor -n aurora-logs -c fluent-bit

# Show K8s log collector
logs-k8s:
	kubectl logs -f daemonset/fluent-bit-k8s -n aurora-logs

# Show cost optimization status
cost:
	@echo "=== Cost Optimization Status ==="
	@echo "\n--- Pod Count ---"
	@kubectl get pods -n aurora-logs --no-headers | awk '{print $$1}' | cut -d'-' -f1-2 | sort | uniq -c
	@echo "\n--- HPA Status ---"
	@kubectl get hpa -n aurora-logs
	@echo "\n--- Resource Usage ---"
	@kubectl top pods -n aurora-logs 2>/dev/null || echo "Metrics server not available"

# Clean up K8s resources
clean:
	@./cleanup.sh

# Clean up IAM roles
clean-iam:
	@./cleanup-iam.sh

