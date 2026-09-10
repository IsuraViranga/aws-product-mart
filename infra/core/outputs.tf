# ---------------------------------------------------------------------------
# Values other projects and the application need to know.
#
# These replace hardcoded ARNs and URLs: instead of pasting a queue URL into
# docker-compose.yml by hand, you read it from here.
# ---------------------------------------------------------------------------

output "products_table_name" {
  description = "DYNAMODB_TABLE for product-service"
  value       = aws_dynamodb_table.products.name
}

output "products_table_arn" {
  description = "Table ARN, for scoping IAM policies to exactly this table"
  value       = aws_dynamodb_table.products.arn
}

output "orders_queue_url" {
  description = "SQS_QUEUE_URL for order-service and notification-service"
  value       = aws_sqs_queue.orders.url
}

output "orders_queue_arn" {
  description = "Queue ARN, for scoping IAM policies"
  value       = aws_sqs_queue.orders.arn
}

output "orders_dlq_url" {
  description = "Dead-letter queue URL, for inspecting failed messages"
  value       = aws_sqs_queue.orders_dlq.url
}

output "aws_region" {
  description = "Region these resources live in"
  value       = var.aws_region
}

output "ecr_registry" {
  description = "Registry hostname to prefix image names with"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}
