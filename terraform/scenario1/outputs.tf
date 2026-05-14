output "lambda_function_name" {
  value = aws_lambda_function.processor.function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.processor.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.events.url
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.events.arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.events.name
}
