# Terraform variable values for the 'dev' environment.
# This file is passed to Terraform using the -var-file flag, e.g.:
# terraform plan -var-file="env/dev.tfvars"

env = "dev"

aws_region = "us-east-1"

tags = {
  Project     = "event-forge"
  Environment = "dev"
  Owner       = "Rico"
}

# The following values are used for the S3 backend configuration.
# They need to be defined here so `terraform init -backend-config` can find them.
# After the first apply, Terraform will use the bucket and table it created.
bucket         = "event-forge-terraform-state-dev" # This is a target name; the actual name will have a random suffix.
dynamodb_table = "event-forge-terraform-lock-dev"  # This is the target name.