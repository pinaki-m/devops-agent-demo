output "mwaa_environment_arn" {
  value = aws_mwaa_environment.main.arn
}

output "mwaa_webserver_url" {
  value = aws_mwaa_environment.main.webserver_url
}

output "emr_application_id" {
  value = aws_emrserverless_application.spark.id
}

output "emr_application_arn" {
  value = aws_emrserverless_application.spark.arn
}

output "mwaa_dags_bucket" {
  value = aws_s3_bucket.mwaa.bucket
}

output "emr_job_role_arn" {
  value = aws_iam_role.emr_job.arn
}
