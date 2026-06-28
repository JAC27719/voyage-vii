data "aws_caller_identity" "current" {}

locals {
  state_bucket = "${data.aws_caller_identity.current.account_id}-hydra-tfstate-${var.aws_region}"
  oidc_subject = "repo:${var.github_repository}:environment:${var.github_environment}"

  component_permissions = {
    foundation = [
      "ec2:*Vpc*", "ec2:*Subnet*", "ec2:*Route*", "ec2:*InternetGateway*",
      "ec2:*NatGateway*", "ec2:*Address*", "ec2:*SecurityGroup*",
      "ec2:Describe*", "ecr:*", "servicediscovery:*", "logs:*",
    ]
    postgres = [
      "rds:*", "ec2:Describe*", "ec2:*SecurityGroup*", "cloudwatch:*",
      "secretsmanager:DescribeSecret", "secretsmanager:ListSecrets",
    ]
    tigerbeetle = [
      "ec2:Describe*", "ec2:RunInstances", "ec2:TerminateInstances",
      "ec2:CreateTags", "ec2:CreateVolume", "ec2:DeleteVolume",
      "ec2:AttachVolume", "ec2:DetachVolume", "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface", "ec2:AttachNetworkInterface",
      "ec2:DetachNetworkInterface", "ec2:ModifyInstanceAttribute",
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:PassRole",
      "iam:TagRole", "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:List*",
      "logs:*", "cloudwatch:*", "ssm:SendCommand", "ssm:GetCommandInvocation",
      "ssm:DescribeInstanceInformation",
    ]
    api = [
      "ecs:*", "ecr:*", "iam:CreateRole", "iam:DeleteRole", "iam:GetRole",
      "iam:PassRole", "iam:TagRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:GetRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:List*", "logs:*", "apigateway:*",
      "servicediscovery:*", "ec2:Describe*", "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface", "ec2:CreateTags", "secretsmanager:DescribeSecret",
      "cloudwatch:*",
    ]
  }
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = local.state_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1b511abead59c6ce207077c0bf0e0043b1382612",
  ]
}

data "aws_iam_policy_document" "github_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.oidc_subject]
    }
  }
}

resource "aws_iam_role" "deploy" {
  for_each = local.component_permissions

  name               = "hydra-${var.github_environment}-${each.key}-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json
}

data "aws_iam_policy_document" "deploy" {
  for_each = local.component_permissions

  statement {
    sid       = "ComponentDeployment"
    effect    = "Allow"
    actions   = each.value
    resources = ["*"]
  }

  statement {
    sid    = "TerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.terraform_state.arn}/*"]
  }

  statement {
    sid       = "TerraformStateList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.terraform_state.arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  for_each = local.component_permissions

  name   = "hydra-${var.github_environment}-${each.key}-deploy"
  role   = aws_iam_role.deploy[each.key].id
  policy = data.aws_iam_policy_document.deploy[each.key].json
}
