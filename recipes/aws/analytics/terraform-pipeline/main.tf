# 실시간 파이프라인: Kinesis → Firehose → S3(동적 파티셔닝) + Athena(projection 테이블).
terraform {
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.0" } }
}
provider "aws" { region = var.region }
variable "region" { default = "ap-northeast-2" }
variable "name" { default = "lab-tf-pipe" }
data "aws_caller_identity" "cur" {}

resource "aws_kinesis_stream" "s" {
  name        = var.name
  stream_mode_details { stream_mode = "ON_DEMAND" }
}

resource "aws_s3_bucket" "b" {
  bucket        = "${var.name}-${data.aws_caller_identity.cur.account_id}"
  force_destroy = true
}

data "aws_iam_policy_document" "fh_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "fh" {
  name               = "${var.name}-fh"
  assume_role_policy = data.aws_iam_policy_document.fh_assume.json
}
resource "aws_iam_role_policy" "fh" {
  name = "p"
  role = aws_iam_role.fh.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket", "s3:AbortMultipartUpload"], Resource = [aws_s3_bucket.b.arn, "${aws_s3_bucket.b.arn}/*"] },
      { Effect = "Allow", Action = ["kinesis:DescribeStream", "kinesis:GetShardIterator", "kinesis:GetRecords", "kinesis:ListShards"], Resource = aws_kinesis_stream.s.arn }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "fh" {
  name        = var.name
  destination = "extended_s3"
  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.s.arn
    role_arn           = aws_iam_role.fh.arn
  }
  extended_s3_configuration {
    role_arn            = aws_iam_role.fh.arn
    bucket_arn          = aws_s3_bucket.b.arn
    buffering_size      = 64
    buffering_interval  = 60
    prefix              = "events/dt=!{partitionKeyFromQuery:dt}/"
    error_output_prefix = "errors/"
    dynamic_partitioning_configuration { enabled = "true" }
    processing_configuration {
      enabled = "true"
      processors {
        type = "MetadataExtraction"
        parameters {
          parameter_name  = "JsonParsingEngine"
          parameter_value = "JQ-1.6"
        }
        parameters {
          parameter_name  = "MetadataExtractionQuery"
          parameter_value = "{dt:.dt}"
        }
      }
    }
  }
}

resource "aws_athena_workgroup" "wg" {
  name          = var.name
  force_destroy = true
  configuration {
    result_configuration { output_location = "s3://${aws_s3_bucket.b.id}/athena-results/" }
  }
}
resource "aws_glue_catalog_database" "db" { name = replace(var.name, "-", "_") }

output "stream" { value = aws_kinesis_stream.s.name }
output "bucket" { value = aws_s3_bucket.b.id }
output "workgroup" { value = aws_athena_workgroup.wg.name }
output "database" { value = aws_glue_catalog_database.db.name }
