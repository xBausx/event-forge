# Declares the output values from the Terraform module.
# These values are printed after a successful `terraform apply` and can be
# queried using the `terraform output` command.

output "lambda_exec_role_arn" {
  value       = aws_iam_role.lambda_exec_role.arn
  description = "The ARN of the IAM role used by the Lambda functions."
}

output "read_sheet_lambda_arn" {
  value       = aws_lambda_function.read_sheet.arn
  description = "The ARN of the 'read_sheet' Lambda function."
}

output "generate_poster_lambda_arn" {
  value       = aws_lambda_function.generate_poster.arn
  description = "The ARN of the 'generate_poster' Lambda function."
}

output "send_report_lambda_arn" {
  value       = aws_lambda_function.send_report.arn
  description = "The ARN of the 'send_report' Lambda function."
}

output "assets_s3_bucket_name" {
  value       = aws_s3_bucket.assets.id
  description = "The name of the S3 bucket for storing assets (templates, fonts)."
}

output "outputs_s3_bucket_name" {
  value       = aws_s3_bucket.outputs.id
  description = "The name of the S3 bucket for storing generated posters."
}

output "sheet_watch_registry_table_name" {
  value       = aws_dynamodb_table.sheet_watch_registry.name
  description = "The name of the DynamoDB table for storing watched sheet information."
}

output "terraform_state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.id
  description = "The name of the S3 bucket created to hold the remote Terraform state."
}

output "terraform_lock_table_name" {
  value       = aws_dynamodb_table.terraform_lock.name
  description = "The name of the DynamoDB table created for Terraform state locking."
}

output "orchestration_function_url" {
  value = aws_lambda_function_url.orchestration_endpoint_url.function_url
}

output "orchestration_function_name" {
  value = aws_lambda_function.orchestration_endpoint.function_name
}

output "read_sheet_function_name" {
  value = aws_lambda_function.read_sheet.function_name
}

output "generate_poster_function_name" {
  value = aws_lambda_function.generate_poster.function_name
}
output "send_report_function_name" {
  value = aws_lambda_function.send_report.function_name
}