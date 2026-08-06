terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# -----------------------------------------------------------------------------
# RANDOM CREDENTIALS (INCLUDES NUMBERS & REDSHIFT SUPPORTED SPECIAL CHARS)
# Valid specials exclude: / @ " ' \ space
# -----------------------------------------------------------------------------
resource "random_password" "admin_password" {
  length           = 16
  special          = true
  numeric          = true
  override_special = "!#$%&*-_=+[]{}<>?"
}

# -----------------------------------------------------------------------------
# VPC & NETWORKING
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "redshift-serverless-vpc" }
}

resource "aws_subnet" "subnet_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = { Name = "redshift-subnet-1" }
}

resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = { Name = "redshift-subnet-2" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "redshift-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "redshift-public-rt" }
}

resource "aws_route_table_association" "pub_1" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "pub_2" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "redshift_sg" {
  name        = "redshift-serverless-sg"
  description = "Allow inbound Redshift connectivity"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5439
    to_port     = 5439
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
# REDSHIFT SERVERLESS NAMESPACE & WORKGROUP
# -----------------------------------------------------------------------------
resource "aws_redshiftserverless_namespace" "main" {
  namespace_name      = "compliant-redshift-namespace"
  db_name             = "dev"
  admin_username      = "adminuser"
  admin_user_password = random_password.admin_password.result
}

resource "aws_redshiftserverless_workgroup" "main" {
  workgroup_name       = "compliant-redshift-workgroup"
  namespace_name       = aws_redshiftserverless_namespace.main.namespace_name
  base_capacity        = 8
  publicly_accessible  = true
  
  subnet_ids           = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
  security_group_ids   = [aws_security_group.redshift_sg.id]

  config_parameter {
    parameter_key   = "search_path"
    parameter_value = "$user, public"
  }
}

resource "aws_redshiftserverless_snapshot" "main" {
  namespace_name   = aws_redshiftserverless_namespace.main.namespace_name
  snapshot_name    = "initial-compliance-snapshot"
  retention_period = 1

  depends_on = [aws_redshiftserverless_workgroup.main]
}

# OUTPUTS
output "workgroup_name" { value = aws_redshiftserverless_workgroup.main.workgroup_name }
output "namespace_name" { value = aws_redshiftserverless_namespace.main.namespace_name }
output "database_name"  { value = aws_redshiftserverless_namespace.main.db_name }
output "endpoint_address" { value = aws_redshiftserverless_workgroup.main.endpoint[0].address }
output "admin_password" {
  value     = random_password.admin_password.result
  sensitive = true
}