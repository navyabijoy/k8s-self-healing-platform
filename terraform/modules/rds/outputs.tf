output "db_endpoint" {
  description = "The hostname of the RDS instance — used by the app to connect"
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "Port the PostgreSQL DB listens on (always 5432)"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Name of the database inside PostgreSQL"
  value       = aws_db_instance.main.db_name
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials"
  value       = aws_secretsmanager_secret.db_password.arn
}
