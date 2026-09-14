# ---------------------------------------------------------------------------
# IRSA - IAM Roles for Service Accounts
#
# The problem this solves:
#
# docker-compose.yml mounts ${USERPROFILE}/.aws into three containers so they
# can reach DynamoDB and SQS. That works locally and is unacceptable anywhere
# else - it hands every one of those containers your full admin credentials,
# on disk, never rotated.
#
# IRSA replaces it. Each pod gets a signed token proving "I am the
# product-service ServiceAccount in the cloudmart namespace". AWS STS trades
# that token for temporary credentials scoped to one role. No keys are stored,
# nothing is mounted, and the credentials expire on their own.
#
# The chain, once:
#
#   pod runs as ServiceAccount "product-service"
#     -> kubelet mounts a signed JWT naming that ServiceAccount
#       -> SDK calls sts:AssumeRoleWithWebIdentity with the JWT
#         -> STS verifies the signature against the cluster's OIDC provider
#           -> the role's trust policy checks the "sub" claim matches
#             -> temporary credentials, valid one hour
#
# The condition on "sub" below is what makes this safe. Without it, ANY pod in
# the cluster could assume the role. With it, only a pod running as that exact
# ServiceAccount in that exact namespace can.
# ---------------------------------------------------------------------------

variable "app_namespace" {
  description = "Kubernetes namespace the CloudMart services run in"
  type        = string
  default     = "cloudmart"
}

# The DynamoDB table and SQS queues were built in infra/core. Read their ARNs
# rather than pasting them, so the policies below stay correct if they are ever
# rebuilt.
data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = "cloudmart-tfstate-468683594325"
    key    = "core/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

locals {
  # Only three of the five services touch AWS at all. user-service runs
  # DB_BACKEND=memory and the frontend serves static files, so neither gets a
  # role - they get no AWS credentials of any kind.
  irsa_service_accounts = toset([
    "product-service",
    "order-service",
    "notification-service",
  ])
}

# ---------------------------------------------------------------------------
# Trust policies - who may assume each role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "irsa_trust" {
  for_each = local.irsa_service_accounts

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    # Pins the role to one ServiceAccount in one namespace. This single
    # condition is the difference between IRSA and handing out credentials.
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.app_namespace}:${each.value}"]
    }

    # Rejects tokens minted for some other audience.
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = local.irsa_service_accounts

  name               = "cloudmart-irsa-${each.value}"
  description        = "Assumed by the ${each.value} pod via its Kubernetes ServiceAccount"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust[each.value].json
}

# ---------------------------------------------------------------------------
# product-service: read and write the product catalogue
#
# Scoped to the one table. Note the absence of dynamodb:DeleteTable and
# friends - the application reads and writes items, it never manages schema.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "product_service" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [
      data.terraform_remote_state.core.outputs.products_table_arn,
      "${data.terraform_remote_state.core.outputs.products_table_arn}/index/*",
    ]
  }
}

resource "aws_iam_role_policy" "product_service" {
  name   = "dynamodb-products"
  role   = aws_iam_role.irsa["product-service"].id
  policy = data.aws_iam_policy_document.product_service.json
}

# ---------------------------------------------------------------------------
# order-service: publish order events
#
# Send only. An order producer has no business reading or deleting from the
# queue, and saying so here means a bug in the service cannot do it either.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "order_service" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]
    resources = [data.terraform_remote_state.core.outputs.orders_queue_arn]
  }
}

resource "aws_iam_role_policy" "order_service" {
  name   = "sqs-publish-orders"
  role   = aws_iam_role.irsa["order-service"].id
  policy = data.aws_iam_policy_document.order_service.json
}

# ---------------------------------------------------------------------------
# notification-service: consume order events
#
# The mirror image: receive and delete, but never send. DeleteMessage is
# required - without it a consumer processes the same message forever, because
# SQS only removes a message when the consumer confirms it is done.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "notification_service" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]
    resources = [data.terraform_remote_state.core.outputs.orders_queue_arn]
  }
}

resource "aws_iam_role_policy" "notification_service" {
  name   = "sqs-consume-orders"
  role   = aws_iam_role.irsa["notification-service"].id
  policy = data.aws_iam_policy_document.notification_service.json
}

# ---------------------------------------------------------------------------
# Outputs
#
# These ARNs go into the ServiceAccount manifests as the
# eks.amazonaws.com/role-arn annotation - the one line that connects a
# Kubernetes identity to an AWS one.
# ---------------------------------------------------------------------------

output "irsa_role_arns" {
  description = "Annotate each ServiceAccount with its matching role ARN"
  value       = { for k, r in aws_iam_role.irsa : k => r.arn }
}

output "app_namespace" {
  value = var.app_namespace
}

# Convenience: the application config the manifests need, read straight from
# infra/core so nothing is hardcoded in a YAML file.
output "app_config" {
  description = "Environment values for the CloudMart deployments"
  value = {
    aws_region     = data.terraform_remote_state.core.outputs.aws_region
    dynamodb_table = data.terraform_remote_state.core.outputs.products_table_name
    sqs_queue_url  = data.terraform_remote_state.core.outputs.orders_queue_url
    ecr_registry   = data.terraform_remote_state.core.outputs.ecr_registry
  }
}
