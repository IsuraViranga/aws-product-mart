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
