# ---------------------------------------------------------------------------
# Cluster access for GitHub Actions
#
# The deploy job runs kubectl, so the role it assumes needs Kubernetes
# permissions - which are separate from IAM permissions. Being an AWS admin
# grants you nothing inside the cluster; that is the whole point of
# authentication_mode = "API".
#
# Two objects are needed:
#   access entry        registers the IAM principal as a cluster identity
#   policy association  says what that identity may do
#
# Scoped deliberately:
#
#   AmazonEKSEditPolicy, not AmazonEKSClusterAdminPolicy. Edit can create and
#   update workloads but cannot touch RBAC, CRDs or cluster-scoped resources.
#
#   type = "namespace", limited to cloudmart. CI can deploy the application and
#   nothing else. It cannot touch kube-system, so a compromised workflow cannot
#   replace CoreDNS or the load balancer controller.
#
# The old way of doing this was editing the aws-auth ConfigMap - a single
# cluster-wide file, no audit trail, and one bad edit locked everyone out.
# These are real AWS resources: visible in CloudTrail, revocable without
# kubectl.
# ---------------------------------------------------------------------------

locals {
  # Read from infra/core rather than hardcoded, so it stays correct if the role
  # is ever rebuilt.
  github_actions_role_arn = data.terraform_remote_state.core.outputs.github_actions_role_arn
}

# ---------------------------------------------------------------------------
# The AWS-side half.
#
# Easy to miss, and the failure is confusing when you do: the access entry
# below grants KUBERNETES permissions, but `aws eks update-kubeconfig` is an
# AWS API call. It needs eks:DescribeCluster in IAM to read the endpoint and
# CA certificate before kubectl exists at all.
#
# Without it the deploy job fails at the first kubectl step with an IAM error,
# which reads like the access entry is broken when it is perfectly fine. Two
# permission systems, both required, failing in the wrong-looking place.
#
# Scoped to this one cluster - the role cannot enumerate or describe others.
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "github_actions_eks" {
  name        = "cloudmart-github-actions-eks-describe"
  description = "Lets the CI role run aws eks update-kubeconfig against the cloudmart cluster"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeThisClusterOnly"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = module.eks.cluster_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_eks" {
  # The role itself is managed in infra/core; this only attaches a policy to
  # it. Attaching from here keeps the EKS-specific grant with the EKS state, so
  # destroying the cluster removes the permission to reach it.
  role       = "cloudmart-github-actions"
  policy_arn = aws_iam_policy.github_actions_eks.arn
}

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = module.eks.cluster_name
  principal_arn = local.github_actions_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions" {
  cluster_name  = module.eks.cluster_name
  principal_arn = local.github_actions_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [var.app_namespace]
  }

  depends_on = [aws_eks_access_entry.github_actions]
}

output "cicd_principal_arn" {
  description = "The IAM role GitHub Actions assumes, granted edit rights on the app namespace only"
  value       = local.github_actions_role_arn
}
