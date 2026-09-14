# ---------------------------------------------------------------------------
# A three-tier VPC across two availability zones.
#
#   public       internet-facing load balancers, NAT gateway
#   private app  EKS nodes and pods - reachable only from inside the VPC
#   private data databases - no route to the internet at all
#
# Everything here is free except the NAT gateway, which is off by default.
# ---------------------------------------------------------------------------

locals {
  az_count = length(var.availability_zones)

  # One NAT gateway shared by all AZs, or one per AZ. Zero when disabled.
  nat_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : local.az_count) : 0
}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # Both required by EKS: nodes resolve each other and the API server by DNS
  # name, not IP.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

# ---------------------------------------------------------------------------
# Public tier
# ---------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # Anything launched here gets a public IP without asking.
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-${var.availability_zones[count.index]}"

    # EKS discovers where to place internet-facing load balancers by looking
    # for this tag. Without it, an Ingress will fail with "could not find any
    # suitable subnets" - a genuinely baffling error if you have not seen it.
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  # THIS LINE is what makes these subnets public. Not the name, not a flag -
  # a default route pointing at the internet gateway.
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name}-rt-public" }
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# NAT - the expensive bit, created only when enable_nat_gateway = true
# ---------------------------------------------------------------------------

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"
  tags   = { Name = "${var.name}-nat-eip-${count.index}" }
}

resource "aws_nat_gateway" "this" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  # A NAT gateway lives in a PUBLIC subnet. That trips people up: it is the
  # thing private subnets route through, but it needs its own way out.
  subnet_id = aws_subnet.public[count.index].id

  tags       = { Name = "${var.name}-nat-${count.index}" }
  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# Private app tier - EKS nodes and pods
# ---------------------------------------------------------------------------

resource "aws_subnet" "private_app" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.name}-private-app-${var.availability_zones[count.index]}"

    # The private equivalent of the elb tag: where EKS places internal-only
    # load balancers.
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# One route table per AZ, so each can point at its own NAT gateway when
# single_nat_gateway is false.
resource "aws_route_table" "private_app" {
  count  = local.az_count
  vpc_id = aws_vpc.this.id

  # A dynamic block emits this route only when a NAT gateway exists. With NAT
  # disabled the table has no default route at all, so these subnets simply
  # cannot reach the internet - which is correct, and free.
  dynamic "route" {
    for_each = local.nat_count > 0 ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
    }
  }

  tags = { Name = "${var.name}-rt-private-app-${count.index}" }
}

resource "aws_route_table_association" "private_app" {
  count          = local.az_count
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

# ---------------------------------------------------------------------------
# Private data tier - databases, deliberately with no route out
# ---------------------------------------------------------------------------

resource "aws_subnet" "private_data" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_data_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = { Name = "${var.name}-private-data-${var.availability_zones[count.index]}" }
}

resource "aws_route_table" "private_data" {
  vpc_id = aws_vpc.this.id
  # No routes beyond the VPC-local one AWS adds automatically. A database here
  # can talk to the VPC and nothing else - it cannot be reached from the
  # internet, and cannot call out to it either.
  tags = { Name = "${var.name}-rt-private-data" }
}

resource "aws_route_table_association" "private_data" {
  count          = local.az_count
  subnet_id      = aws_subnet.private_data[count.index].id
  route_table_id = aws_route_table.private_data.id
}

# ---------------------------------------------------------------------------
# Gateway VPC endpoints - free, and they save real money
# ---------------------------------------------------------------------------

# Without this, a pod in a private subnet talking to DynamoDB routes through
# the NAT gateway and you pay $0.059 per GB. A gateway endpoint is a route
# table entry that sends that traffic over AWS's own network instead:
# free, faster, and it never leaves the AWS backbone.
#
# Gateway endpoints exist only for S3 and DynamoDB, and only they are free.
# Interface endpoints (for every other service) cost ~$7/month each.
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    aws_route_table.private_app[*].id,
    [aws_route_table.private_data.id],
  )

  tags = { Name = "${var.name}-endpoint-dynamodb" }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    aws_route_table.private_app[*].id,
    [aws_route_table.private_data.id],
  )

  tags = { Name = "${var.name}-endpoint-s3" }
}

# Reads the region from the provider rather than hardcoding it, so the endpoint
# service names are correct wherever this module is used.
data "aws_region" "current" {}
