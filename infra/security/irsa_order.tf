# --- order-service IRSA ---
data "aws_iam_policy_document" "order_service_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.eks.outputs.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${data.terraform_remote_state.eks.outputs.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:cloudmart-prod:order-service-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${data.terraform_remote_state.eks.outputs.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "order_service" {
  name               = "cloudmart-order-service"
  assume_role_policy = data.aws_iam_policy_document.order_service_trust.json

  tags = {
    Project     = var.project
    Environment = var.environment
    Team        = var.team
    Owner       = var.owner
  }
}

resource "aws_iam_role_policy" "order_service_sqs" {
  name = "sqs-publish-access"
  role = aws_iam_role.order_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:SendMessage",
        "sqs:GetQueueAttributes"
      ]
      Resource = data.terraform_remote_state.sqs.outputs.queue_arn
    }]
  })
}

output "order_service_role_arn" {
  value = aws_iam_role.order_service.arn
}