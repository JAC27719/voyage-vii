terraform {
  required_version = "~> 1.12"

  backend "s3" {
    key          = "dev/postgres.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "hydra"
      Environment = var.environment
      Component   = "postgres"
      ManagedBy   = "terraform"
    }
  }
}
