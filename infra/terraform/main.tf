# Main Terraform configuration for the Event-Forge project.
# This file defines all the AWS resources required for the application to run.

# ==============================================================================
# LOCAL VALUES & NAMING CONVENTIONS
# ==============================================================================

# Use a random suffix for globally unique resources like S3 buckets to avoid naming conflicts.
resource "random_pet" "suffix" {
    length = 2
}

# The locals block is used to define reusable values and create consistent naming conventions.
locals {
    # Add the environment name (dev, staging, prod) to all tags.
    tags = merge(var.tags, {
        Environment = var.env
    })
    # Create a consistent prefix for all resources created by this configuration.
    resource_prefix = "event-forge-${var.env}"
    # Generate a unique name for the S3 buckets.
    s3_bucket_suffix = random_pet.suffix.id
}

# ==============================================================================
# TERRAFORM STATE RESOURCES (The "Chicken-and-Egg" Solution)
# ==============================================================================
# These resources create the S3 bucket and DynamoDB table needed for the remote
# backend. After the first `terraform apply`, you can uncomment the `backend "s3"`
# block in `providers.tf` and run `terraform init` again to migrate the state.

resource "aws_s3_bucket" "terraform_state" {
    bucket = "event-forge-terraform-state-${var.env}-${local.s3_bucket_suffix}"

    # Prevent accidental deletion of the state bucket.
    lifecycle {
        prevent_destroy = true
    }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
    bucket = aws_s3_bucket.terraform_state.id
    versioning_configuration {
        status = "Enabled"
    }
}

resource "aws_dynamodb_table" "terraform_lock" {
    name           = "event-forge-terraform-lock-${var.env}"
    billing_mode   = "PAY_PER_REQUEST"
    hash_key       = "LockID"

    attribute {
        name = "LockID"
        type = "S"
    }
}


# ==============================================================================
# APPLICATION STORAGE (S3 & DYNAMODB)
# ==============================================================================

resource "aws_s3_bucket" "assets" {
    bucket = "${local.resource_prefix}-assets-${local.s3_bucket_suffix}"
    tags   = local.tags
}

resource "aws_s3_bucket" "outputs" {
    bucket = "${local.resource_prefix}-outputs-${local.s3_bucket_suffix}"
    tags   = local.tags
}

resource "aws_s3_bucket_versioning" "assets" {
    bucket = aws_s3_bucket.assets.id
    versioning_configuration {
        status = "Enabled"
    }
}

resource "aws_s3_bucket_versioning" "outputs" {
    bucket = aws_s3_bucket.outputs.id
    versioning_configuration {
        status = "Enabled"
    }
}

resource "aws_dynamodb_table" "sheet_watch_registry" {
    name           = "SheetWatchRegistry-${var.env}"
    billing_mode   = "PAY_PER_REQUEST"
    hash_key       = "sheet_id"
    tags           = local.tags

    attribute {
        name = "sheet_id"
        type = "S"
    }
}

# ==============================================================================
# SECRETS (Placeholders)
# ==============================================================================
# These resources create placeholders in AWS Secrets Manager. The actual secret
# values (like API keys) must be set manually in the AWS Console for security.

resource "aws_secretsmanager_secret" "adobe_api_key" {
    name = "event-forge/adobe-api-key-${var.env}"
    description = "Adobe API credentials (client_id, client_secret) for the Event-Forge project."
    tags = local.tags
}

resource "aws_secretsmanager_secret" "google_wif_config" {
    name = "event-forge/google-wif-config-${var.env}"
    description = "Google Cloud Service Account email for Workload Identity Federation."
    tags = local.tags
}

resource "aws_secretsmanager_secret" "slack_webhook_url" {
    name = "event-forge/slack-webhook-url-${var.env}"
    description = "Slack webhook URL for sending reports."
    tags = local.tags
}


# ==============================================================================
# IAM ROLE & POLICY FOR LAMBDA FUNCTIONS
# ==============================================================================
# A single execution role is created and shared by all Lambda functions in this
# project. It follows the principle of least privilege.

data "aws_iam_policy_document" "lambda_assume_role" {
    statement {
        actions = ["sts:AssumeRole"]
        principals {
        type        = "Service"
        identifiers = ["lambda.amazonaws.com"]
        }
    }
}

resource "aws_iam_role" "lambda_exec_role" {
    name               = "${local.resource_prefix}-lambda-exec-role"
    assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
    tags               = local.tags
}

data "aws_iam_policy_document" "lambda_exec_policy" {
    # Allow writing logs to CloudWatch
    statement {
        actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        resources = ["arn:aws:logs:*:*:*"]
    }

    # Allow access to the application S3 buckets
    statement {
        actions = [
        "s3:GetObject",
        "s3:PutObject"
        ]
        resources = [
        "${aws_s3_bucket.assets.arn}/*",
        "${aws_s3_bucket.outputs.arn}/*"
        ]
    }

    # Allow access to the DynamoDB table
    statement {
        actions   = ["dynamodb:Query", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        resources = [aws_dynamodb_table.sheet_watch_registry.arn]
    }

    # Allow reading secrets from Secrets Manager
    statement {
        actions   = ["secretsmanager:GetSecretValue"]
        resources = [
        aws_secretsmanager_secret.adobe_api_key.arn,
        aws_secretsmanager_secret.google_wif_config.arn,
        aws_secretsmanager_secret.slack_webhook_url.arn
        ]
    }
}

resource "aws_iam_role_policy" "lambda_exec_policy" {
    name   = "${local.resource_prefix}-lambda-exec-policy"
    role   = aws_iam_role.lambda_exec_role.id
    policy = data.aws_iam_policy_document.lambda_exec_policy.json
}


# ==============================================================================
# LAMBDA FUNCTIONS
# ==============================================================================
# For each Lambda, we use the `archive_file` data source to create a .zip file
# of its source code directory, which is then used by the `aws_lambda_function` resource.

# --- read_sheet Lambda ---
data "archive_file" "read_sheet" {
    type        = "zip"
    source_dir  = "${path.module}/../../src/lambdas/read_sheet"
    output_path = "${path.module}/../../.terraform/archives/read_sheet.zip"
}

resource "aws_lambda_function" "read_sheet" {
    function_name    = "${local.resource_prefix}-read-sheet"
    role             = aws_iam_role.lambda_exec_role.arn
    handler          = "handler.handler"
    runtime          = "python3.12"
    filename         = data.archive_file.read_sheet.output_path
    source_code_hash = data.archive_file.read_sheet.output_base64sha256
    timeout          = 15
    tags             = local.tags

    environment {
        variables = {
        APP_ENV                 = var.env
        POWERTOOLS_SERVICE_NAME = "event-forge-${var.env}"
        }
    }
}

# --- generate_poster Lambda ---
data "archive_file" "generate_poster" {
    type        = "zip"
    source_dir  = "${path.module}/../../src/lambdas/generate_poster"
    output_path = "${path.module}/../../.terraform/archives/generate_poster.zip"
}

resource "aws_lambda_function" "generate_poster" {
    function_name    = "${local.resource_prefix}-generate-poster"
    role             = aws_iam_role.lambda_exec_role.arn
    handler          = "handler.handler"
    runtime          = "python3.12"
    filename         = data.archive_file.generate_poster.output_path
    source_code_hash = data.archive_file.generate_poster.output_base64sha256
    timeout          = 15
    tags             = local.tags

    environment {
        variables = {
        APP_ENV                 = var.env
        POWERTOOLS_SERVICE_NAME = "event-forge-${var.env}"
        }
    }
}

# --- send_report Lambda ---
data "archive_file" "send_report" {
    type        = "zip"
    source_dir  = "${path.module}/../../src/lambdas/send_report"
    output_path = "${path.module}/../../.terraform/archives/send_report.zip"
    }

resource "aws_lambda_function" "send_report" {
    function_name    = "${local.resource_prefix}-send-report"
    role             = aws_iam_role.lambda_exec_role.arn
    handler          = "handler.handler"
    runtime          = "python3.12"
    filename         = data.archive_file.send_report.output_path
    source_code_hash = data.archive_file.send_report.output_base64sha256
    timeout          = 15
    tags             = local.tags

    environment {
        variables = {
        APP_ENV                 = var.env
        POWERTOOLS_SERVICE_NAME = "event-forge-${var.env}"
        }
    }
}