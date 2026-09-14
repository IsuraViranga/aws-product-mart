variable "name" {
  description = "Prefix for every resource name in this VPC"
  type        = string
  default     = "cloudmart"
}

variable "vpc_cidr" {
  description = "Address range for the whole VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread subnets across. EKS requires at least two."
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two availability zones are required (EKS will not create a cluster in one)."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnets - route to the internet gateway. Load balancers and NAT live here."
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.16.0/20"]
}

variable "private_app_subnet_cidrs" {
  description = "Private subnets for compute. EKS nodes and pods."
  type        = list(string)
  default     = ["10.0.64.0/20", "10.0.80.0/20"]
}

variable "private_data_subnet_cidrs" {
  description = "Private subnets for databases. No route out at all."
  type        = list(string)
  default     = ["10.0.128.0/20", "10.0.144.0/20"]
}

# ---------------------------------------------------------------------------
# Cost controls
# ---------------------------------------------------------------------------

variable "enable_nat_gateway" {
  description = <<-EOT
    Create a NAT gateway so private subnets can reach the internet.

    OFF BY DEFAULT because this is the single most expensive thing in the
    module: roughly $0.059/hour plus $0.059 per GB processed, which is about
    $43/month per gateway even when completely idle.

    Turn it on only for the duration of an EKS session, and turn it off again.
  EOT
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = <<-EOT
    Use one NAT gateway for all AZs instead of one per AZ.

    One per AZ is the production answer: if an AZ fails, the others keep their
    route out. One shared gateway halves or thirds the cost but becomes a single
    point of failure, and cross-AZ traffic to reach it is billed.

    True here because this is a learning environment where $43/month matters
    more than surviving an AZ outage.
  EOT
  type        = bool
  default     = true
}
