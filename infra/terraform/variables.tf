# Declares all input variables for the Terraform configuration.
# Default values can be provided here, but they are typically overridden
# by values in `.tfvars` files or command-line arguments.

variable "env" {
  type        = string
  description = "The deployment environment (e.g., 'dev', 'staging', 'prod'). This is used to name and tag resources."
  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "The environment must be one of 'dev', 'staging', or 'prod'."
  }
}

variable "aws_region" {
  type        = string
  description = "The AWS region where resources will be deployed."
  default     = "us-east-1"
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to apply to all taggable resources."
  default = {
    Project     = "Event-Forge"
    ManagedBy   = "Terraform"
  }
}
