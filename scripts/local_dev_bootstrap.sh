#!/bin/bash

# ==============================================================================
# local_dev_bootstrap.sh
# ==============================================================================
#
# Purpose:
#   This script sets up a local development environment for the Event-Forge
#   project. It checks for required tools and installs all dependencies for
#   Python, Node.js, and our pre-commit git hooks.
#
# Usage:
#   Run this script from the root of the project repository:
#   ./scripts/local_dev_bootstrap.sh
#
# ==============================================================================

set -e # Exit immediately if a command exits with a non-zero status.

# --- Helper Functions for colored output ---
function print_header() {
    echo ""
    echo -e "\033[1;34m=== $1 ===\033[0m" # Bold Blue
}
function print_success() {
    echo -e "\033[0;32m✔ $1\033[0m" # Green
}
function print_error() {
    echo -e "\033[0;31m✖ $1\033[0m" # Red
}
function print_info() {
    echo -e "\033[0;33m  $1\033[0m" # Yellow
}

# --- Check for required command-line tools ---
print_header "Checking for required tools"
command -v git >/dev/null 2>&1 || { print_error "Git is not installed. Please install Git and re-run."; exit 1; }
print_success "Git is installed."

command -v python3 >/dev/null 2>&1 || { print_error "Python 3 is not installed. Please install Python 3.12+ and re-run."; exit 1; }
print_success "Python 3 is installed."

command -v pip3 >/dev/null 2>&1 || { print_error "pip3 is not installed. Please install pip3 and re-run."; exit 1; }
print_success "pip3 is installed."

command -v node >/dev/null 2>&1 || { print_error "Node.js is not installed. Please install Node.js (LTS 20.x) and re-run."; exit 1; }
print_success "Node.js is installed."

command -v npm >/dev/null 2>&1 || { print_error "npm is not installed. Please install npm and re-run."; exit 1; }
print_success "npm is installed."

command -v terraform >/dev/null 2>&1 || { print_error "Terraform is not installed. Please install Terraform (>= 1.6) and re-run."; exit 1; }
print_success "Terraform is installed."

command -v make >/dev/null 2>&1 || { print_error "make is not installed. Please install make (e.g., via build-essential or Xcode Command Line Tools)."; exit 1; }
print_success "make is installed."

# --- Install Dependencies using Makefile ---
print_header "Installing project dependencies via Makefile"
print_info "This will install Python requirements, Node modules, and pre-commit hooks."

# The `install` target in our Makefile does all the heavy lifting.
make install

print_header "Bootstrap Complete!"
print_success "Your local development environment is ready."
print_info "Next steps:"
print_info "1. Copy '.env.example' to '.env' and fill in your local secrets."
print_info "2. Run 'make lint' to verify all linters are working."
print_info "3. To deploy infrastructure, run 'make tf-plan env=dev' and 'make tf-apply env=dev'."