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

variable "instance_type" {
  type    = string
  default = "t3.large"
}

variable "tigerbeetle_version" {
  type    = string
  default = "0.17.5"
}

variable "cluster_id" {
  description = "Stable, non-secret decimal UInt128 cluster identifier."
  type        = string
  default     = "2026062701"

  validation {
    condition     = can(regex("^[0-9]+$", var.cluster_id))
    error_message = "cluster_id must be a decimal unsigned integer."
  }
}
