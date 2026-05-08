output "sagemaker_endpoint_name" {
  value = aws_sagemaker_endpoint.main.name
}

output "sagemaker_endpoint_arn" {
  value = aws_sagemaker_endpoint.main.arn
}

output "model_artefacts_bucket" {
  value = aws_s3_bucket.model_artefacts.bucket
}

output "sagemaker_role_arn" {
  value = aws_iam_role.sagemaker_exec.arn
}
