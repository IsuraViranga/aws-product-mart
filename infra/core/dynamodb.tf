# ---------------------------------------------------------------------------
# Product catalogue table, read and written by product-service.
#
# This config deliberately matches the table exactly as it was created in the
# console, so the first `plan` after import is clean. Improvements (like
# point-in-time recovery) are made afterwards, as separate, visible changes.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "products" {
  name = "cloudmart-products"

  # PAY_PER_REQUEST bills per read/write with nothing charged when idle, which
  # suits bursty, unpredictable traffic. PROVISIONED is cheaper at steady high
  # volume but you pay for the capacity whether you use it or not.
  billing_mode = "PAY_PER_REQUEST"

  # The partition key. Every item must have it, and it is the only way to fetch
  # a single item cheaply.
  hash_key = "id"

  # Only key attributes are declared. DynamoDB is schemaless for everything
  # else - `name`, `price` and `stock` exist on the items without being
  # declared anywhere.
  attribute {
    name = "id"
    type = "S" # S = string, N = number, B = binary
  }
}
