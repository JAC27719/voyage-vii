data "terraform_remote_state" "foundation" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/foundation.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "postgres" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/postgres.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "tigerbeetle" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/tigerbeetle.tfstate"
    region = var.aws_region
  }
}

locals {
  name          = "hydra-${var.environment}"
  api_image     = "${data.terraform_remote_state.foundation.outputs.api_repository_url}:${var.image_tag}"
  seeder_image  = "${data.terraform_remote_state.foundation.outputs.seeder_repository_url}:${var.image_tag}"
  pg_secret_arn = data.terraform_remote_state.postgres.outputs.master_secret_arn

  common_environment = [
    {
      name  = "Postgres__Host"
      value = data.terraform_remote_state.postgres.outputs.endpoint
    },
    {
      name  = "Postgres__Port"
      value = tostring(data.terraform_remote_state.postgres.outputs.port)
    },
    {
      name  = "Postgres__Database"
      value = data.terraform_remote_state.postgres.outputs.database_name
    },
    {
      name  = "TigerBeetle__ClusterId"
      value = data.terraform_remote_state.tigerbeetle.outputs.cluster_id
    },
    {
      name  = "TigerBeetle__Addresses"
      value = "${data.terraform_remote_state.tigerbeetle.outputs.private_ip}:3000"
    },
  ]

  common_secrets = [
    {
      name      = "Postgres__Username"
      valueFrom = "${local.pg_secret_arn}:username::"
    },
    {
      name      = "Postgres__Password"
      valueFrom = "${local.pg_secret_arn}:password::"
    },
  ]
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/hydra/${var.environment}/api"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "seeder" {
  name              = "/hydra/${var.environment}/seeder"
  retention_in_days = 14
}

resource "aws_iam_role" "execution" {
  name = "${local.name}-ecs-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "secret" {
  name = "read-postgres-secret"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = local.pg_secret_arn
    }]
  })
}

resource "aws_iam_role" "task" {
  name = "${local.name}-ecs-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_ecs_cluster" "main" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${local.name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = local.api_image
      essential = true
      portMappings = [{
        name          = "http"
        containerPort = 8080
        hostPort      = 8080
        protocol      = "tcp"
      }]
      environment = concat(local.common_environment, [
        {
          name  = "ASPNETCORE_HTTP_PORTS"
          value = "8080"
        },
      ])
      secrets = local.common_secrets
      healthCheck = {
        command     = ["CMD-SHELL", "curl --fail --silent http://127.0.0.1:8080/health/live || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.api.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "api"
        }
      }
    },
  ])
}

resource "aws_ecs_task_definition" "seeder" {
  family                   = "${local.name}-seeder"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name        = "seeder"
      image       = local.seeder_image
      essential   = true
      environment = local.common_environment
      secrets     = local.common_secrets
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.seeder.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "seeder"
        }
      }
    },
  ])
}

resource "aws_service_discovery_service" "api" {
  name = "api"

  dns_config {
    namespace_id   = data.terraform_remote_state.foundation.outputs.service_discovery_namespace_id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
  }
}

resource "aws_ecs_service" "api" {
  name            = "api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = data.terraform_remote_state.foundation.outputs.application_subnet_ids
    security_groups  = [data.terraform_remote_state.foundation.outputs.api_security_group_id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.api.arn
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_apigatewayv2_vpc_link" "api" {
  name               = local.name
  subnet_ids         = data.terraform_remote_state.foundation.outputs.application_subnet_ids
  security_group_ids = [data.terraform_remote_state.foundation.outputs.api_security_group_id]
}

resource "aws_apigatewayv2_api" "api" {
  name          = local.name
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = aws_service_discovery_service.api.arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.api.id
  payload_format_version = "1.0"
  timeout_milliseconds   = 30000
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_cloudwatch_metric_alarm" "api_errors" {
  alarm_name          = "${local.name}-api-5xx"
  alarm_description   = "Hydra API Gateway is returning server errors."
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = aws_apigatewayv2_api.api.id
    Stage = aws_apigatewayv2_stage.default.name
  }
}
