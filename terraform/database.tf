resource "aws_db_subnet_group" "main" {
  name = "${local.name_prefix}-db-subnet-group"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id,
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-db"

  engine         = "postgres"
  engine_version = "16.14"
  # Avoids silent Extended Support charges; the major version must be upgraded
  # before PostgreSQL 16 leaves standard support.
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"
  instance_class           = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "quadra"
  username = "quadra_admin"
  port     = 5432

  manage_master_user_password         = true
  iam_database_authentication_enabled = false

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  parameter_group_name = "default.postgres16"

  # One day is the current AWS Free Plan limit, not the intended long-term retention.
  backup_retention_period  = 1
  backup_window            = "06:00-06:30"
  delete_automated_backups = true
  copy_tags_to_snapshot    = true

  maintenance_window          = "sun:07:00-sun:08:00"
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false
  apply_immediately           = false

  # Keep database observability within the current low-cost scope: seven days of
  # Database Insights, without Enhanced Monitoring or continuous log exports.
  database_insights_mode                = "standard"
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  monitoring_interval                   = 0
  enabled_cloudwatch_logs_exports       = []

  # Native RDS protection is the single deletion switch; lifecycle.prevent_destroy
  # is intentionally not duplicated here.
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name_prefix}-db-final"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db"
  })
}
