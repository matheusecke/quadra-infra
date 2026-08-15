terraform {
  required_version = "~> 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.57"
    }
  }

  # The bucket is managed in terraform_state.tf, but backend blocks cannot use variables.
  backend "s3" {
    bucket       = "quadra-terraform-state-141145164743"
    key          = "production/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
