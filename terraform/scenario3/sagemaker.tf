locals {
  name_prefix = "${var.project}-${var.environment}-s3"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── S3 bucket for model artefacts ────────────────────────────────────────────

resource "aws_s3_bucket" "model_artefacts" {
  bucket = "${local.name_prefix}-model-artefacts-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "model_artefacts" {
  bucket = aws_s3_bucket.model_artefacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "model_artefacts" {
  bucket                  = aws_s3_bucket.model_artefacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── IAM role ─────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "sagemaker_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sagemaker_exec" {
  name               = "${local.name_prefix}-sagemaker-exec"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume.json
}

resource "aws_iam_role_policy_attachment" "sagemaker_full" {
  role       = aws_iam_role.sagemaker_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_iam_role_policy" "sagemaker_s3" {
  name = "model-artefacts-s3"
  role = aws_iam_role.sagemaker_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.model_artefacts.arn, "${aws_s3_bucket.model_artefacts.arn}/*"]
    }]
  })
}

# ── SageMaker Model ───────────────────────────────────────────────────────────
# Using a pre-built SKLearn container from ECR. Substitute model_data_url after
# running the training job or uploading a model.tar.gz to S3.

resource "aws_sagemaker_model" "main" {
  name               = "${local.name_prefix}-${var.model_name}"
  execution_role_arn = aws_iam_role.sagemaker_exec.arn

  primary_container {
    # ap-southeast-2 SKLearn 1.2 inference image
    image          = "544295431143.dkr.ecr.${var.aws_region}.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3"
    model_data_url = "s3://${aws_s3_bucket.model_artefacts.bucket}/models/${var.model_name}/model.tar.gz"
    environment = {
      SAGEMAKER_PROGRAM = "inference.py"
    }
  }
}

# ── Endpoint Configuration ────────────────────────────────────────────────────

resource "aws_sagemaker_endpoint_configuration" "main" {
  name = "${local.name_prefix}-endpoint-config"

  production_variants {
    variant_name           = "AllTraffic"
    model_name             = aws_sagemaker_model.main.name
    instance_type          = var.endpoint_instance_type
    initial_instance_count = var.endpoint_instance_count
  }

  data_capture_config {
    enable_capture              = true
    initial_sampling_percentage = 10
    destination_s3_uri          = "s3://${aws_s3_bucket.model_artefacts.bucket}/data-capture"

    capture_options {
      capture_mode = "Input"
    }
    capture_options {
      capture_mode = "Output"
    }
  }
}

# ── Endpoint ──────────────────────────────────────────────────────────────────

resource "aws_sagemaker_endpoint" "main" {
  name                 = "${local.name_prefix}-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.main.name
}

# ── CloudWatch alarms ────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "endpoint_4xx" {
  alarm_name          = "${local.name_prefix}-endpoint-4xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Invocation4XXErrors"
  namespace           = "AWS/SageMaker"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "SageMaker endpoint 4xx error rate elevated"

  dimensions = {
    EndpointName = aws_sagemaker_endpoint.main.name
    VariantName  = "AllTraffic"
  }
}

resource "aws_cloudwatch_metric_alarm" "endpoint_5xx" {
  alarm_name          = "${local.name_prefix}-endpoint-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Invocation5XXErrors"
  namespace           = "AWS/SageMaker"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "SageMaker endpoint 5xx errors detected"

  dimensions = {
    EndpointName = aws_sagemaker_endpoint.main.name
    VariantName  = "AllTraffic"
  }
}
