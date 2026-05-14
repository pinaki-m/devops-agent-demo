# Dead-letter queue
resource "aws_sqs_queue" "events_dlq" {
  name                      = "${local.name_prefix}-events-dlq"
  message_retention_seconds = 1209600 # 14 days
}

resource "aws_sqs_queue" "events" {
  name                       = "${local.name_prefix}-events"
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = 86400 # 1 day

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.events_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_policy" "events" {
  queue_url = aws_sqs_queue.events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.lambda_exec.arn }
      Action    = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource  = aws_sqs_queue.events.arn
    }]
  })
}
