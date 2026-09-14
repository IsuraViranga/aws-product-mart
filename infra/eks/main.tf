# ---------------------------------------------------------------------------
# The CloudMart EKS cluster.
#
# This is the expensive root. Everything in it is designed to be created for a
# practice session and destroyed afterwards:
#
#     terraform -chdir=../network apply -var enable_nat_gateway=true
#     terraform apply
#     ... learn things ...
#     terraform destroy
#     terraform -chdir=../network apply -var enable_nat_gateway=false
#
# Roughly $0.22/hour while it is up, near zero when it is not. The daily budget
# in infra/budget exists to catch the session you forget to end.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "cloudmart-tfstate-468683594325"
    key          = "eks/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
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
# Helm, pointed at the cluster this same root creates.
#
# Note the `exec` block: no token is stored anywhere. Terraform shells out to
# `aws eks get-token` for a fresh short-lived credential on every operation,
# the same mechanism kubectl uses. That is why this works with no kubeconfig
# and no secret in state.
#
# The chicken-and-egg here is real - the provider is configured from outputs of
# a resource in the same root. Terraform handles it because provider
# configuration is resolved lazily, but it does mean the cluster must exist
# before anything using this provider can be planned in detail.
# ---------------------------------------------------------------------------
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "cluster_name" {
  type    = string
  default = "cloudmart"
}

variable "kubernetes_version" {
  description = "Pin this after the first apply. Null lets AWS pick the current default."
  type        = string
  default     = null
}

# Narrow this to your own address for a real improvement in exposure:
#   terraform apply -var 'public_access_cidrs=["203.0.113.4/32"]'
variable "public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "node_capacity_type" {
  description = "SPOT for practice, ON_DEMAND for a demo you cannot have interrupted"
  type        = string
  default     = "SPOT"
}

# ---------------------------------------------------------------------------
# The VPC, read from the network root's state
#
# Read rather than duplicated: the subnet IDs exist in exactly one place, and
# rebuilding the VPC does not mean hand-editing this file.
# ---------------------------------------------------------------------------

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "cloudmart-tfstate-468683594325"
    key    = "network/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

module "eks" {
  source = "../modules/eks"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_app_subnet_ids
  public_subnet_ids  = data.terraform_remote_state.network.outputs.public_subnet_ids

  # Feeds the precondition that stops you creating a node group that can never
  # reach ECR.
  nat_gateway_enabled = data.terraform_remote_state.network.outputs.nat_gateway_enabled

  public_access_cidrs = var.public_access_cidrs
  node_capacity_type  = var.node_capacity_type

  # The GitHub Actions role needs cluster admin to run kubectl in a deploy job.
  # Scoped down to a namespace-limited policy once the deploy job settles.
  extra_admin_principal_arns = compact([var.github_actions_role_arn])
}

variable "github_actions_role_arn" {
  description = "The OIDC role from infra/core, granted cluster access so CD can deploy. Empty disables it."
  type        = string
  default     = ""
}
