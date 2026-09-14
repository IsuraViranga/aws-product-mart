variable "name" {
  description = "Cluster name, also used as a prefix for the IAM roles it owns"
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster and its nodes live in"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets the worker nodes run in. Nodes here need NAT (or ECR interface endpoints) to pull images."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Subnets the internet-facing load balancers are placed in"
  type        = list(string)
}

# Left null on purpose. AWS then picks the current default version, which is
# guaranteed to exist. Once you have applied once, read the real version out of
# the output and pin it here - an unpinned control plane can be upgraded out
# from under you at AWS's discretion.
variable "kubernetes_version" {
  description = "Kubernetes minor version, e.g. \"1.33\". Null means let AWS choose."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Node group sizing
#
# t3.small is 2 vCPU / 2 GiB. Two of them comfortably hold five small services
# plus the system pods. Note the pod-per-node ceiling: with the default VPC CNI
# a t3.small tops out at 11 pods, so two nodes give you 22 - enough here, but
# it is the limit you will hit first, not CPU or memory.
# ---------------------------------------------------------------------------

variable "node_instance_types" {
  description = "Instance types for the managed node group"
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_disk_size_gb" {
  description = "EBS volume per node. Billed while the cluster exists."
  type        = number
  default     = 20
}

# SPOT is roughly 70% cheaper and entirely appropriate for practice: the worst
# case is a node being reclaimed and pods rescheduling, which is a useful thing
# to watch happen. Switch to ON_DEMAND if you need a stable demo.
variable "node_capacity_type" {
  description = "SPOT or ON_DEMAND"
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.node_capacity_type)
    error_message = "node_capacity_type must be SPOT or ON_DEMAND."
  }
}

# ---------------------------------------------------------------------------
# API endpoint exposure
# ---------------------------------------------------------------------------

# Public access is on so kubectl works from your laptop without a bastion.
# The endpoint still requires IAM authentication - it is not an open cluster -
# but narrowing this to your own IP is strictly better if your address is
# stable. Find it with: curl -s ifconfig.me
variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "extra_admin_principal_arns" {
  description = "Additional IAM principals granted cluster-admin, beyond whoever applies this"
  type        = list(string)
  default     = []
}

variable "nat_gateway_enabled" {
  description = "Read from the network state so the node group precondition can fail early and loudly"
  type        = bool
}

variable "tags" {
  description = "Extra tags, merged over the provider default_tags"
  type        = map(string)
  default     = {}
}
