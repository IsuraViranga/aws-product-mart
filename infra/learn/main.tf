# ---------------------------------------------------------------------------
# A throwaway project to learn the Terraform workflow.
# Creates one S3 bucket, then you destroy it. Nothing here is kept.
# ---------------------------------------------------------------------------

# The `terraform` block configures Terraform itself: which version of the CLI
# is acceptable, and which providers (cloud plugins) this project needs.
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws" # where to download the plugin from
      version = "~> 6.0"        # allow 6.x, but not 7.0 - a breaking change
    }
  }
}

# The `provider` block configures a plugin. Note there are NO credentials here:
# the AWS provider finds them exactly the way boto3 did - environment variables,
# then ~/.aws/credentials, then an instance role. Same chain, same rule:
# credentials are never written in code.
provider "aws" {
  region = "ap-southeast-1"

  # Tags applied to every taggable resource this provider creates, so you never
  # have to remember to tag things individually. This is what makes cost
  # allocation by project possible later.
  default_tags {
    tags = {
      Project     = "cloudmart"
      Environment = "learning"
      ManagedBy   = "terraform"
      Owner       = "isura"
    }
  }
}

# A `resource` block declares one thing that should exist.
#
#   aws_s3_bucket   <- the resource TYPE (defined by the aws provider)
#   hello           <- the LOCAL NAME, used to refer to it elsewhere in the code.
#                      It is not the bucket's real name and never appears in AWS.
resource "aws_s3_bucket" "hello" {
  bucket = "cloudmart-tf-hello-isura-468683594325"
}

# Modern AWS buckets configure versioning as a separate resource rather than a
# field. Note how it refers to the bucket above by its local name - Terraform
# reads that reference and works out that the bucket must be created first.
resource "aws_s3_bucket_versioning" "hello" {
  bucket = aws_s3_bucket.hello.id

  versioning_configuration {
    status = "Enabled"
  }
}

# `output` values are printed after an apply and can be read by other projects.
# Use them for things you need to look up afterwards.
output "bucket_name" {
  description = "Name of the bucket that was created"
  value       = aws_s3_bucket.hello.bucket
}

output "bucket_arn" {
  description = "ARN of the bucket - the same ARN format you wrote in IAM policies"
  value       = aws_s3_bucket.hello.arn
}
