output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

# The version AWS actually gave you. Read this after the first apply and pin it
# in var.kubernetes_version so upgrades become a deliberate act.
output "cluster_version" {
  value = aws_eks_cluster.this.version
}

output "cluster_certificate_authority_data" {
  value     = aws_eks_cluster.this.certificate_authority[0].data
  sensitive = true
}

output "cluster_security_group_id" {
  description = "The security group EKS manages for control-plane-to-node traffic"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

# ---------------------------------------------------------------------------
# IRSA plumbing
#
# These two are what any pod-level IAM role needs: the provider ARN goes in the
# trust policy principal, and the issuer URL (minus its https:// prefix) forms
# the condition key that pins the role to one namespace and ServiceAccount.
# ---------------------------------------------------------------------------

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "Issuer URL with https:// stripped, ready to use in an IAM condition key"
  value       = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

output "node_role_arn" {
  value = aws_iam_role.node.arn
}

output "node_group_name" {
  value = aws_eks_node_group.this.node_group_name
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the cluster"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${aws_eks_cluster.this.name}"
}

data "aws_region" "current" {}
