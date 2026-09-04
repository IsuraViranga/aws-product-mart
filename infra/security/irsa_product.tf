# --- product-service IRSA ---
data "aws_iam_policy_document" "product_service_trust" {
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
      values   = ["system:serviceaccount:cloudmart-prod:product-service-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${data.terraform_remote_state.eks.outputs.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "product_service" {
  name               = "cloudmart-product-service"
  assume_role_policy = data.aws_iam_policy_document.product_service_trust.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "product_service_dynamodb" {
  name = "dynamodb-access"
  role = aws_iam_role.product_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
        "dynamodb:Query"
      ]
      Resource = data.terraform_remote_state.databases.outputs.dynamodb_table_arn
    }]
  })
}