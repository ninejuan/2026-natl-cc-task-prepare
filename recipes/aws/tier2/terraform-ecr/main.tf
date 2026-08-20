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
variable "name" { default = "lab-tf-ecr" }

resource "aws_ecr_repository" "r" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  force_delete = true
}
resource "aws_ecr_lifecycle_policy" "l" {
  repository = aws_ecr_repository.r.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "untagged 1d"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 1 }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "keep last 10"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
        action       = { type = "expire" }
      }
    ]
  })
}
output "url" { value = aws_ecr_repository.r.repository_url }
