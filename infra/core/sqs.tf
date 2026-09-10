# ---------------------------------------------------------------------------
# Order event queue: order-service publishes, notification-service consumes.
# ---------------------------------------------------------------------------

# The dead-letter queue must exist before the main queue can point at it.
# Terraform works this out from the reference in `redrive_policy` below - the
# ordering is never stated explicitly.
resource "aws_sqs_queue" "orders_dlq" {
  name = "cloudmart-orders-dlq"

  max_message_size = 1048576 # 1 MiB

  # Failed messages are worth keeping longer than live ones: nobody inspects a
  # dead-letter queue within four days of something breaking. 14 days is the
  # maximum SQS allows.
  message_retention_seconds = 1209600 # 14 days

  sqs_managed_sse_enabled = true
}

resource "aws_sqs_queue" "orders" {
  name = "cloudmart-orders"

  max_message_size = 1048576 # 1 MiB

  # How long a received message stays hidden from other consumers. Must exceed
  # the time your consumer needs to process one, or the message reappears and
  # gets handled twice while the first attempt is still running.
  visibility_timeout_seconds = 30

  message_retention_seconds = 345600 # 4 days

  # Long polling. SQS holds the connection open until a message arrives or this
  # many seconds pass, instead of returning empty immediately. Fewer API calls,
  # lower latency, lower cost. 0 would mean short polling.
  receive_wait_time_seconds = 20

  # Encryption at rest with an SQS-managed key. Free. Using a customer-managed
  # KMS key instead would cost $1/month plus per-request charges.
  sqs_managed_sse_enabled = true

  # After maxReceiveCount failed processing attempts, SQS stops redelivering
  # and moves the message to the dead-letter queue. Without this, one poison
  # message would be retried forever and block the consumer.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.orders_dlq.arn
    maxReceiveCount     = 3
  })
}
