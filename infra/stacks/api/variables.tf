variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "state_bucket" {
  type = string
}

variable "image_tag" {
  description = "Immutable Git commit SHA shared by the API and seeder images."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.image_tag))
    error_message = "image_tag must be a Git commit SHA."
  }
}
