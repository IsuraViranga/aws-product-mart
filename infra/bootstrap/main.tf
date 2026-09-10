# ---------------------------------------------------------------------------
# Bootstrap: the S3 bucket that stores Terraform state for every other project.
#
# This is the chicken-and-egg project. It is applied ONCE with local state,
# then migrates its own state into the bucket it just created. After that,
# every other Terraform project in this repo uses this bucket as its backend.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "cloudmart-tfstate-468683594325"
    key          = "bootstrap/terraform.tfstate"
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

  # NOTE: the `backend` block above was added AFTER the first apply, then the
  # state was moved into the bucket with `terraform init -migrate-state`.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cloudmart"
      Environment = "shared"
      ManagedBy   = "terraform"
      Owner       = "isura"
    }
  }
}

variable "aws_region" {
  description = "Region everything is built in"
  type        = string
  default     = "ap-southeast-1"
}

variable "state_bucket_name" {
  description = "Globally unique name for the Terraform state bucket"
  type        = string
  default     = "cloudmart-tfstate-468683594325"
}

# ---------------------------------------------------------------------------
# The state bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  # Refuse to delete this bucket even if someone runs `terraform destroy`.
  # Losing the state bucket means every other project forgets what it owns.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning is not optional here. If a state file is corrupted or truncated
# mid-write, the previous version is the only way back.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# State files contain secrets in plaintext - generated database passwords,
# private keys. Encrypt at rest. SSE-S3 is free; a KMS key would cost $1/month.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Belt and braces. Public access is already blocked by default on new buckets,
# but stating it explicitly means nobody can quietly turn it off without the
# change showing up in a plan.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Old state versions pile up forever otherwise. Keep 90 days of history, which
# is far more than you will ever need to roll back.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "state_bucket" {
  description = "Bucket name to use in every other project's backend block"
  value       = aws_s3_bucket.tfstate.bucket
}

output "region" {
  value = var.aws_region
}
