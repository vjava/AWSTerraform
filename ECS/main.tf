terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# IAM ROLE CREATION (Unique Name to avoid conflict)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecsTaskRole-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# -----------------------------------------------------------------------------
# VPC & NETWORKING
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "ecs-cron-vpc-${random_id.suffix.hex}" }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = { Name = "ecs-cron-public-subnet-1" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "ecs-cron-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "ecs-cron-public-rt" }
}

resource "aws_route_table_association" "pub_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ecs_sg" {
  name        = "ecs-cron-task-sg-${random_id.suffix.hex}"
  description = "Allow outbound connectivity for scheduled task"
  vpc_id      = aws_vpc.main.id

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------------------------------------------------------
# CLOUDWATCH LOG GROUP (Unique Name)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name = "/ecs/compliant-python-cron-${random_id.suffix.hex}"
}

# -----------------------------------------------------------------------------
# ECS CLUSTER & TASK DEFINITION
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "compliant-cron-ecs-cluster-${random_id.suffix.hex}"
}

resource "aws_ecs_task_definition" "python_cron" {
  family                   = "python-cron-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "python-worker"
      image     = "python:3.11-slim"
      essential = true

      environment = [
        { name = "PYTHONUNBUFFERED", value = "1" }
      ]

      command = [
        "python3", "-c",
        "import datetime, time; print('=== ECS Task Started ===');\nfor i in range(5):\n    print(f'[{datetime.datetime.now()}] Running iteration {i+1}...');\n    time.sleep(10);\nprint('=== ECS Task Completed Successfully ===')"
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# ECS SERVICE
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "main" {
  name            = "compliant-cron-ecs-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.python_cron.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_1.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
}

output "cluster_name" { value = aws_ecs_cluster.main.name }
output "log_group_name" { value = aws_cloudwatch_log_group.ecs_logs.name }