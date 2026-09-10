# ---------------------------------------------------------------------------
# The identity product-service runs as.
#
# An EC2 instance (later, an EKS pod) wears this role and receives temporary,
# auto-rotating credentials from the instance metadata service. No access key
# is ever created, stored, or rotated by hand.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# The role, and who is allowed to wear it
# ---------------------------------------------------------------------------

resource "aws_iam_role" "product_service" {
  name        = "cloudmart-product-service-ec2"
  description = "Identity for product-service running on EC2"

  # The TRUST policy: who may assume this role. Not what they can do.
  # `ec2.amazonaws.com` means the EC2 service itself, on behalf of an instance
  # this role is attached to. Swapping this principal is all that changes when
  # the workload moves to EKS (an OIDC provider) or GitHub Actions.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEC2ToAssume"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# EC2 cannot attach a role directly - it attaches an *instance profile*, which
# is a thin wrapper around exactly one role. The console creates this silently
# when you pick a role in the launch wizard, which is why most people never
# learn it exists.
resource "aws_iam_instance_profile" "product_service" {
  name = "cloudmart-product-service-ec2"
  role = aws_iam_role.product_service.name
}

# ---------------------------------------------------------------------------
# What it can do
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "product_service_dynamodb" {
  # No `description`: it is immutable on an IAM policy, so setting one on an
  # imported policy that has none would force a destroy-and-recreate.
  name = "cloudmart-product-service-dynamodb"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ProductCatalogueAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query",
        ]
        # THE POINT OF THIS WHOLE STEP: not a pasted ARN string, but a
        # reference. Rename the table and this policy follows it. Delete the
        # table and Terraform knows the policy depends on it.
        Resource = aws_dynamodb_table.products.arn
      }
    ]
  })
}

resource "aws_iam_policy" "product_service_ecr_pull" {
  name = "cloudmart-product-service-ecr-pull"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetLoginToken"
        Effect = "Allow"
        Action = "ecr:GetAuthorizationToken"
        # Genuinely cannot be scoped: registry login is account-level and is
        # not tied to any repository.
        Resource = "*"
      },
      {
        Sid    = "PullProductServiceImageOnly"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
        ]
        Resource = aws_ecr_repository.services["product-service"].arn
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Wiring the policies to the role
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "product_service_dynamodb" {
  role       = aws_iam_role.product_service.name
  policy_arn = aws_iam_policy.product_service_dynamodb.arn
}

resource "aws_iam_role_policy_attachment" "product_service_ecr_pull" {
  role       = aws_iam_role.product_service.name
  policy_arn = aws_iam_policy.product_service_ecr_pull.arn
}

# AWS-managed, so it is referenced by its fixed ARN rather than defined here.
# Grants only what the SSM agent needs to register and open sessions.
resource "aws_iam_role_policy_attachment" "product_service_ssm" {
  role       = aws_iam_role.product_service.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
