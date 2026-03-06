terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }

  # Remote state in S3 — shared between local dev and CI/CD
  backend "s3" {
    bucket = "com.sharmaabhineet"
    key    = "terraform/terraform.tfstate"
    region = "us-east-1"
  }
}

# Configure the AWS Provider
# Profile is set via AWS_PROFILE env var locally; OIDC credentials are used in CI/CD
provider "aws" {
  region = var.region
}
