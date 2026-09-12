# ---------------------------------------------------------------------------
# Lets GitHub Actions authenticate to AWS with no stored access key.
#
# GitHub signs a short-lived token describing each workflow run. AWS verifies
# the signature against GitHub's published public keys, checks the claims
# against the trust policy below, and returns temporary credentials.
#
# Nothing is stored in GitHub secrets, so there is nothing to leak, nothing to
# rotate, and revoking access is a Terraform change rather than a key deletion.
# ---------------------------------------------------------------------------

variable "github_repository" {
  description = "owner/repo allowed to assume the CI role"
  type        = string
  default     = "IsuraViranga/aws-product-mart"
}

# Registers GitHub's token issuer as one AWS is willing to trust. Account-wide,
# not per repository - the trust policy is where scoping happens.
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # The `aud` claim AWS will require. The official configure-aws-credentials
  # action requests exactly this value.
  client_id_list = ["sts.amazonaws.com"]
}

# ---------------------------------------------------------------------------
# The role a workflow run wears
# ---------------------------------------------------------------------------

resource "aws_iam_role" "github_actions" {
  name        = "cloudmart-github-actions"
  description = "Assumed by GitHub Actions via OIDC to build and push images"

  # Sessions expire after an hour. A workflow run needs minutes.
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGitHubActionsOIDC"
        Effect = "Allow"

        # A Federated principal, not a Service or AWS principal: the caller
        # authenticates with a third party's signed token rather than with AWS
        # credentials of its own.
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }

        # Note: NOT sts:AssumeRole. Web identity federation is a distinct API
        # call that takes an external JWT as its input.
        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          # Checks the token was minted for AWS STS and not some other service
          # GitHub can also issue tokens for.
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }

          # THE LINE THAT MATTERS.
          #
          # Without a `sub` condition, ANY GitHub repository on the internet
          # could assume this role - every GitHub token has the same issuer and
          # the same audience, so those two checks restrict nothing on their own.
          # This is the single most common and most serious OIDC misconfiguration.
          #
          # `sub` format:
          #   repo:<owner>/<repo>:ref:refs/heads/<branch>
          #   repo:<owner>/<repo>:pull_request
          #   repo:<owner>/<repo>:environment:<name>
          #
          # Scoped to main and pull requests. A push to any other branch cannot
          # assume this role, and neither can a fork of your repository.
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_repository}:ref:refs/heads/main",
              "repo:${var.github_repository}:pull_request",
            ]
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# What CI may do: push images. Nothing else in the account.
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "github_actions_ecr_push" {
  name = "cloudmart-github-actions-ecr-push"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetLoginToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*" # account-level call, cannot be scoped to a repository
      },
      {
        Sid    = "PushAndInspectCloudMartImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeImages",
          "ecr:DescribeImageScanFindings",
        ]

        # Built from the repositories Terraform manages, so adding a service to
        # var.services extends this policy automatically. No pasted ARN lists.
        Resource = [for r in aws_ecr_repository.services : r.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr_push" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_ecr_push.arn
}

# ---------------------------------------------------------------------------

output "github_actions_role_arn" {
  description = "role-to-assume value for the GitHub Actions workflow"
  value       = aws_iam_role.github_actions.arn
}
