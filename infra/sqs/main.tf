terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  tags = {
    Project     = var.project
    Environment = var.environment
    Team        = var.team
    Owner       = var.owner
  }
}

resource "aws_sqs_queue" "orders" {
  name                       = "cloudmart-orders"
  message_retention_seconds  = 345600   # 4 days
  visibility_timeout_seconds = 30
  sqs_managed_sse_enabled    = true     # encryption at rest

  tags = local.tags
}