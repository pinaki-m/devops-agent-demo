data "aws_caller_identity" "current" {}

# ── IAM ──────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${local.name_prefix}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_exec" {
  name = "scenario1-lambda-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:SendMessage"]
        Resource = [aws_sqs_queue.events.arn, aws_sqs_queue.events_dlq.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.events.arn
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/cloudops/slack/*"
      }
    ]
  })
}

# ── Function package ─────────────────────────────────────────────────────────

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.root}/../../src/scenario1"
  output_path = "${path.root}/../../src/scenario1/lambda.zip"
}

# ── CloudWatch Log Group ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}-processor"
  retention_in_days = 7
}

# ── Lambda function ──────────────────────────────────────────────────────────

resource "aws_lambda_function" "processor" {
  function_name    = "${local.name_prefix}-processor"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  memory_size      = var.lambda_memory_mb
  timeout          = var.lambda_timeout_sec
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE     = aws_dynamodb_table.events.name
      SQS_QUEUE_URL      = aws_sqs_queue.events.url
      SLACK_SSM_PREFIX   = "/cloudops/slack"
      AWS_ACCOUNT_ID     = data.aws_caller_identity.current.account_id
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# ── SQS → Lambda trigger ─────────────────────────────────────────────────────

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn                   = aws_sqs_queue.events.arn
  function_name                      = aws_lambda_function.processor.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  enabled                            = true
}
