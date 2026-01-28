# =============================================================================
# Kimi K2.5 GCP Deployment - Makefile
# =============================================================================
# Convenience commands for managing the deployment.
#
# Usage:
#   make deploy      # Deploy infrastructure
#   make start       # Start instance and configure access
#   make stop        # Stop instance
#   make status      # Check status
#   make destroy     # Destroy all resources
# =============================================================================

# Default configuration (override with environment variables or make args)
PROJECT_ID ?= $(shell gcloud config get-value project 2>/dev/null)
ZONE ?= us-central1-a
INSTANCE_NAME ?= kimi-k25-poc

# Colors for output
BLUE := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
NC := \033[0m # No Color

.PHONY: help init deploy start stop status destroy logs ssh clean

# =============================================================================
# Help
# =============================================================================

help: ## Show this help message
	@echo ""
	@echo "Kimi K2.5 GCP Deployment - Available Commands"
	@echo "=============================================="
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Configuration:"
	@echo "  PROJECT_ID:    $(PROJECT_ID)"
	@echo "  ZONE:          $(ZONE)"
	@echo "  INSTANCE_NAME: $(INSTANCE_NAME)"
	@echo ""

# =============================================================================
# Setup
# =============================================================================

init: ## Initialize Terraform
	@echo "$(BLUE)Initializing Terraform...$(NC)"
	cd terraform && terraform init

validate: ## Validate Terraform configuration
	@echo "$(BLUE)Validating Terraform configuration...$(NC)"
	cd terraform && terraform validate

plan: ## Show Terraform execution plan
	@echo "$(BLUE)Generating Terraform plan...$(NC)"
	cd terraform && terraform plan

# =============================================================================
# Deployment
# =============================================================================

deploy: init ## Deploy infrastructure with Terraform
	@echo "$(BLUE)Deploying Kimi K2.5 infrastructure...$(NC)"
	cd terraform && terraform apply -auto-approve
	@echo ""
	@echo "$(GREEN)Deployment complete!$(NC)"
	@echo "Run 'make start' to start the instance."

start: ## Start the instance and configure access
	@echo "$(BLUE)Starting Kimi K2.5 instance...$(NC)"
	./scripts/start-poc.sh $(PROJECT_ID) $(ZONE) $(INSTANCE_NAME)

stop: ## Stop the instance
	@echo "$(BLUE)Stopping Kimi K2.5 instance...$(NC)"
	./scripts/stop-poc.sh $(PROJECT_ID) $(ZONE) $(INSTANCE_NAME)

# =============================================================================
# Operations
# =============================================================================

status: ## Check deployment status
	@echo "$(BLUE)Checking deployment status...$(NC)"
	./scripts/status.sh $(PROJECT_ID) $(ZONE) $(INSTANCE_NAME)

logs: ## View container logs
	@echo "$(BLUE)Fetching container logs...$(NC)"
	gcloud compute ssh $(INSTANCE_NAME) --zone=$(ZONE) --command='docker logs -f --tail 100 kimi-k25-server'

ssh: ## SSH into the instance
	@echo "$(BLUE)Connecting via SSH...$(NC)"
	gcloud compute ssh $(INSTANCE_NAME) --zone=$(ZONE)

gpu: ## Check GPU status
	@echo "$(BLUE)Checking GPU status...$(NC)"
	gcloud compute ssh $(INSTANCE_NAME) --zone=$(ZONE) --command='watch -n 1 nvidia-smi'

api: ## Test API endpoint
	@echo "$(BLUE)Testing API endpoint...$(NC)"
	@EXTERNAL_IP=$$(gcloud compute instances describe $(INSTANCE_NAME) --zone=$(ZONE) --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null); \
	if [ -n "$$EXTERNAL_IP" ]; then \
		echo "Testing http://$$EXTERNAL_IP:8000/v1/models"; \
		curl -s http://$$EXTERNAL_IP:8000/v1/models | python3 -m json.tool 2>/dev/null || echo "$(YELLOW)API not responding$(NC)"; \
	else \
		echo "$(RED)Could not get external IP. Is the instance running?$(NC)"; \
	fi

# =============================================================================
# Cleanup
# =============================================================================

destroy: ## Destroy all Terraform-managed resources
	@echo "$(YELLOW)WARNING: This will destroy all resources!$(NC)"
	@read -p "Are you sure? [y/N] " confirm && [ $$confirm = y ] || exit 1
	@echo "$(BLUE)Destroying resources...$(NC)"
	cd terraform && terraform destroy -auto-approve

clean: ## Clean up temporary files
	@echo "$(BLUE)Cleaning up temporary files...$(NC)"
	rm -f $(INSTANCE_NAME)-connection-info.txt
	rm -f $(INSTANCE_NAME)-stop-info.txt
	rm -f terraform/terraform.tfvars
	@echo "$(GREEN)Cleanup complete!$(NC)"

# =============================================================================
# Cost Management
# =============================================================================

cost: ## Show cost estimates
	@echo ""
	@echo "Kimi K2.5 Cost Estimates (4x H100 80GB)"
	@echo "======================================="
	@echo ""
	@echo "On-Demand Pricing:"
	@echo "  Hourly:  ~\$16.00/hour"
	@echo "  Daily:   ~\$384/day"
	@echo "  Monthly: ~\$11,700/month (24/7)"
	@echo ""
	@echo "Spot Pricing (~70% off):"
	@echo "  Hourly:  ~\$4.80/hour"
	@echo "  Daily:   ~\$115/day"
	@echo "  Monthly: ~\$3,500/month (24/7)"
	@echo ""
	@echo "Storage (always charged):"
	@echo "  Boot disk (200GB): ~\$17/month"
	@echo "  Model disk (1TB):  ~\$80/month"
	@echo "  Total storage:     ~\$97/month"
	@echo ""

# =============================================================================
# Development
# =============================================================================

fmt: ## Format Terraform code
	@echo "$(BLUE)Formatting Terraform code...$(NC)"
	cd terraform && terraform fmt -recursive

lint: ## Lint shell scripts
	@echo "$(BLUE)Linting shell scripts...$(NC)"
	shellcheck scripts/*.sh || echo "$(YELLOW)shellcheck not installed$(NC)"

# =============================================================================
# All-in-One Commands
# =============================================================================

all: deploy start status ## Full deployment: deploy infrastructure, start instance, show status

quickstart: ## Quick start for existing deployment
	@echo "$(BLUE)Quick starting Kimi K2.5...$(NC)"
	$(MAKE) start
	$(MAKE) status
