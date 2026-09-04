# --- user-service IRSA ---
data "aws_iam_policy_document" "user_service_trust" {
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
      values   = ["system:serviceaccount:cloudmart-prod:user-service-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${data.terraform_remote_state.eks.outputs.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "user_service" {
  name               = "cloudmart-user-service"
  assume_role_policy = data.aws_iam_policy_document.user_service_trust.json

  tags = {
    Project     = var.project
    Environment = var.environment
    Team        = var.team
    Owner       = var.owner
  }
}

resource "aws_iam_role_policy" "user_service_secrets" {
  name = "secretsmanager-read"
  role = aws_iam_role.user_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = data.terraform_remote_state.databases.outputs.db_secret_arn
    }]
  })
}

output "user_service_role_arn" {
  value = aws_iam_role.user_service.arn
}
