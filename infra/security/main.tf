terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "cloudmart-tf-state-1aaa66cd"
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "databases" {
  backend = "s3"
  config = {
    bucket = "cloudmart-tf-state-1aaa66cd"
    key    = "databases/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "sqs" {
  backend = "s3"
  config = {
    bucket = "cloudmart-tf-state-1aaa66cd"
    key    = "messaging/terraform.tfstate"
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
