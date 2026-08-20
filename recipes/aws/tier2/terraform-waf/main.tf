# WAF WebACL (REGIONAL): managed rule + rate limit + custom 403.
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
variable "name" { default = "lab-tf-waf" }

resource "aws_wafv2_web_acl" "acl" {
  name  = var.name
  scope = "REGIONAL" # CloudFront 면 CLOUDFRONT + provider us-east-1
  default_action {
    allow {}
  }

  custom_response_body {
    key          = "blocked"
    content      = "Request blocked by Skills WAF"
    content_type = "TEXT_PLAIN"
  }

  rule {
    name     = "common"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "common"
    }
  }
  rule {
    name     = "ratelimit"
    priority = 2
    action {
      block {
        custom_response {
          response_code            = 403
          custom_response_body_key = "blocked"
        }
      }
    }
    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "ratelimit"
    }
  }
  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
  }
}
output "acl_arn" { value = aws_wafv2_web_acl.acl.arn }
