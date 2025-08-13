.PHONY: help install lint format tf-plan tf-apply clean

# Use bash on Linux runners for better scripting
SHELL := /usr/bin/env bash

YELLOW := "\033[1;33m"
RESET  := "\033[0m"

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "------------------------------------------------------------------"
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf $(YELLOW)"%-20s"$(RESET)" %s\n", $$1, $$2}'
	@echo "------------------------------------------------------------------"

# ==============================================================================
# DEVELOPMENT & SETUP
# ==============================================================================

install: ## Install project deps (pre-commit hooks, Node, Python).
	@echo "--> Installing pre-commit hooks..."
	@pip3 install pre-commit
	@pre-commit install
	@printf "\n--> Installing Node.js deps for orchestration...\n"
	@cd src/orchestration && npm install
	@printf "\n--> Installing Python deps for all Lambda functions...\n"
	@for dir in src/lambdas/*/; do \
		if [ -f "$${dir}requirements.txt" ]; then \
			echo "Installing requirements for $${dir}..."; \
			pip3 install -r "$${dir}requirements.txt"; \
		fi; \
	done
	@printf "\nInstallation complete.\n"

# Detect Windows to skip Terraform hooks locally (they need /bin/bash)
ifeq ($(OS),Windows_NT)
	SKIP_LOCAL := terraform_fmt,terraform_validate,terraform_tflint
else
	SKIP_LOCAL :=
endif

lint: ## Run all linters via pre-commit (skips Terraform on Windows).
	@echo "--> Running all linters..."
	@SKIP=$(SKIP_LOCAL) pre-commit run --all-files

format: ## Run formatters only (Terraform fmt, Prettier, isort, Black).
	@echo "--> Formatting all code..."
	@SKIP=$(SKIP_LOCAL) pre-commit run --all-files --hook-stage manual terraform_fmt
	@pre-commit run --all-files --hook-stage manual prettier
	@pre-commit run --all-files --hook-stage manual isort
	@pre-commit run --all-files --hook-stage manual black

clean: ## Remove temporary files and build artifacts.
	@echo "--> Cleaning project..."
	@find . -type f -name '*.pyc' -delete || true
	@find . -type d -name '__pycache__' -exec rm -rf {} + || true
	@rm -rf .terraform* || true
	@rm -rf .coverage .pytest_cache || true
	@echo "Clean complete."

# ==============================================================================
# INFRASTRUCTURE (TERRAFORM)
# ==============================================================================

# Require env=dev|staging|prod
ifeq ($(env),)
    TF_CHECK = @echo "ERROR: 'env' is not set. Usage: make $(MAKECMDGOALS) env=<dev|staging|prod>" && exit 1
else
    TF_CHECK = @true
endif

tf-plan: ## Generate a Terraform plan (e.g., `make tf-plan env=dev`).
	$(TF_CHECK)
	@echo "--> Initializing Terraform for $(env)..."
	@cd infra/terraform && terraform init -reconfigure
	@printf "\n--> Planning for $(env)...\n"
	@cd infra/terraform && terraform plan -input=false -var-file="env/$(env).tfvars"

tf-apply: ## Apply Terraform for an env (e.g., `make tf-apply env=dev`).
	$(TF_CHECK)
	@echo "--> Initializing Terraform for $(env)..."
	@cd infra/terraform && terraform init -reconfigure
	@printf "\n--> Applying for $(env)...\n"
	@cd infra/terraform && terraform apply -input=false -auto-approve -var-file="env/$(env).tfvars"
