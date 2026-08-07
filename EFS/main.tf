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

# 1. NETWORKING SETUP (VPC & SUBNET FOR MOUNT TARGET)
resource "aws_vpc" "efs_vpc" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "efs-vpc-${random_id.suffix.hex}"
  }
}

resource "aws_subnet" "efs_subnet" {
  vpc_id            = aws_vpc.efs_vpc.id
  cidr_block        = "10.50.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "efs-subnet-${random_id.suffix.hex}"
  }
}

resource "aws_security_group" "efs_sg" {
  name        = "efs-security-group-${random_id.suffix.hex}"
  description = "Allow NFS traffic for EFS"
  vpc_id      = aws_vpc.efs_vpc.id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["10.50.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2. EFS FILE SYSTEM (GENERAL PURPOSE, BURSTING, ENCRYPTED, IA AFTER 1 DAY)
resource "aws_efs_file_system" "demo_efs" {
  creation_token   = "efs-token-${random_id.suffix.hex}"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true

  lifecycle_policy {
    transition_to_ia = "AFTER_1_DAY"
  }

  tags = {
    Name = "demo-efs-${random_id.suffix.hex}"
  }
}

# 3. EFS MOUNT TARGET
resource "aws_efs_mount_target" "demo_mount_target" {
  file_system_id  = aws_efs_file_system.demo_efs.id
  subnet_id       = aws_subnet.efs_subnet.id
  security_groups = [aws_security_group.efs_sg.id]
}

# OUTPUTS
output "efs_file_system_id" {
  value = aws_efs_file_system.demo_efs.id
}

output "efs_mount_target_id" {
  value = aws_efs_mount_target.demo_mount_target.id
}