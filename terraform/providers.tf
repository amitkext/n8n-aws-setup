terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "your-n8n-terraform-state" # Replace with your S3 bucket name
    key            = "n8n/terraform.tfstate"
    region         = "us-east-1" # Your desired AWS region
    encrypt        = true
    dynamodb_table = "your-n8n-terraform-state" # Replace with your DynamoDB table name
  }
}

provider "aws" {
  region = var.aws_region
}