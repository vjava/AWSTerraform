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
# VPC & NETWORKING
# -----------------------------------------------------------------------------
resource "aws_vpc" "rds_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "rds-compliant-vpc-${random_id.suffix.hex}" }
}

resource "aws_subnet" "subnet_a" {
  vpc_id                  = aws_vpc.rds_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = { Name = "rds-subnet-a" }
}

resource "aws_subnet" "subnet_b" {
  vpc_id                  = aws_vpc.rds_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = { Name = "rds-subnet-b" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.rds_vpc.id
  tags   = { Name = "rds-igw" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.rds_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "rds-public-rt" }
}

resource "aws_route_table_association" "assoc_a" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "assoc_b" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group-${random_id.suffix.hex}"
  subnet_ids = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]

  tags = { Name = "RDS Subnet Group" }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-mysql-sg-${random_id.suffix.hex}"
  description = "Allow MySQL traffic from anywhere"
  vpc_id      = aws_vpc.rds_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
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

# -----------------------------------------------------------------------------
# RDS MYSQL INSTANCE (Strict Lab Compliance)
# -----------------------------------------------------------------------------
resource "aws_db_instance" "mysql_db" {
  identifier             = "compliant-mysql-db-${random_id.suffix.hex}"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"       # Permitted T-series burstable class
  allocated_storage      = 20                  # Limit: Max 30 GB
  max_allocated_storage  = 20                  # Disables autoscaling beyond lab limit
  storage_type           = "gp2"                 # Standard GP2 Storage (No Provisioned IOPS)
  
  db_name                = "company_db"
  username               = "admin"
  password               = "LabPassword123!"     # Change if needed
  
  multi_az               = false                 # Single-AZ Deployment
  publicly_accessible    = true
  skip_final_snapshot    = true
  
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  tags = {
    Environment = "Lab"
  }
}

output "rds_endpoint" {
  value = aws_db_instance.mysql_db.endpoint
}

output "rds_address" {
  value = aws_db_instance.mysql_db.address
}

output "db_name" {
  value = aws_db_instance.mysql_db.db_name
}