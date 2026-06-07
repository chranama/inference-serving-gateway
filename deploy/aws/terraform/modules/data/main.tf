resource "aws_security_group" "postgres" {
  name        = "${var.name_prefix}-postgres"
  description = "Bounded Postgres access for the AWS runtime stack."
  vpc_id      = var.vpc_id

  ingress {
    description = "Postgres from the bounded VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-postgres-sg"
    },
  )
}

resource "aws_security_group" "redis" {
  name        = "${var.name_prefix}-redis"
  description = "Bounded Redis access for the AWS runtime stack."
  vpc_id      = var.vpc_id

  ingress {
    description = "Redis from the bounded VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-redis-sg"
    },
  )
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.name_prefix}-postgres"
  subnet_ids = var.subnet_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-postgres-subnets"
    },
  )
}

resource "aws_db_instance" "postgres" {
  identifier                  = "${var.name_prefix}-postgres"
  engine                      = "postgres"
  engine_version              = var.db_engine_version
  instance_class              = var.db_instance_class
  allocated_storage           = var.db_allocated_storage
  max_allocated_storage       = var.db_max_allocated_storage
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = var.db_name
  username                    = var.db_username
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.postgres.name
  vpc_security_group_ids      = [aws_security_group.postgres.id]
  publicly_accessible         = false
  multi_az                    = false
  backup_retention_period     = var.ephemeral_environment ? 1 : 7
  skip_final_snapshot         = var.ephemeral_environment
  deletion_protection         = !var.ephemeral_environment
  apply_immediately           = true
  auto_minor_version_upgrade  = true

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-postgres"
    },
  )
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.name_prefix}-redis"
  subnet_ids = var.subnet_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-redis-subnets"
    },
  )
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id                 = "${var.name_prefix}-redis"
  engine                     = "redis"
  engine_version             = var.redis_engine_version
  node_type                  = var.redis_node_type
  num_cache_nodes            = 1
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [aws_security_group.redis.id]
  apply_immediately          = true
  auto_minor_version_upgrade = true

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-redis"
    },
  )
}
