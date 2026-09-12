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

variable "github_owner" {
  description = "GitHub account that owns the repository"
  type        = string
  default     = "IsuraViranga"
}

variable "github_owner_id" {
  description = "Numeric GitHub user/org ID. From the OIDC sub claim, or: gh api users/<owner> --jq .id"
  type        = string
  default     = "110254441"
}

variable "github_repo" {
  description = "Repository name"
  type        = string
  default     = "aws-product-mart"
}

variable "github_repo_id" {
  description = "Numeric repository ID. From the OIDC sub claim, or: gh api repos/<owner>/<repo> --jq .id"
  type        = string
  default     = "1360420722"
}

locals {
  # GitHub issues OIDC subjects containing immutable numeric IDs alongside the
  # names:
  #     repo:IsuraViranga@110254441/aws-product-mart@1360420722:ref:refs/heads/main
  #
  # Most documentation still shows the older name-only form:
  #     repo:IsuraViranga/aws-product-mart:ref:refs/heads/main
  #
  # Both are listed so the policy holds whichever GitHub sends. Note these are
  # exact strings, not wildcards - listing two forms costs nothing in security,
  # whereas a pattern like "repo:IsuraViranga*/..." would also match an account
  # called IsuraVirangaEvil.
  github_repo_refs = [
    "${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}",
    "${var.github_owner}/${var.github_repo}",
  ]

  # Branch and event scoping: main pushes and pull requests only.
  github_oidc_subjects = flatten([
    for r in local.github_repo_refs : [
      "repo:${r}:ref:refs/heads/main",
      "repo:${r}:pull_request",
    ]
  ])
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
          # Confirms the token was minted for AWS STS rather than some other
          # service GitHub can also issue tokens for.
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }

          # THE CONDITION THAT MATTERS.
          #
          # Without a `sub` restriction, ANY GitHub repository on the internet
          # could assume this role: every GitHub token shares the same issuer
          # and audience, so those two checks restrict nothing by themselves.
          # This is the most common and most serious OIDC misconfiguration.
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.github_oidc_subjects
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

output "github_oidc_allowed_subjects" {
  description = "Exact sub claims this role accepts - compare against CloudTrail when debugging"
  value       = local.github_oidc_subjects
}
