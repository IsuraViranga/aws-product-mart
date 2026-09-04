terraform {
  backend "s3" {
    bucket         = "cloudmart-tf-state-1aaa66cd"
    key            = "ecr/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cloudmart-tf-lock"
    encrypt        = true
    use_lockfile   = true
  }
}