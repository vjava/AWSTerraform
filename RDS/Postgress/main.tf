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

# Fetch Default VPC
data "aws_vpc" "default" {
  default = true
}

# Fetch Subnets in Default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group
resource "aws_security_group" "rds_sg" {
  name        = "rds-pg-sg-${random_id.suffix.hex}"
  description = "Allow PostgreSQL traffic from anywhere"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-pg-subnet-group-${random_id.suffix.hex}"
  subnet_ids = data.aws_subnets.default.ids
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "postgres_db" {
  identifier             = "compliant-rds-pg-${random_id.suffix.hex}"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"       # Permitted T-series class
  allocated_storage      = 20                  # Max 30 GB limit
  max_allocated_storage  = 20
  storage_type           = "gp2"
  
  db_name                = "transaction_db"
  username               = "postgres"
  password               = "LabPassword123!"
  
  publicly_accessible    = true
  skip_final_snapshot    = true
  
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
}

output "aurora_endpoint" {
  value = aws_db_instance.postgres_db.address
}

output "db_name" {
  value = aws_db_instance.postgres_db.db_name
}