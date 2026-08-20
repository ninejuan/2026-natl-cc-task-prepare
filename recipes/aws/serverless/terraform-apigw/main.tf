# API Gateway REST + DynamoDB 직접통합(AWS Service Proxy, Lambda 없음) + VTL.
# 2025 inventory 형: GET /inventory?item=balance -> 1000 (raw), mysecret* -> 403.
terraform {
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.0" } }
}
provider "aws" { region = var.region }
variable "region" { default = "ap-northeast-2" }
variable "name" { default = "lab-tf-inv" }

# --- DynamoDB + 시드 ---
resource "aws_dynamodb_table" "inv" {
  name         = var.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "name"
  attribute {
    name = "name"
    type = "S"
  }
}
resource "aws_dynamodb_table_item" "balance" {
  table_name = aws_dynamodb_table.inv.name
  hash_key   = "name"
  item       = jsonencode({ name = { S = "balance" }, value = { N = "1000" } })
}
resource "aws_dynamodb_table_item" "stock" {
  table_name = aws_dynamodb_table.inv.name
  hash_key   = "name"
  item       = jsonencode({ name = { S = "stock" }, value = { N = "100" } })
}

# --- API GW 가 DDB GetItem ---
data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "agw" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}
resource "aws_iam_role_policy" "ddb" {
  name = "ddb"
  role = aws_iam_role.agw.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["dynamodb:GetItem"], Resource = aws_dynamodb_table.inv.arn }]
  })
}

# --- REST API ---
resource "aws_api_gateway_rest_api" "api" { name = var.name }
resource "aws_api_gateway_resource" "inv" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "inventory"
}
resource "aws_api_gateway_method" "get" {
  rest_api_id      = aws_api_gateway_rest_api.api.id
  resource_id      = aws_api_gateway_resource.inv.id
  http_method      = "GET"
  authorization    = "NONE"
  request_parameters = { "method.request.querystring.item" = false }
}
resource "aws_api_gateway_integration" "ddb" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.inv.id
  http_method             = aws_api_gateway_method.get.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.region}:dynamodb:action/GetItem"
  credentials             = aws_iam_role.agw.arn
  request_templates = {
    "application/json" = <<VTL
#set($item = $input.params('item'))
#if($item.startsWith("mysecret"))
#set($context.responseOverride.status = 403)
{}
#else
{ "TableName": "${aws_dynamodb_table.inv.name}", "Key": { "name": { "S": "$item" } } }
#end
VTL
  }
}
resource "aws_api_gateway_method_response" "ok" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.inv.id
  http_method = aws_api_gateway_method.get.http_method
  status_code = "200"
}
resource "aws_api_gateway_integration_response" "ok" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.inv.id
  http_method = aws_api_gateway_method.get.http_method
  status_code = aws_api_gateway_method_response.ok.status_code
  response_templates = {
    "application/json" = "$input.path('$.Item.value.N')"
  }
  depends_on = [aws_api_gateway_integration.ddb]
}
resource "aws_api_gateway_deployment" "d" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers    = { redeploy = sha1(jsonencode([aws_api_gateway_integration.ddb, aws_api_gateway_integration_response.ok])) }
  lifecycle { create_before_destroy = true }
}
resource "aws_api_gateway_stage" "v1" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.d.id
  stage_name    = "v1"
}
output "url" { value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com/v1/inventory" }
