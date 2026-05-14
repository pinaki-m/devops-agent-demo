terraform {
  # bucket is supplied at init time:
  #   terraform init -backend-config="bucket=$TF_STATE_BUCKET"
  backend "s3" {
    key            = "scenario4/terraform.tfstate"
    region         = "ap-southeast-2"
    use_lockfile   = true
    encrypt        = true
  }
}
