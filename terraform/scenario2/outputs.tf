output "mwaa_serverless_workflow_name" {
  value = "${local.name_prefix}-emr-spark"
}

output "mwaa_dags_bucket" {
  value = aws_s3_bucket.mwaa.bucket
}

output "emr_application_id" {
  value = aws_emrserverless_application.spark.id
}

output "emr_application_arn" {
  value = aws_emrserverless_application.spark.arn
}

output "emr_job_role_arn" {
  value = aws_iam_role.emr_job.arn
}
