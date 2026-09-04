resource "aws_db_subnet_group" "main" {
  name       = "cloudmart-db-subnet-group"
  subnet_ids = data.terraform_remote_state.networking.outputs.private_data_subnet_ids
  tags       = local.tags
}

resource "aws_db_parameter_group" "postgres_ssl" {
  name   = "cloudmart-postgres-ssl"
  family = "postgres16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_db_instance" "users" {
  identifier        = "cloudmart-users"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "cloudmart"
  username = "cloudmart_admin"
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [data.terraform_remote_state.networking.outputs.sg_rds_id]

  parameter_group_name    = aws_db_parameter_group.postgres_ssl.name
  backup_retention_period = 7
  storage_encrypted       = true
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = local.tags
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "cloudmart/user-service/db-credentials"
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    DB_HOST     = aws_db_instance.users.address
    DB_USER     = aws_db_instance.users.username
    DB_PASSWORD = random_password.db.result
  })
}
