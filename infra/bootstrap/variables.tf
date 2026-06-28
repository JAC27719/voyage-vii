variable "aws_region" {
  description = "AWS region containing the state bucket."
  type        = string
  default     = "us-east-1"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume deployment roles."
  type        = string
  default     = "JAC27719/hydra"
}

variable "github_environment" {
  description = "GitHub Environment required by the OIDC trust policy."
  type        = string
  default     = "dev"
}
