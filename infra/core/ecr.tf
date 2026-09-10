# ---------------------------------------------------------------------------
# Container registries, one per service.
#
# Five near-identical repositories are declared by ONE resource block using
# `for_each`. Adding a sixth service is a one-word change to var.services.
# ---------------------------------------------------------------------------

variable "services" {
  description = "The CloudMart services that get a container image"
  type        = set(string)
  default = [
    "product-service",
    "order-service",
    "user-service",
    "notification-service",
    "frontend",
  ]
}

resource "aws_ecr_repository" "services" {
  # `for_each` creates one instance per element, keyed by the element itself.
  # Refer to them as aws_ecr_repository.services["order-service"].
  #
  # Prefer this over `count`. With count, resources are keyed by list POSITION,
  # so deleting the second service renumbers everything after it and Terraform
  # destroys and recreates them all. for_each keys by NAME, so removing one
  # touches only that one.
  for_each = var.services

  name = "cloudmart/${each.key}"

  # MUTABLE lets us re-push a tag like `latest` while developing. IMMUTABLE is
  # the production-grade choice: a released tag can never be silently swapped
  # for different content. Worth revisiting once the CI pipeline tags by commit
  # SHA and never needs to overwrite.
  image_tag_mutability = "MUTABLE"

  # Free basic scanning against the CVE database on every push. This is what
  # produced the finding that moved product-service off Debian.
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256" # free; KMS would be $1/month per key
  }
}

# ---------------------------------------------------------------------------
# Lifecycle policies - stop storage growing without limit
# ---------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the 10 most recent images"
        selection = {
          # Deliberately `any`, NOT `untagged`.
          #
          # The obvious rule is "delete untagged images", and it is a trap:
          # BuildKit pushes an image index plus untagged child manifests, and
          # your tag points at the index. Deleting untagged images would delete
          # the actual image and leave the tag pointing at nothing.
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
