# Lambda + IAM role + DynamoDB + SQS ESM 를 한 번에. crud-booking 핸들러 배포.
#   terraform init && terraform apply -auto-approve
#   terraform destroy -auto-approve
terraform {
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.0" } }
}
provider "aws" { region = var.region }

variable "region" { default = "ap-northeast-2" }
variable "name" { default = "lab-tf-book" }

data "aws_caller_identity" "cur" {}

# --- DynamoDB (GSI 포함) ---
resource "aws_dynamodb_table" "book" {
  name         = var.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "booking_id"
  attribute {
    name = "booking_id"
    type = "S"
  }
  attribute {
    name = "client_id"
    type = "S"
  }
  attribute {
    name = "created_at"
    type = "S"
  }
  global_secondary_index {
    name            = "client-id-created-at-index"
    hash_key        = "client_id"
    range_key       = "created_at"
    projection_type = "ALL"
  }
}

# --- IAM role ---
data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "fn" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}
resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.fn.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "ddb" {
  name = "ddb"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query"], Resource = "*" }]
  })
}

# --- 패키징 + 함수 ---
data "archive_file" "fn" {
  type        = "zip"
  source_file = "${path.module}/../lambda/crud-booking/handler.py"
  output_path = "${path.module}/fn.zip"
}
resource "aws_lambda_function" "fn" {
  function_name    = var.name
  filename         = data.archive_file.fn.output_path
  source_code_hash = data.archive_file.fn.output_base64sha256
  role             = aws_iam_role.fn.arn
  handler          = "handler.handler"
  runtime          = "python3.13"
  timeout          = 10
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.book.name
      GSI_NAME   = "client-id-created-at-index"
    }
  }
}

output "function_name" { value = aws_lambda_function.fn.function_name }
output "table_name" { value = aws_dynamodb_table.book.name }
