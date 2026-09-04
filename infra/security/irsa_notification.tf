# --- notification-service IRSA ---
data "aws_iam_policy_document" "notification_service_trust" {
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
      values   = ["system:serviceaccount:cloudmart-prod:notification-service-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${data.terraform_remote_state.eks.outputs.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "notification_service" {
  name               = "cloudmart-notification-service"
  assume_role_policy = data.aws_iam_policy_document.notification_service_trust.json

  tags = {
    Project     = var.project
    Environment = var.environment
    Team        = var.team
    Owner       = var.owner
  }
}

resource "aws_iam_role_policy" "notification_service_sqs_ses" {
  name = "sqs-consume-ses-send"
  role = aws_iam_role.notification_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = data.terraform_remote_state.sqs.outputs.queue_arn
      },
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ses:FromAddress" = var.from_email
          }
        }
      }
    ]
  })
}

output "notification_service_role_arn" {
  value = aws_iam_role.notification_service.arn
}
