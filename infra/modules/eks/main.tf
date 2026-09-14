# ---------------------------------------------------------------------------
# A small EKS cluster, sized for learning and built to be destroyed.
#
# Everything expensive lives in this module: the control plane ($0.10/hr), the
# nodes, and the EBS volumes attached to them. Destroying this root returns the
# account to roughly zero spend while leaving the VPC, ECR, DynamoDB and SQS
# in place.
#
# What is deliberately included, because these are the parts worth learning:
#
#   IRSA        an OIDC provider, so pods assume IAM roles directly instead of
#               being handed static access keys. This is the single most
#               important thing on the page.
#   Access      authentication_mode = API. Access is granted with real IAM
#               resources rather than by editing the aws-auth ConfigMap, which
#               was the old approach and had no audit trail.
#   Addons      vpc-cni, coredns and kube-proxy as managed addons, so AWS
#               handles their version compatibility rather than you.
#   LB tags     subnets tagged so the AWS Load Balancer Controller can find
#               them automatically when you create an Ingress.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

data "aws_partition" "current" {}

locals {
  # Partition is looked up rather than hardcoded as "aws" so the policy ARNs
  # below stay correct in GovCloud or China. Costs nothing, avoids a whole
  # category of copy-paste bug.
  policy_prefix = "arn:${data.aws_partition.current.partition}:iam::aws:policy"
}

# ---------------------------------------------------------------------------
# Control plane IAM role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "${local.policy_prefix}/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# The cluster
# ---------------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    # Control plane ENIs live in the private subnets. The public endpoint below
    # is what your laptop talks to; these ENIs are how the control plane reaches
    # back into the VPC to run things like `kubectl exec` and `kubectl logs`.
    subnet_ids = var.private_subnet_ids

    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
  }

  access_config {
    # API drops the aws-auth ConfigMap entirely. Access is granted with
    # aws_eks_access_entry resources, which are visible in CloudTrail and can be
    # revoked without a kubectl round trip.
    authentication_mode = "API"

    # Whoever runs terraform apply becomes cluster admin. Without this you would
    # create a cluster you cannot talk to.
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Send control plane logs to CloudWatch. "audit" is the one that answers "who
  # deleted that deployment". Retention is set below so these do not quietly
  # accumulate after the cluster is destroyed.
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# EKS creates this log group itself if absent, but then it has no retention and
# keeps paying for storage long after the cluster is gone. Declaring it here
# means terraform destroy takes the logs with it.
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = 7
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# IRSA: let pods assume IAM roles
#
# The cluster publishes an OIDC discovery document. Registering it as an
# identity provider in IAM means a ServiceAccount token can be exchanged for
# real AWS credentials - so product-service reaches DynamoDB, and
# order-service reaches SQS, with no long-lived keys anywhere.
# ---------------------------------------------------------------------------

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
  tags            = var.tags
}

# ---------------------------------------------------------------------------
# Worker node IAM role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-eks-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  tags               = var.tags
}

# These three are the required minimum for a node to join and function.
# ECR read-only is what lets the kubelet pull your CloudMart images.
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = "${local.policy_prefix}/${each.value}"
}

# ---------------------------------------------------------------------------
# Managed node group
# ---------------------------------------------------------------------------

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type
  disk_size      = var.node_disk_size_gb
  ami_type       = "AL2023_x86_64_STANDARD"

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = var.tags

  lifecycle {
    # Nodes in private subnets reach the EKS API, ECR and S3 through the NAT
    # gateway. With it off they boot, fail to register, and the node group
    # rolls back after about fifteen minutes with an unhelpful error. Failing
    # here instead turns that into one clear sentence.
    precondition {
      condition     = var.nat_gateway_enabled
      error_message = "Nodes in private subnets cannot reach ECR or the EKS API without NAT. Apply infra/network with -var enable_nat_gateway=true first, and remember to turn it back off when you tear this down."
    }

    # desired_size drifts as the cluster autoscales. Without this, the next
    # apply would helpfully scale you back down mid-experiment.
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# ---------------------------------------------------------------------------
# Managed addons
#
# Applied after the node group, because coredns has actual pods that need
# somewhere to be scheduled. Without the dependency the addon installs into an
# empty cluster and sits Degraded until nodes appear.
# ---------------------------------------------------------------------------

resource "aws_eks_addon" "this" {
  for_each = toset(["vpc-cni", "coredns", "kube-proxy"])

  cluster_name = aws_eks_cluster.this.name
  addon_name   = each.value

  # If a version already exists (say the addon was installed by hand), take
  # ours rather than failing the apply with a conflict.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_eks_node_group.this]
}

# ---------------------------------------------------------------------------
# Extra cluster admins
#
# The applying principal is already admin via bootstrap_cluster_creator_admin_
# permissions. This is for anyone else - a teammate, or the GitHub Actions role
# once you add a deploy job.
# ---------------------------------------------------------------------------

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.extra_admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = aws_eks_access_entry.admin

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# ---------------------------------------------------------------------------
# Subnet tags for load balancer auto-discovery
#
# When you create an Ingress, the AWS Load Balancer Controller has to decide
# which subnets to put the ALB in. It does that by looking for these tags. They
# are applied here rather than in the networking module because they name a
# specific cluster, and the VPC outlives any cluster built on it.
# ---------------------------------------------------------------------------

resource "aws_ec2_tag" "public_elb" {
  for_each = toset(var.public_subnet_ids)

  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_ec2_tag" "private_internal_elb" {
  for_each = toset(var.private_subnet_ids)

  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

# Marks the subnets as belonging to this cluster. "shared" rather than "owned"
# means destroying the cluster will not try to take the subnets with it.
resource "aws_ec2_tag" "cluster_shared" {
  for_each = toset(concat(var.public_subnet_ids, var.private_subnet_ids))

  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.name}"
  value       = "shared"
}
