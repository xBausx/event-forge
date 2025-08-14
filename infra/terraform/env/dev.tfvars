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