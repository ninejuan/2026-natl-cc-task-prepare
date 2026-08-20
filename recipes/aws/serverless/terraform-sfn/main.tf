# Step Functions state machine + IAM + DynamoDB. 검증된 inventory ASL 을 그대로 로드.
terraform {
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.0" } }
}
provider "aws" { region = var.region }
variable "region" { default = "ap-northeast-2" }
variable "name" { default = "lab-tf-sfn" }

resource "aws_dynamodb_table" "inv" {
  name         = var.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "name"
  attribute {
    name = "name"
    type = "S"
  }
}
resource "aws_dynamodb_table_item" "stock" {
  table_name = aws_dynamodb_table.inv.name
  hash_key   = "name"
  item       = jsonencode({ name = { S = "stock" }, value = { N = "100" } })
}
resource "aws_dynamodb_table_item" "balance" {
  table_name = aws_dynamodb_table.inv.name
  hash_key   = "name"
  item       = jsonencode({ name = { S = "balance" }, value = { N = "1000" } })
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "sfn" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}
resource "aws_iam_role_policy" "ddb" {
  name = "ddb"
  role = aws_iam_role.sfn.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["dynamodb:UpdateItem"], Resource = aws_dynamodb_table.inv.arn }]
  })
}

resource "aws_sfn_state_machine" "sm" {
  name     = var.name
  role_arn = aws_iam_role.sfn.arn
  definition = jsonencode({
    Comment = "sales 만큼 stock 차감·balance 증가 (Lambda 없이 DDB 직접통합)"
    StartAt = "DecStock"
    States = {
      DecStock = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName                 = aws_dynamodb_table.inv.name
          Key                       = { name = { S = "stock" } }
          UpdateExpression          = "SET #v = #v - :s"
          ExpressionAttributeNames  = { "#v" = "value" }
          ExpressionAttributeValues = { ":s" = { "N.$" = "States.Format('{}', $.sales)" } }
        }
        ResultPath = null
        Next       = "IncBalance"
      }
      IncBalance = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName                 = aws_dynamodb_table.inv.name
          Key                       = { name = { S = "balance" } }
          UpdateExpression          = "SET #v = #v + :s"
          ExpressionAttributeNames  = { "#v" = "value" }
          ExpressionAttributeValues = { ":s" = { "N.$" = "States.Format('{}', $.sales)" } }
        }
        End = true
      }
    }
  })
}
output "state_machine_arn" { value = aws_sfn_state_machine.sm.arn }
output "table" { value = aws_dynamodb_table.inv.name }
