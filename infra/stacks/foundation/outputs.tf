output "vpc_id" {
  value = aws_vpc.main.id
}

output "application_subnet_ids" {
  value = values(aws_subnet.application)[*].id
}

output "data_subnet_ids" {
  value = values(aws_subnet.data)[*].id
}

output "api_security_group_id" {
  value = aws_security_group.api.id
}

output "postgres_security_group_id" {
  value = aws_security_group.postgres.id
}

output "tigerbeetle_security_group_id" {
  value = aws_security_group.tigerbeetle.id
}

output "service_discovery_namespace_id" {
  value = aws_service_discovery_private_dns_namespace.main.id
}

output "api_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "seeder_repository_url" {
  value = aws_ecr_repository.seeder.repository_url
}
