terraform {
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }

  }
}

provider "aws" {
  region = var.aws_region
}

data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "cloudmart-tf-state-1aaa66cd"
    key    = "networking/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  tags = {
    Project     = var.project
    Environment = var.environment
    Team        = var.team
    Owner       = var.owner
  }
}
