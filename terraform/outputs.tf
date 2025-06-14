output "n8n_alb_dns_name" {
  description = "The DNS name of the Application Load Balancer for n8n."
  value       = aws_lb.n8n_alb.dns_name
}

output "rds_endpoint" {
  description = "The endpoint of the RDS instance for n8n."
  value       = aws_db_instance.n8n_db.address
}

output "ecr_repository_url" {
  description = "URL of the ECR repository."
  value       = aws_ecr_repository.n8n.repository_url
}