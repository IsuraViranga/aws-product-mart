# Re-exported so the deploy workflow and any IRSA roles can read them.

output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "cluster_version" { value = module.eks.cluster_version }
output "oidc_provider_arn" { value = module.eks.oidc_provider_arn }
output "oidc_provider_url" { value = module.eks.oidc_provider_url }
output "node_role_arn" { value = module.eks.node_role_arn }

output "configure_kubectl" {
  description = "Run this first after apply"
  value       = module.eks.configure_kubectl
}
