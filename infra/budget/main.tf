# ---------------------------------------------------------------------------
# Spend guardrails.
#
# This root exists so that a forgotten EKS cluster costs an email, not a
# surprise at the end of the month. It is applied FIRST and destroyed LAST:
# every other root can come and go, this one stays.
#
# AWS Budgets is a billing service, so these resources cost nothing to run.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "cloudmart-tfstate-468683594325"
    key          = "budget/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cloudmart"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "isura"
    }
  }
}

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

# No default on purpose. Terraform will prompt for it rather than silently
# mailing alerts to whoever the last person to edit this file happened to be.
variable "alert_email" {
  description = "Address that receives budget alerts"
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

variable "monthly_limit_usd" {
  description = "Monthly ceiling for the whole account"
  type        = number
  default     = 20
}

# A forgotten EKS stack burns roughly $5.30/day. A $3 daily budget therefore
# trips inside about fourteen hours, which is the difference between noticing
# overnight and noticing on payday.
variable "daily_limit_usd" {
  description = "Daily ceiling, sized to catch a cluster left running overnight"
  type        = number
  default     = 3
}

# ---------------------------------------------------------------------------
# Monthly budget
#
# Three notifications, deliberately different in kind:
#   50%  ACTUAL     - early heads-up, still cheap to react
#   90%  ACTUAL     - you are about to blow the budget
#  100%  FORECASTED - AWS projects the month will end over, based on run rate.
#                     This is the one that fires while there is still time to
#                     do something about it.
# ---------------------------------------------------------------------------

resource "aws_budgets_budget" "monthly" {
  name         = "cloudmart-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Measure usage, not the bill.
  #
  # If the account is carrying AWS credits, a budget that counts them nets out
  # to about zero however much you actually consume - so the alert never fires
  # and you learn nothing until the credits run out. Excluding them makes this
  # track real usage, which is the number worth watching while practising.
  cost_types {
    include_credit = false
    include_refund = false
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 90
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

# ---------------------------------------------------------------------------
# Daily budget
#
# The month-long budget is too slow to catch the specific mistake this project
# is prone to: standing up EKS for an hour of practice and forgetting to run
# terraform destroy. This one notices the next morning.
# ---------------------------------------------------------------------------

resource "aws_budgets_budget" "daily" {
  name         = "cloudmart-daily"
  budget_type  = "COST"
  limit_amount = tostring(var.daily_limit_usd)
  limit_unit   = "USD"
  time_unit    = "DAILY"

  # Same reasoning as the monthly budget: track usage, not the post-credit bill.
  cost_types {
    include_credit = false
    include_refund = false
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "monthly_budget_name" {
  value = aws_budgets_budget.monthly.name
}

output "daily_budget_name" {
  value = aws_budgets_budget.daily.name
}

output "alerts_go_to" {
  value       = var.alert_email
  description = "Confirm this address can actually receive mail"
}
