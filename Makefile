.PHONY: help install lint format tf-plan tf-apply clean

# Use this to colorize output
YELLOW := "\033[1;33m"
RESET := "\033[0m"

# Default target
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "------------------------------------------------------------------"
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(YELLOW)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo "------------------------------------------------------------------"

# ==============================================================================
# DEVELOPMENT & SETUP
# ==============================================================================

install: ## Install all project dependencies (Python Lambdas, Node Orchestration, and pre-commit hooks).
	@echo "--> Installing pre-commit hooks..."
	@pip3 install pre-commit
	@pre-commit install
	@echo "\n--> Installing Node.js dependencies for orchestration..."
	@cd src/orchestration && npm install
	@echo "\n--> Installing Python dependencies for all Lambda functions..."
	@for dir in src/lambdas/*/; do \
		if [ -f "$${dir}requirements.txt" ]; then \
			echo "Installing requirements for $${dir}..."; \
			pip3 install -r "$${dir}requirements.txt"; \
		fi; \
	done
	@echo "\nInstallation complete."

lint: ## Run all linters (Terraform, Python, TS) using pre-commit configuration.
	@echo "--> Running all linters..."
	@pre-commit run --all-files

format: ## Format all code (Terraform, Python, TS) using pre-commit configuration.
	@echo "--> Formatting all code..."
	@pre-commit run --all-files --hook-stage manual fmt
	@pre-commit run --all-files --hook-stage manual prettier

clean: ## Remove temporary files and build artifacts.
	@echo "--> Cleaning project..."
	@find . -type f -name '*.pyc' -delete
	@find . -type d -name '__pycache__' -exec rm -rf {} +
	@rm -rf .terraform*
	@rm -rf .coverage .pytest_cache
	@echo "Clean complete."

# ==============================================================================
# INFRASTRUCTURE (TERRAFORM)
# ==============================================================================

# Check if 'env' is passed, e.g., `make tf-plan env=dev`
ifeq ($(env),)
    TF_CHECK = @echo "ERROR: 'env' is not set. Usage: make $(MAKECMDGOALS) env=<dev|staging|prod>" && exit 1
else
    TF_CHECK = @true
endif

tf-plan: ## Generate a Terraform plan for a specific environment (e.g., `make tf-plan env=dev`).
	$(TF_CHECK)
	@echo "--> Initializing Terraform for the $(env) environment..."
	@cd infra/terraform && terraform init -reconfigure -backend-config="env/$(env).tfvars"
	@echo "\n--> Generating Terraform plan for $(env)..."
	@cd infra/terraform && terraform plan -var-file="env/$(env).tfvars"

tf-apply: ## Apply a Terraform plan for a specific environment (e.g., `make tf-apply env=dev`).
	$(TF_CHECK)
	@echo "--> Initializing Terraform for the $(env) environment..."
	@cd infra/terraform && terraform init -reconfigure -backend-config="env/$(env).tfvars"
	@echo "\n--> Applying Terraform plan for $(env)..."
	@cd infra/terraform && terraform apply -var-file="env/$(env).tfvars" -auto-approve
