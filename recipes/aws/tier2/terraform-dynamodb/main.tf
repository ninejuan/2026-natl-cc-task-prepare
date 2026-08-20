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
variable "name" { default = "lab-tf-ddb" }

resource "aws_dynamodb_table" "t" {
  name         = var.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }
  attribute {
    name = "sk"
    type = "S"
  }
  attribute {
    name = "gsipk"
    type = "S"
  }
  attribute {
    name = "lsi_sk"
    type = "N"
  }

  global_secondary_index {
    name            = "gsi1"
    hash_key        = "gsipk"
    projection_type = "ALL"
  }
  local_secondary_index {
    name            = "lsi1"
    range_key       = "lsi_sk"
    projection_type = "ALL"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
  point_in_time_recovery { enabled = true }
  deletion_protection_enabled = false
}
output "table" { value = aws_dynamodb_table.t.name }
