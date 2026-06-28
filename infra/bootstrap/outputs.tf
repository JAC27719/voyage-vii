output "state_bucket" {
  description = "Set this as the GitHub repository variable TF_STATE_BUCKET."
  value       = aws_s3_bucket.terraform_state.id
}

output "deployment_role_arns" {
  description = "Set these values as the corresponding GitHub repository variables."
  value       = { for name, role in aws_iam_role.deploy : name => role.arn }
}
