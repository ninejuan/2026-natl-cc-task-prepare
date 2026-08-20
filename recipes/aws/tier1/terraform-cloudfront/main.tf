# CloudFront + S3 OAC. 유저는 CF 로만, S3 직접 403.
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
variable "name" { default = "lab-tf-cf" }
data "aws_caller_identity" "cur" {}

resource "aws_s3_bucket" "b" {
  bucket        = "${var.name}-${data.aws_caller_identity.cur.account_id}"
  force_destroy = true
}
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.b.id
  key          = "index.html"
  content      = "<html><body>Cloud Skills 2026 TF</body></html>"
  content_type = "text/html"
}
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
resource "aws_cloudfront_distribution" "d" {
  enabled             = true
  default_root_object = "index.html"
  comment             = var.name
  origin {
    domain_name              = aws_s3_bucket.b.bucket_regional_domain_name
    origin_id                = "s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }
  default_cache_behavior {
    target_origin_id       = "s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate { cloudfront_default_certificate = true }
}
resource "aws_s3_bucket_policy" "b" {
  bucket = aws_s3_bucket.b.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.b.arn}/*"
      Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.d.arn } }
    }]
  })
}
output "domain" { value = aws_cloudfront_distribution.d.domain_name }
output "bucket" { value = aws_s3_bucket.b.id }
