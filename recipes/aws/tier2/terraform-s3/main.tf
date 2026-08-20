# S3: 버전관리 + SSE + PAB + 정적 웹호스팅. v6 는 설정마다 별도 리소스.
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
variable "name" { default = "lab-tf-s3" }
data "aws_caller_identity" "cur" {}

resource "aws_s3_bucket" "b" {
  bucket        = "${var.name}-${data.aws_caller_identity.cur.account_id}"
  force_destroy = true
}
resource "aws_s3_bucket_versioning" "v" {
  bucket = aws_s3_bucket.b.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "e" {
  bucket = aws_s3_bucket.b.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
    bucket_key_enabled = true
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "l" {
  bucket = aws_s3_bucket.b.id
  rule {
    id     = "expire-tmp"
    status = "Enabled"
    filter { prefix = "tmp/" }
    expiration { days = 7 }
    noncurrent_version_expiration { noncurrent_days = 3 }
  }
}
# 정적 웹호스팅 (별도 버킷 — 퍼블릭)
resource "aws_s3_bucket" "web" {
  bucket        = "${var.name}-web-${data.aws_caller_identity.cur.account_id}"
  force_destroy = true
}
resource "aws_s3_bucket_public_access_block" "web" {
  bucket                  = aws_s3_bucket.web.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
resource "aws_s3_bucket_website_configuration" "web" {
  bucket = aws_s3_bucket.web.id
  index_document { suffix = "index.html" }
  error_document { key = "error.html" }
}
resource "aws_s3_object" "idx" {
  bucket       = aws_s3_bucket.web.id
  key          = "index.html"
  content      = "<h1>Cloud Skills 2026 S3</h1>"
  content_type = "text/html"
}
resource "aws_s3_bucket_policy" "web" {
  bucket     = aws_s3_bucket.web.id
  depends_on = [aws_s3_bucket_public_access_block.web]
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = "*", Action = "s3:GetObject", Resource = "${aws_s3_bucket.web.arn}/*" }]
  })
}
output "web_endpoint" { value = aws_s3_bucket_website_configuration.web.website_endpoint }
