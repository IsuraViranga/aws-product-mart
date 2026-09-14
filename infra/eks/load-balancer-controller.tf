# ---------------------------------------------------------------------------
# AWS Load Balancer Controller
#
# Kubernetes has no idea what an ALB is. The Ingress object you write is just a
# record in etcd until something reads it and builds real infrastructure. This
# controller is that something: it watches for Ingress resources and creates,
# updates and deletes Application Load Balancers to match.
#
# Installed with the Terraform helm provider rather than the helm CLI, for two
# reasons:
#   - no extra binary to install, and no manual step outside IaC
#   - terraform destroy removes it, which matters because an orphaned ALB keeps
#     charging $0.0225/hr after the cluster is gone
#
# It runs in kube-system, not the cloudmart namespace: it is cluster
# infrastructure that happens to serve your app, not part of your app.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# The controller's own IAM permissions
#
# Broad by necessity - creating and deleting load balancers, target groups,
# listeners, security group rules and WAF associations across the account. This
# is the policy AWS publishes and maintains for the controller; it is pinned to
# a release tag in policies/aws-lbc-iam-policy.json rather than fetched at
# apply time, so a change upstream cannot silently alter your permissions.
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "lb_controller" {
  name        = "cloudmart-aws-load-balancer-controller"
  description = "Permissions for the AWS Load Balancer Controller (upstream v2.13.4 policy)"
  policy      = file("${path.module}/policies/aws-lbc-iam-policy.json")
}

# Same IRSA pattern as the application roles: the trust policy pins the role to
# one ServiceAccount in one namespace.
data "aws_iam_policy_document" "lb_controller_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "cloudmart-aws-load-balancer-controller"
  description        = "Assumed by the AWS Load Balancer Controller pod"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_trust.json
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

# ---------------------------------------------------------------------------
# The Helm release
#
# Helm is Kubernetes' package manager: a chart is a parameterised bundle of
# manifests. Installing this one by hand would mean applying a CRD, a
# Deployment, RBAC rules, a webhook and its certificates - about a dozen
# objects that have to agree with each other.
# ---------------------------------------------------------------------------

resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.13.4" # chart version, not the same as the app version
  namespace  = "kube-system"

  # Wait for the pods to actually be ready before considering this applied.
  # Without it Terraform reports success while the webhook is still starting,
  # and the very next Ingress apply fails with a connection refused.
  wait    = true
  timeout = 600

  set = [
    {
      name  = "clusterName"
      value = module.eks.cluster_name
    },
    {
      # Let the chart create the ServiceAccount, and annotate it with the role
      # above. This is the same one-line IRSA link used by the app services.
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.lb_controller.arn
    },
    {
      # The controller can usually discover these, but being explicit avoids a
      # class of failure where it guesses wrong in a VPC with several clusters.
      name  = "region"
      value = var.aws_region
    },
    {
      name  = "vpcId"
      value = data.terraform_remote_state.network.outputs.vpc_id
    },
  ]

  depends_on = [
    aws_iam_role_policy_attachment.lb_controller,
    module.eks,
  ]
}

output "lb_controller_role_arn" {
  value = aws_iam_role.lb_controller.arn
}
