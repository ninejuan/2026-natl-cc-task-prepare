# Assume Role + External ID + 최소권한 + 세션 1시간 (2026 audit-role 형).
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
provider "aws" { region = var.region }
variable "region" { default = "ap-northeast-2" }
variable "name" { default = "lab-tf-audit" }
variable "external_id" { default = "skills-audit-2026" }
data "aws_caller_identity" "cur" {}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.cur.account_id}:root"]
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
    }
  }
}
resource "aws_iam_role" "audit" {
  name                 = var.name
  assume_role_policy    = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
}
resource "aws_iam_role_policy" "ro" {
  name = "ro"
  role = aws_iam_role.audit.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["dynamodb:DescribeTable", "ec2:DescribeVpcs"], Resource = "*" }]
  })
}
output "role_arn" { value = aws_iam_role.audit.arn }
