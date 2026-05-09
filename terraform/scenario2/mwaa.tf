locals {
  name_prefix  = "${var.project}-${var.environment}-s2"
  aws_cli      = "/usr/local/Cellar/awscli/2.34.45/libexec/bin/aws"
  workflow_key = "workflows/emr-spark-job.yaml"
}

data "aws_caller_identity" "current" {}

# ── S3 bucket (DAGs + workflow definitions + EMR logs) ───────────────────────

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

# ── Workflow definition uploaded to S3 ───────────────────────────────────────

resource "aws_s3_object" "workflow" {
  bucket = aws_s3_bucket.mwaa.id
  key    = local.workflow_key
  source = "${path.module}/../../src/scenario2/workflow.yaml"
  etag   = filemd5("${path.module}/../../src/scenario2/workflow.yaml")
}

# ── Security Group ───────────────────────────────────────────────────────────

resource "aws_security_group" "mwaa" {
  name        = "${local.name_prefix}-mwaa"
  description = "MWAA Serverless workflow security group"
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
      identifiers = ["airflow-serverless.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mwaa" {
  name               = "${local.name_prefix}-mwaa-exec"
  assume_role_policy = data.aws_iam_policy_document.mwaa_assume.json
}

resource "aws_iam_role_policy" "mwaa" {
  name = "mwaa-serverless-policy"
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
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/mwaa-serverless/*"
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["emr-serverless:StartJobRun", "emr-serverless:GetJobRun", "emr-serverless:CancelJobRun", "emr-serverless:ListJobRuns"]
        Resource = aws_emrserverless_application.spark.arn
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.emr_job.arn
      }
    ]
  })
}

# ── MWAA Serverless workflow (via AWS CLI — no Terraform resource yet) ────────

resource "null_resource" "mwaa_serverless_workflow" {
  triggers = {
    workflow_etag    = aws_s3_object.workflow.etag
    role_arn         = aws_iam_role.mwaa.arn
    security_groups  = aws_security_group.mwaa.id
    subnets          = join(",", slice(var.private_subnet_ids, 0, 2))
    workflow_name    = "${local.name_prefix}-emr-spark"
  }

  provisioner "local-exec" {
    command = <<-EOF
      cat > /tmp/${local.name_prefix}-workflow.json <<'PAYLOAD'
      ${jsonencode({
        Name = "${local.name_prefix}-emr-spark"
        DefinitionS3Location = {
          Bucket    = aws_s3_bucket.mwaa.bucket
          ObjectKey = local.workflow_key
          VersionId = aws_s3_object.workflow.version_id
        }
        RoleArn       = aws_iam_role.mwaa.arn
        EngineVersion = 1
        TriggerMode   = "manual_only"
        NetworkConfiguration = {
          SecurityGroupIds = [aws_security_group.mwaa.id]
          SubnetIds        = slice(var.private_subnet_ids, 0, 2)
        }
        Tags = {
          Project     = var.project
          Environment = var.environment
        }
      })}
      PAYLOAD
      ${local.aws_cli} mwaa-serverless create-workflow \
        --region ${var.aws_region} \
        --cli-input-json file:///tmp/${local.name_prefix}-workflow.json
    EOF
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOF
      /usr/local/Cellar/awscli/2.34.45/libexec/bin/aws mwaa-serverless delete-workflow \
        --name "${self.triggers.workflow_name}" \
        --region ap-southeast-2 || true
    EOF
  }

  depends_on = [
    aws_s3_object.workflow,
    aws_iam_role_policy.mwaa,
  ]
}
