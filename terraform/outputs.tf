output "terraform_state_bucket_name" {
  description = "Name of the S3 bucket used to store Terraform state"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "vpc_id" {
  description = "ID of the Quadra VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets used by internet-facing resources"
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "private_subnet_ids" {
  description = "IDs of the private subnets used by the database"
  value       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

output "alb_security_group_id" {
  description = "ID of the Application Load Balancer security group"
  value       = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  description = "ID of the ECS tasks security group"
  value       = aws_security_group.ecs.id
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "api_ecr_repository_url" {
  description = "URL of the shared ECR repository for the Quadra API"
  value       = aws_ecr_repository.api.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "api_log_group_name" {
  description = "Name of the CloudWatch log group for the Quadra API"
  value       = aws_cloudwatch_log_group.api.name
}

output "database_identifier" {
  description = "Identifier of the RDS PostgreSQL instance"
  value       = aws_db_instance.main.identifier
}

output "database_endpoint" {
  description = "Private endpoint and port of the RDS PostgreSQL instance"
  value       = aws_db_instance.main.endpoint
}

output "database_master_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the RDS master credentials"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "route53_name_servers" {
  description = "Name servers to configure for appquadra.com.br at Registro.br"
  value       = aws_route53_zone.main.name_servers
}

output "api_url" {
  description = "Public HTTPS URL of the Quadra API"
  value       = "https://api.appquadra.com.br"
}

output "alb_dns_name" {
  description = "AWS DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "ecs_service_name" {
  description = "Name of the Quadra API ECS service"
  value       = aws_ecs_service.api.name
}

output "api_task_definition_family" {
  description = "Family of the Quadra API ECS task definition"
  value       = aws_ecs_task_definition.api.family
}
