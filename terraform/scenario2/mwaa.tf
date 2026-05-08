locals {
  name_prefix = "${var.project}-${var.environment}-s2"
}

data "aws_caller_identity" "current" {}

# ── S3 bucket for DAGs ───────────────────────────────────────────────────────

resource "aws_s3_bucket" "mwaa" {
  bucket = "${local.name_prefix}-mwaa-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "mwaa" {
  bucket = aws_s3_bucket.mwaa.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "mwaa" {
  bucket                  = aws_s3_bucket.mwaa.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Security Group ───────────────────────────────────────────────────────────

resource "aws_security_group" "mwaa" {
  name        = "${local.name_prefix}-mwaa"
  description = "MWAA environment security group"
  vpc_id      = var.vpc_id

  ingress {
    description = "Self-referencing for cluster communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── IAM role ─────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "mwaa_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["airflow.amazonaws.com", "airflow-env.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mwaa" {
  name               = "${local.name_prefix}-mwaa-exec"
  assume_role_policy = data.aws_iam_policy_document.mwaa_assume.json
}

resource "aws_iam_role_policy" "mwaa" {
  name = "mwaa-policy"
  role = aws_iam_role.mwaa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject*", "s3:GetBucket*", "s3:List*"]
        Resource = [aws_s3_bucket.mwaa.arn, "${aws_s3_bucket.mwaa.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:GetLogEvents", "logs:GetLogRecord", "logs:GetLogGroupFields", "logs:GetQueryResults"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:airflow-${local.name_prefix}-*"
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ChangeMessageVisibility", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl", "sqs:ReceiveMessage", "sqs:SendMessage"]
        Resource = "arn:aws:sqs:${var.aws_region}:*:airflow-celery-*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey*", "kms:Encrypt"]
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:ViaService" = ["sqs.${var.aws_region}.amazonaws.com"]
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["emr-serverless:StartJobRun", "emr-serverless:GetJobRun", "emr-serverless:CancelJobRun", "emr-serverless:ListJobRuns"]
        Resource = aws_emrserverless_application.spark.arn
      }
    ]
  })
}

# ── MWAA Environment ─────────────────────────────────────────────────────────

resource "aws_mwaa_environment" "main" {
  name               = local.name_prefix
  airflow_version    = "2.10.3"
  environment_class  = "mw1.small"
  min_webservers     = 2
  max_webservers     = var.mwaa_max_webservers
  execution_role_arn = aws_iam_role.mwaa.arn

  source_bucket_arn    = aws_s3_bucket.mwaa.arn
  dag_s3_path          = "dags/"
  requirements_s3_path = "requirements.txt"

  network_configuration {
    security_group_ids = [aws_security_group.mwaa.id]
    subnet_ids         = slice(var.private_subnet_ids, 0, 2)
  }

  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = "INFO"
    }
    scheduler_logs {
      enabled   = true
      log_level = "INFO"
    }
    task_logs {
      enabled   = true
      log_level = "INFO"
    }
    webserver_logs {
      enabled   = true
      log_level = "INFO"
    }
    worker_logs {
      enabled   = true
      log_level = "INFO"
    }
  }
}
