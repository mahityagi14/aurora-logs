# Makefile for Terraform operations

.PHONY: help init plan apply destroy fmt validate clean

# Default environment
ENV ?= poc

help:
	@echo "Available targets:"
	@echo "  init        - Initialize Terraform"
	@echo "  plan        - Create execution plan"
	@echo "  apply       - Apply infrastructure changes"
	@echo "  destroy     - Destroy infrastructure"
	@echo "  fmt         - Format Terraform files"
	@echo "  validate    - Validate Terraform configuration"
	@echo "  clean       - Clean Terraform files"
	@echo ""
	@echo "Usage: make <target> ENV=<poc|production>"
	@echo "Example: make plan ENV=production"

init:
	@echo "Initializing Terraform..."
	terraform init -upgrade

plan: validate
	@echo "Creating execution plan for $(ENV) environment..."
	@if [ ! -f terraform.tfvars.$(ENV) ]; then \
		echo "Error: terraform.tfvars.$(ENV) not found!"; \
		echo "Copy terraform.tfvars.$(ENV).example to terraform.tfvars.$(ENV) and update values"; \
		exit 1; \
	fi
	terraform plan -var-file=terraform.tfvars.$(ENV) -out=tfplan.$(ENV)

apply:
	@echo "Applying infrastructure for $(ENV) environment..."
	@if [ ! -f tfplan.$(ENV) ]; then \
		echo "Error: No plan found! Run 'make plan ENV=$(ENV)' first"; \
		exit 1; \
	fi
	terraform apply tfplan.$(ENV)
	@rm -f tfplan.$(ENV)

destroy:
	@echo "WARNING: This will destroy all infrastructure for $(ENV) environment!"
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read confirm
	@if [ ! -f terraform.tfvars.$(ENV) ]; then \
		echo "Error: terraform.tfvars.$(ENV) not found!"; \
		exit 1; \
	fi
	terraform destroy -var-file=terraform.tfvars.$(ENV)

fmt:
	@echo "Formatting Terraform files..."
	terraform fmt -recursive

validate: fmt
	@echo "Validating Terraform configuration..."
	terraform validate

clean:
	@echo "Cleaning Terraform files..."
	rm -rf .terraform
	rm -f terraform.tfstate*
	rm -f tfplan.*
	rm -f .terraform.lock.hcl

# Additional useful targets

output:
	@echo "Showing outputs for current state..."
	terraform output

output-json:
	@echo "Showing outputs in JSON format..."
	terraform output -json > outputs.$(ENV).json
	@echo "Outputs saved to outputs.$(ENV).json"

kubeconfig:
	@echo "Configuring kubectl..."
	@eval $$(terraform output -raw configure_kubectl)
	kubectl config current-context

cost:
	@echo "Estimating monthly costs..."
	@echo "Note: This requires Infracost to be installed"
	@which infracost > /dev/null || (echo "Infracost not found. Install from https://www.infracost.io/docs/" && exit 1)
	infracost breakdown --path . --terraform-var-file terraform.tfvars.$(ENV)

graph:
	@echo "Generating infrastructure graph..."
	terraform graph | dot -Tpng > infrastructure-$(ENV).png
	@echo "Graph saved to infrastructure-$(ENV).png"

# State management helpers

state-list:
	@echo "Listing resources in state..."
	terraform state list

state-backup:
	@echo "Creating state backup..."
	@mkdir -p backups
	@cp terraform.tfstate backups/terraform.tfstate.$$(date +%Y%m%d_%H%M%S)
	@echo "State backed up to backups/"

# Import existing resources example

import-vpc:
	@echo "Example: Import existing VPC"
	@echo "terraform import module.vpc.aws_vpc.main vpc-xxxxxx"

# Workspace management

workspace-list:
	terraform workspace list

workspace-new:
	@read -p "Enter workspace name: " ws_name; \
	terraform workspace new $$ws_name

workspace-select:
	@read -p "Enter workspace name: " ws_name; \
	terraform workspace select $$ws_name