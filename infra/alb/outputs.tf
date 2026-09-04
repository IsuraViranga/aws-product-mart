output "alb_controller_role_arn" {
  value = aws_iam_role.alb_controller.arn
}

output "alb_controller_namespace" {
  value = "kube-system"
}

output "alb_controller_service_account_name" {
  value = "aws-load-balancer-controller"
}

output "recommended_ingress_annotations" {
  value = {
    "kubernetes.io/ingress.class"               = "alb"
    "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
    "alb.ingress.kubernetes.io/target-type"     = "ip"
    "alb.ingress.kubernetes.io/healthcheck-path" = "/health"
    "alb.ingress.kubernetes.io/subnets"         = join(",", data.terraform_remote_state.networking.outputs.public_subnet_ids)
    "alb.ingress.kubernetes.io/security-groups"  = data.terraform_remote_state.networking.outputs.sg_alb_id
  }
}
