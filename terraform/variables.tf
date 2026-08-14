variable "aws_region" {
  description = "AWS region where the Quadra infrastructure is provisioned"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name used for resource naming and tagging"
  type        = string
  default     = "production"
}