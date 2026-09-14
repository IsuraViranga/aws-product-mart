# ---------------------------------------------------------------------------
# The CloudMart VPC.
#
# A thin root module: it configures the backend and provider, then calls the
# reusable networking module. Kept in its own state file so that a mistake here
# cannot touch the DynamoDB table or SQS queues in infra/core.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "cloudmart-tfstate-468683594325"
    key          = "network/terraform.tfstate"
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

variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "enable_nat_gateway" {
  description = "Switch the ~$43/month NAT gateway on for an EKS session, off afterwards"
  type        = bool
  default     = false
}

module "networking" {
  source = "../modules/networking"

  name               = "cloudmart"
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b"]

  # Off by default. Enable with:  terraform apply -var enable_nat_gateway=true
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = true
}
