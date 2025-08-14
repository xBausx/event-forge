# ======================================================================
# Event-Forge: main.tf  (corrected)
# - Adds missing Lambda trust policy
# - Merges/cleans duplicate exec policy blocks
# - Avoids IAM ↔ Lambda dependency cycle (wildcard ARN with account_id)
# - Packages orchestration Lambda with node_modules (deploys dist/)
# - Function URL uses NONE; verify via INNGEST_SIGNING_KEY
# - S3 hardening & versioning for both buckets
# ======================================================================

# Unique suffix for globally-unique names (e.g., S3 buckets)
resource "random_pet" "suffix" {
  length = 2
}

# Current AWS account (for wildcard ARNs without creating a cycle)
# data "aws_caller_identity" "current" {}

# -----------------------------
# Locals (naming, tags, limits)
# -----------------------------
locals {
  tags = merge(var.tags, { Environment = var.env })

  # Prefix applied to most resources
  resource_prefix = "event-forge-${var.env}"

  # Unique bucket suffix
  s3_bucket_suffix = random_pet.suffix.id

  # Concurrency per env for Adobe jobs (stringified for env var)
  adobe_concurrency_limits = {
    dev     = 5
    staging = 50
    prod    = 200
  }
}

# ======================================================================
# Terraform Backend Bootstrap (state bucket & lock table)
# After first apply, configure backend in providers.tf and re-init.
# ======================================================================
resource "aws_s3_bucket" "terraform_state" {
  bucket = "event-forge-terraform-state-${var.env}-${local.s3_bucket_suffix}"

  lifecycle {
    prevent_destroy = true
  }

  tags = local.tags
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration { status = "Enabled" }
}

# Lock table (state backend)
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "event-forge-terraform-lock-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = local.tags
}

# ======================================================================
# Application Storage (S3) & Registry (DynamoDB)
# ======================================================================
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
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_versioning" "outputs" {
  bucket = aws_s3_bucket.outputs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "outputs" {
  bucket                  = aws_s3_bucket.outputs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "outputs" {
  bucket = aws_s3_bucket.outputs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# App registry table
resource "aws_dynamodb_table" "sheet_watch_registry" {
  name         = "SheetWatchRegistry-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sheet_id"

  attribute {
    name = "sheet_id"
    type = "S" # <— REQUIRED
  }

  tags = local.tags
}

# ======================================================================
# Secrets (placeholders). Put real values before apply where needed.
# ======================================================================
resource "aws_secretsmanager_secret" "adobe_api_key" {
  name        = "event-forge/adobe-api-key-${var.env}"
  description = "Adobe API credentials (client_id, client_secret)."
  tags        = local.tags
}

resource "aws_secretsmanager_secret" "google_wif_config" {
  name        = "event-forge/google-wif-config-${var.env}"
  description = "Google SA email for Workload Identity Federation."
  tags        = local.tags
}

resource "aws_secretsmanager_secret" "slack_webhook_url" {
  name        = "event-forge/slack-webhook-url-${var.env}"
  description = "Slack webhook URL for sending reports."
  tags        = local.tags
}

# ======================================================================
# IAM POLICY DOCUMENT FOR LAMBDA EXECUTION ROLE
# (no reference to the Inngest signing key secret)
# ======================================================================
data "aws_iam_policy_document" "lambda_exec_policy" {
  # CloudWatch Logs
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # S3 assets & outputs
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = [
      format("%s/*", aws_s3_bucket.assets.arn),
      format("%s/*", aws_s3_bucket.outputs.arn)
    ]
  }

  # DynamoDB registry
  statement {
    actions   = ["dynamodb:Query", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.sheet_watch_registry.arn]
  }

  # Secrets Manager (keep only the ones we still use)
  statement {
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      aws_secretsmanager_secret.adobe_api_key.arn,
      aws_secretsmanager_secret.google_wif_config.arn,
      aws_secretsmanager_secret.slack_webhook_url.arn
      # NOTE: no reference to an Inngest secret anymore
    ]
  }

  # Allow orchestration Lambda to invoke the worker Lambdas
  statement {
    actions = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.read_sheet.arn,
      aws_lambda_function.generate_poster.arn,
      aws_lambda_function.send_report.arn
    ]
  }
}


# ======================================================================
# IAM TRUST POLICY FOR LAMBDA EXECUTION ROLE
# ======================================================================
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    sid     = "LambdaAssumeRole"
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

resource "aws_iam_role_policy" "lambda_exec_policy" {
  name   = "${local.resource_prefix}-lambda-exec-policy"
  role   = aws_iam_role.lambda_exec_role.id
  policy = data.aws_iam_policy_document.lambda_exec_policy.json
}

# ======================================================================
# Lambda Functions (Python)
# - CI step installs deps into each folder and copies src/common before apply.
# ======================================================================

# read_sheet
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

# generate_poster
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

# send_report
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

# ======================================================================
# Orchestration Lambda (Node.js) + Function URL
# - CI builds TypeScript -> dist/, and keeps node_modules/ present
# ======================================================================

# Zip the entire orchestration package so node_modules are included.
# Exclude TS sources; deploy compiled JS from dist/.
data "archive_file" "orchestration" {
  type        = "zip"
  source_dir  = "${path.module}/../../src/orchestration"
  output_path = "${path.module}/../../.terraform/archives/orchestration.zip"

  excludes = [
    "src/**",
    "tsconfig.json",
    ".npmrc",
    "package-lock.json"
  ]
}

resource "aws_lambda_function" "orchestration_endpoint" {
  function_name    = "${local.resource_prefix}-orchestration-endpoint"
  role             = aws_iam_role.lambda_exec_role.arn
  runtime          = "nodejs20.x"
  handler          = "dist/handler.handler" # compiled handler.js export
  filename         = data.archive_file.orchestration.output_path
  source_code_hash = data.archive_file.orchestration.output_base64sha256
  timeout          = 30
  tags             = local.tags

  environment {
    variables = {
      APP_ENV                 = var.env
      ADOBE_CONCURRENCY_LIMIT = lookup(local.adobe_concurrency_limits, var.env)
      AWS_REGION              = var.aws_region
      INNGEST_SIGNING_KEY     = "set-by-ci"
    }
  }
}

resource "aws_lambda_function_url" "orchestration_endpoint_url" {
  function_name      = aws_lambda_function.orchestration_endpoint.function_name
  authorization_type = "NONE" # Inngest signs the request; handler verifies with INNGEST_SIGNING_KEY

  cors {
    allow_origins     = ["*"]
    allow_methods     = ["POST"]
    allow_headers     = ["*"]
    allow_credentials = false
  }
}
