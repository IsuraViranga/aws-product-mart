output "rds_endpoint" {
  value = aws_db_instance.users.address
}

output "rds_db_name" {
  value = aws_db_instance.users.db_name
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.products.name
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.products.arn
}
