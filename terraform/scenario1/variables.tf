variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "environment" {
  type    = string
  default = "demo"
}

variable "project" {
  type    = string
  default = "devops-agent-demo"
}

variable "lambda_memory_mb" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 256
}

variable "lambda_timeout_sec" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "sqs_visibility_timeout" {
  description = "SQS message visibility timeout in seconds"
  type        = number
  default     = 60
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"
}
