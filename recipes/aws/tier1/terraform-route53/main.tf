# split-view DNS: public zone(54.x) + private zone(172.x), 같은 이름.
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
variable "zone" { default = "lab-tf.internal" }
variable "vpc_id" { description = "private zone 연결 VPC" }

resource "aws_route53_zone" "pub" { name = var.zone }
resource "aws_route53_zone" "priv" {
  name = var.zone
  vpc { vpc_id = var.vpc_id }
}
resource "aws_route53_record" "pub_q1" {
  zone_id = aws_route53_zone.pub.zone_id
  name    = "q1.${var.zone}"
  type    = "A"
  ttl     = 60
  records = ["54.0.0.10"]
}
resource "aws_route53_record" "priv_q1" {
  zone_id = aws_route53_zone.priv.zone_id
  name    = "q1.${var.zone}"
  type    = "A"
  ttl     = 60
  records = ["172.16.0.10"]
}
# weighted 예시
resource "aws_route53_record" "w_blue" {
  zone_id        = aws_route53_zone.pub.zone_id
  name           = "web.${var.zone}"
  type           = "A"
  ttl            = 60
  records        = ["10.0.0.1"]
  set_identifier = "blue"
  weighted_routing_policy { weight = 80 }
}
resource "aws_route53_record" "w_green" {
  zone_id        = aws_route53_zone.pub.zone_id
  name           = "web.${var.zone}"
  type           = "A"
  ttl            = 60
  records        = ["10.0.0.2"]
  set_identifier = "green"
  weighted_routing_policy { weight = 20 }
}
output "public_ns" { value = aws_route53_zone.pub.name_servers }
output "pub_zone_id" { value = aws_route53_zone.pub.zone_id }
