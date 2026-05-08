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

variable "model_name" {
  description = "SageMaker model name (pre-built image tag)"
  type        = string
  default     = "sklearn-iris-classifier"
}

variable "endpoint_instance_type" {
  description = "SageMaker real-time endpoint instance type"
  type        = string
  default     = "ml.t2.medium"
}

variable "endpoint_instance_count" {
  description = "Number of endpoint instances"
  type        = number
  default     = 1
}
