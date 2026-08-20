# SQS(+DLQ redrive) + FIFO + SNS(+SQS 구독+filter) + EventBridge Scheduler → SQS.
terraform {
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.0" } }
}
provider "aws" { region = var.region }
variable "region" { default = "ap-northeast-2" }
variable "name" { default = "lab-tf-msg" }

# --- SQS + DLQ ---
resource "aws_sqs_queue" "dlq" { name = "${var.name}-dlq" }
resource "aws_sqs_queue" "main" {
  name                       = "${var.name}-main"
  visibility_timeout_seconds = 30
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}
# --- FIFO ---
resource "aws_sqs_queue" "fifo" {
  name                        = "${var.name}.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
}

# --- SNS + SQS 구독 + filter ---
resource "aws_sns_topic" "t" { name = "${var.name}-topic" }
data "aws_iam_policy_document" "sqs_from_sns" {
  statement {
    effect  = "Allow"
    actions = ["SQS:SendMessage"]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    resources = [aws_sqs_queue.main.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.t.arn]
    }
  }
}
resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.id
  policy    = data.aws_iam_policy_document.sqs_from_sns.json
}
resource "aws_sns_topic_subscription" "sub" {
  topic_arn     = aws_sns_topic.t.arn
  protocol      = "sqs"
  endpoint      = aws_sqs_queue.main.arn
  filter_policy = jsonencode({ type = ["order"] })
}

# --- Scheduler → SQS ---
data "aws_iam_policy_document" "sched_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "sched" {
  name               = "${var.name}-sched"
  assume_role_policy = data.aws_iam_policy_document.sched_assume.json
}
resource "aws_iam_role_policy" "sched" {
  name = "send"
  role = aws_iam_role.sched.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["sqs:SendMessage"], Resource = aws_sqs_queue.main.arn }]
  })
}
resource "aws_scheduler_schedule" "s" {
  name = "${var.name}-sched"
  flexible_time_window { mode = "OFF" }
  schedule_expression = "rate(5 minutes)"
  target {
    arn      = aws_sqs_queue.main.arn
    role_arn = aws_iam_role.sched.arn
    input    = "scheduled-tick"
  }
}

output "main_url" { value = aws_sqs_queue.main.url }
output "topic_arn" { value = aws_sns_topic.t.arn }
