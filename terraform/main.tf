resource "aws_s3_bucket" "terraform_state" {
  bucket = "quadra-terraform-state-141145164743"

  tags = {
    Project   = "Quadra"
    ManagedBy = "Terraform"
    Purpose   = "Terraform State"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}