data "terraform_remote_state" "foundation" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/foundation.tfstate"
    region = var.aws_region
  }
}

locals {
  name = "hydra-${var.environment}"
}

resource "aws_db_subnet_group" "main" {
  name       = local.name
  subnet_ids = data.terraform_remote_state.foundation.outputs.data_subnet_ids
}

resource "aws_db_instance" "main" {
  identifier = local.name

  engine         = "postgres"
  engine_version = "18.4"
  instance_class = var.instance_class

  db_name                     = "hydra"
  username                    = "hydra_admin"
  manage_master_user_password = true
  port                        = 5432

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [
    data.terraform_remote_state.foundation.outputs.postgres_security_group_id,
  ]
  publicly_accessible = false
  multi_az            = false

  backup_retention_period    = 7
  backup_window              = "06:00-07:00"
  maintenance_window         = "sun:07:00-sun:08:00"
  auto_minor_version_upgrade = true
  apply_immediately          = false

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-final"
  copy_tags_to_snapshot     = true

  performance_insights_enabled = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "${local.name}-postgres-high-cpu"
  alarm_description   = "PostgreSQL CPU has exceeded 80 percent for 15 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  treat_missing_data  = "missing"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "free_storage" {
  alarm_name          = "${local.name}-postgres-low-storage"
  alarm_description   = "PostgreSQL has less than 5 GiB free storage."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "LessThanThreshold"
  threshold           = 5368709120
  treat_missing_data  = "missing"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }
}
