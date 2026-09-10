# ---------------------------------------------------------------------------
# Core data services for CloudMart: the product catalogue table and the order
# event queue.
#
# These resources were originally created by hand in the console. They are
# brought under Terraform management with `import` blocks (see imports.tf)
# rather than being destroyed and recreated, so no data is lost.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "cloudmart-tfstate-468683594325"
    key          = "core/terraform.tfstate" # a different key from bootstrap
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cloudmart"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "isura"
    }
  }
}

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "Region everything is built in"
  type        = string
  default     = "ap-southeast-1"
}

variable "environment" {
  description = "Environment name, used in tags and resource names"
  type        = string
  default     = "dev"
}

# Looks up the account Terraform is currently authenticated to, so the account
# ID never has to be written down. Works in any account without editing code.
data "aws_caller_identity" "current" {}
