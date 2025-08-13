# Configures the providers that Terraform will use to create infrastructure.

provider "aws" {
  region = var.aws_region
}

# ==============================================================================
# Terraform Backend Configuration (Temporarily Disabled)
# ==============================================================================
#
# We will start with a local backend (the default). This means Terraform will
# create a `terraform.tfstate` file in this directory.
#
# Once our main configuration creates the S3 bucket and DynamoDB table for
# remote state, we will uncomment this block. Terraform will then offer to

# automatically migrate the local state file to the new S3 backend. This
# avoids any manual setup steps.

# terraform {
#   backend "s3" {
#     bucket         = "event-forge-terraform-state-${var.env}" # We will create this bucket
#     key            = "terraform.tfstate"
#     region         = var.aws_region
#     dynamodb_table = "event-forge-terraform-lock" # We will create this table
#     encrypt        = true
#   }
# }