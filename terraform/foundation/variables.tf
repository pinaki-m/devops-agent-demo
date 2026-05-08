variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "demo"
}

variable "project" {
  description = "Project name used in resource naming"
  type        = string
  default     = "devops-agent-demo"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "github_org" {
  description = "GitHub organisation / username owning the repo"
  type        = string
  default     = "pinaki-m"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "devops-agent-demo"
}
