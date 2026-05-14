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

variable "vpc_id" {
  description = "VPC ID from foundation stack"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from foundation stack"
  type        = list(string)
}

variable "emr_release_label" {
  description = "EMR Serverless release label"
  type        = string
  default     = "emr-7.3.0"
}
