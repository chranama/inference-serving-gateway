output "postgres_endpoint" {
  description = "Postgres endpoint address."
  value       = aws_db_instance.postgres.address
}

output "postgres_port" {
  description = "Postgres port."
  value       = aws_db_instance.postgres.port
}

output "postgres_db_name" {
  description = "Initial Postgres database name."
  value       = aws_db_instance.postgres.db_name
}

output "postgres_master_secret_arn" {
  description = "Secrets Manager ARN for the Postgres master password."
  value       = try(aws_db_instance.postgres.master_user_secret[0].secret_arn, null)
}

output "redis_endpoint" {
  description = "Redis endpoint address."
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  description = "Redis port."
  value       = aws_elasticache_cluster.redis.port
}
