locals {
  name_prefix = "${var.project}-${var.environment}"

  azs = [
    "${var.aws_region}a",
    "${var.aws_region}b",
    "${var.aws_region}c",
  ]

  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}
