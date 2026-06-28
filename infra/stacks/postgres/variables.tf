variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "state_bucket" {
  description = "S3 bucket containing the independent Hydra Terraform states."
  type        = string
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}
