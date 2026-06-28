data "terraform_remote_state" "foundation" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/foundation.tfstate"
    region = var.aws_region
  }
}

data "aws_ssm_parameter" "amazon_linux" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_subnet" "selected" {
  id = data.terraform_remote_state.foundation.outputs.application_subnet_ids[0]
}

locals {
  name = "hydra-${var.environment}-tigerbeetle"
}

resource "aws_iam_role" "instance" {
  name = local.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "main" {
  name = local.name
  role = aws_iam_role.instance.name
}

resource "aws_network_interface" "main" {
  subnet_id = data.aws_subnet.selected.id
  security_groups = [
    data.terraform_remote_state.foundation.outputs.tigerbeetle_security_group_id,
  ]

  tags = { Name = local.name }
}

resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.selected.availability_zone
  size              = 20
  type              = "gp3"
  encrypted         = true

  tags = { Name = "${local.name}-data" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "main" {
  name              = "/hydra/${var.environment}/tigerbeetle"
  retention_in_days = 14
}

resource "aws_instance" "main" {
  ami                  = data.aws_ssm_parameter.amazon_linux.value
  instance_type        = var.instance_type
  iam_instance_profile = aws_iam_instance_profile.main.name

  network_interface {
    network_interface_id = aws_network_interface.main.id
    device_index         = 0
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 10
  }

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    cluster_id          = var.cluster_id
    data_volume_id      = aws_ebs_volume.data.id
    log_group_name      = aws_cloudwatch_log_group.main.name
    region              = var.aws_region
    tigerbeetle_version = var.tigerbeetle_version
  })
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = { Name = local.name }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.main.id

  stop_instance_before_detaching = true
}

resource "aws_cloudwatch_metric_alarm" "instance_status" {
  alarm_name          = "${local.name}-instance-status"
  alarm_description   = "TigerBeetle EC2 instance has failed its status check."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = aws_instance.main.id
  }
}

resource "aws_cloudwatch_log_metric_filter" "service_failure" {
  name           = "${local.name}-service-failure"
  log_group_name = aws_cloudwatch_log_group.main.name
  pattern        = "\"hydra-service-failure\""

  metric_transformation {
    name      = "TigerBeetleServiceFailure"
    namespace = "Hydra/${var.environment}"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "service_failure" {
  alarm_name          = "${local.name}-service-failure"
  alarm_description   = "TigerBeetle systemd service failed."
  namespace           = "Hydra/${var.environment}"
  metric_name         = "TigerBeetleServiceFailure"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
}
