locals {
  name_prefix = "quadra-${var.environment}"

  common_tags = {
    Project     = "Quadra"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
