variable "aws_region" {
  description = "The AWS region to deploy resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name for the n8n project, used as a prefix for resources."
  type        = string
  default     = "n8n"
}

variable "db_name" {
  description = "Name of the RDS database."
  type        = string
  default     = "n8ndb"
}

variable "db_user" {
  description = "Username for the RDS database."
  type        = string
  default     = "n8nadmin"
}

# IMPORTANT: Do not hardcode sensitive values here.
# These will be fetched from Secrets Manager.
variable "db_password" {
  description = "Password for the RDS database."
  type        = string
  sensitive   = true
}

variable "n8n_encryption_key" {
  description = "Encryption key for n8n workflows."
  type        = string
  sensitive   = true
}

variable "container_image_tag" {
  description = "Docker image tag for n8n."
  type        = string
  default     = "latest" # Will be overridden by GitHub Actions
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type         = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}