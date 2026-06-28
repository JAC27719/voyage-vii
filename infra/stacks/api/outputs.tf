output "api_url" {
  value = aws_apigatewayv2_api.api.api_endpoint
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "api_service_name" {
  value = aws_ecs_service.api.name
}

output "seeder_task_definition_arn" {
  value = aws_ecs_task_definition.seeder.arn
}

output "application_subnet_ids" {
  value = data.terraform_remote_state.foundation.outputs.application_subnet_ids
}

output "api_security_group_id" {
  value = data.terraform_remote_state.foundation.outputs.api_security_group_id
}
