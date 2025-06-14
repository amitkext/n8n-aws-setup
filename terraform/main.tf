# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true # Required for ALB in public subnets

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index}"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index}"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway (for outbound access from private subnets)
resource "aws_eip" "nat_gateway" {
  vpc        = true
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat_gateway.id
  subnet_id     = aws_subnet.public[0].id # Place NAT Gateway in one public subnet

  tags = {
    Name = "${var.project_name}-nat-gateway"
  }
}

# Route Table for Private Subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ECR Repository
resource "aws_ecr_repository" "n8n" {
  name = "n8n-n8n-repo"
  # name = "${var.project_name}-n8n-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-ecr-repo"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "n8n" {
  name = "${var.project_name}-cluster"

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Role (for n8n to access Secrets Manager)
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "n8n_secrets_policy" {
  name        = "${var.project_name}-n8n-secrets-policy"
  description = "Policy for n8n tasks to access Secrets Manager secrets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = [aws_secretsmanager_secret.db_password.arn, aws_secretsmanager_secret.n8n_encryption_key.arn]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "n8n_secrets_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.n8n_secrets_policy.arn
}

# Secrets Manager for RDS password and n8n encryption key
resource "aws_secretsmanager_secret" "db_password" {
  name_prefix = "${var.project_name}-db-password"
  description = "RDS password for n8n"
}

resource "aws_secretsmanager_secret_version" "db_password_version" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}

resource "aws_secretsmanager_secret" "n8n_encryption_key" {
  name_prefix = "${var.project_name}-n8n-encryption-key"
  description = "n8n encryption key"
}

resource "aws_secretsmanager_secret_version" "n8n_encryption_key_version" {
  secret_id     = aws_secretsmanager_secret.n8n_encryption_key.id
  secret_string = var.n8n_encryption_key
}

# RDS Security Group
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound traffic to RDS from ECS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5432 # PostgreSQL default port
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id] # Allow from ECS tasks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = aws_subnet.private[*].id # RDS in private subnets

  tags = {
    Name = "${var.project_name}-rds-subnet-group"
  }
}

# RDS Instance
resource "aws_db_instance" "n8n_db" {
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "13.15" # Or a desired version
  instance_class       = "db.t3.micro" # Adjust based on your needs
  identifier           = "${var.project_name}-n8n-db"
  username             = var.db_user
  password             = var.db_password # From secrets manager
  db_name              = var.db_name
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name = aws_db_subnet_group.main.name
  skip_final_snapshot  = true
  publicly_accessible  = false # Crucial for security

  tags = {
    Name = "${var.project_name}-n8n-db"
  }
}

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP/HTTPS access to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

# ECS Task Security Group
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Allow inbound traffic to ECS tasks from ALB and outbound to RDS/internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5678 # n8n default port
    to_port     = 5678
    protocol    = "tcp"
    security_groups = [aws_security_group.alb.id] # Allow from ALB
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Allow outbound to internet (for n8n connections)
  }

  tags = {
    Name = "${var.project_name}-ecs-tasks-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "n8n_alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id # ALB in public subnets

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# Target Group for ALB
resource "aws_lb_target_group" "n8n_tg" {
  name        = "${var.project_name}-tg"
  port        = 5678 # n8n default port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Fargate uses IP targets

  health_check {
    path                = "/healthz" # n8n health check endpoint
    protocol            = "HTTP"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

# ACM Certificate
# For testing, you can use a self-signed cert or if you have a domain
# you control, request a public one. For "autogenerated internal domain"
# exposure, you'll still need a valid cert, typically generated by ACM
# or imported, for HTTPS to work properly with a browser.
# This example assumes you will create a certificate for the ALB DNS name
# in ACM. This requires DNS validation, so you'd need to add a CNAME record
# if you were using a custom domain. For the ALB's autogenerated DNS,
# you *can* request a public certificate for that specific DNS name.
# However, for pure "testing with autogenerated internal domain",
# you might temporarily disable HTTPS or ignore certificate warnings in your browser.
# For proper public access, a real domain with an ACM cert is recommended.
#
# For simplicity in this example, we'll configure HTTPS but assume
# you'll manually handle the ACM certificate for the ALB's public DNS name
# if you want a fully trusted connection without browser warnings.
# Or, if you use a custom domain later, you'd request a cert for that domain.
#
# For initial testing purposes, you could even just use HTTP (port 80)
# on the ALB listener to simplify.
#
# Let's add a placeholder for ACM, as it's part of the request.
# You would typically provision this outside of this specific Terraform config
# if you're using a custom domain. For an autogenerated ALB DNS name,
# requesting an ACM certificate directly for that generated name isn't
# straightforward or common.
#
# If you truly want a public domain, you'd need a Route 53 Public Hosted Zone
# and request a certificate for that domain in ACM. Then the ALB would point
# to that certificate, and your Route 53 alias record would point to the ALB.

# For this setup, we'll use a placeholder variable for an existing certificate ARN.
# You'd either manually provision a certificate for a domain you own and point
# to the ALB, or if you strictly want to use the ALB's autogenerated DNS,
# you would just use HTTP or accept browser warnings.
# For production-like testing, an ACM certificate associated with a custom domain
# is the standard approach.

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.n8n_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.n8n_tg.arn
#    redirect {
#      port        = "443"
#      protocol    = "HTTPS"
#      status_code = "HTTP_301"
#    }
  }
}

# HTTPS Listener
# resource "aws_lb_listener" "https" {
#  load_balancer_arn = aws_lb.n8n_alb.arn
#  port              = 443
#  protocol          = "HTTPS"
  # IMPORTANT: Replace with a valid ACM certificate ARN
  # You'll need to manually provision an ACM certificate beforehand.
  # For testing, you could get a free cert for a custom domain via ACM,
  # or omit this listener if you're OK with HTTP for now.
#  certificate_arn   = var.acm_certificate_arn # This variable needs to be added to variables.tf and populated

#  default_action {
#    type             = "forward"
#    target_group_arn = aws_lb_target_group.n8n_tg.arn
#  }
# }


# ECS Task Definition
resource "aws_ecs_task_definition" "n8n" {
  family                   = "${var.project_name}-n8n-task"
  cpu                      = "1024" # 1 vCPU
  memory                   = "2048" # 2GB
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "n8n"
      image     = "${aws_ecr_repository.n8n.repository_url}:${var.container_image_tag}"
      cpu       = 1024
      memory    = 2048
      essential = true
      portMappings = [
        {
          containerPort = 5678
          hostPort      = 5678
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "N8N_HOST"
          value = "http://${aws_lb.n8n_alb.dns_name}" # Use ALB DNS name
        },
        {
          name  = "N8N_PORT"
          value = "5678"
        },
        {
          name  = "N8N_PROTOCOL"
          value = "https" # Assumes HTTPS on ALB
        },
        {
          name  = "WEBHOOK_URL"
          value = "https://${aws_lb.n8n_alb.dns_name}/webhook/"
        },
        {
          name  = "GENERIC_TIMEZONE"
          value = "America/New_York"
        },
        {
          name  = "DB_TYPE"
          value = "postgres"
        },
        {
          name  = "DB_HOST"
          value = aws_db_instance.n8n_db.address # RDS Endpoint
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "DB_DATABASE"
          value = var.db_name
        },
        {
          name  = "DB_USER"
          value = var.db_user
        }
      ]
      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = aws_secretsmanager_secret.db_password.arn
        },
        {
          name      = "N8N_ENCRYPTION_KEY"
          valueFrom = aws_secretsmanager_secret.n8n_encryption_key.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/n8n-fargate"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
  tags = {
    Name = "${var.project_name}-n8n-task"
  }
}

# CloudWatch Log Group for ECS tasks
resource "aws_cloudwatch_log_group" "n8n_logs" {
  name              = "/ecs/n8n-fargate"
  retention_in_days = 7 # Adjust as needed

  tags = {
    Name = "${var.project_name}-n8n-logs"
  }
}


# ECS Service
resource "aws_ecs_service" "n8n" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.n8n.id
  task_definition = aws_ecs_task_definition.n8n.arn
  desired_count   = 1 # Start with 1, scale up as needed. Be aware of n8n's webhook limitations with multiple instances without a shared queue.
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id # Fargate tasks in private subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false # Tasks do not need public IPs directly
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.n8n_tg.arn
    container_name   = "n8n"
    container_port   = 5678
  }

  depends_on = [
    aws_lb_listener.http,
    aws_db_instance.n8n_db
  ]

  tags = {
    Name = "${var.project_name}-n8n-service"
  }
}

# Data source for available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# IMPORTANT: Add this variable to variables.tf for the ACM ARN
# variable "acm_certificate_arn" {
#  description = "ARN of the ACM certificate for the ALB HTTPS listener. You must provision this separately."
#  type        = string
  # No default, it must be provided. For testing with ALB's autogenerated DNS,
  # you'll need to manually get a certificate for that specific ALB DNS
  # if you want valid HTTPS without browser warnings.
  # For a real application, you'd associate a custom domain with the ALB
  # and get an ACM certificate for that custom domain.
#}