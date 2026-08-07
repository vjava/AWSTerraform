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

# 1. EBS VOLUME (GP3, 20GB, ENCRYPTED)
resource "aws_ebs_volume" "demo_ebs" {
  availability_zone = "us-east-1a"
  size              = 20
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "demo-ebs-volume-${random_id.suffix.hex}"
  }
}

# 2. EBS SNAPSHOT CREATION
resource "aws_ebs_snapshot" "demo_snapshot" {
  volume_id   = aws_ebs_volume.demo_ebs.id
  description = "Basic snapshot management test for EBS volume"

  tags = {
    Name = "demo-ebs-snapshot-${random_id.suffix.hex}"
  }
}

# OUTPUTS
output "ebs_volume_id" {
  value = aws_ebs_volume.demo_ebs.id
}

output "ebs_snapshot_id" {
  value = aws_ebs_snapshot.demo_snapshot.id
}

output "ebs_volume_size" {
  value = aws_ebs_volume.demo_ebs.size
}

output "ebs_volume_type" {
  value = aws_ebs_volume.demo_ebs.type
}