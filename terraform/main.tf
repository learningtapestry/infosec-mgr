# DefectDojo AWS Infrastructure
# Terraform configuration for deploying DefectDojo to AWS

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state in S3 (uncomment after first apply creates the bucket)
  # backend "s3" {
  #   bucket         = "infosec-mgr-terraform-state"
  #   key            = "defectdojo/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "infosec-mgr-terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "infosec-mgr"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
