terraform {
  backend "s3" {
    bucket         = "tfstate-gdarslan-infralab-2026-03-prod"
    key            = "terraform123/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}