terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "repository_name" {
  type        = string
  description = "Name of the public ECR repository"
  default     = "my-public-app-repo"
}

resource "aws_ecrpublic_repository" "repo" {
  repository_name = var.repository_name
  catalog_data {
    description       = "Public ECR repository with vulnerability scanning and lifecycle policies"
    operating_systems = ["Linux"]
    architectures     = ["x86_64"]
  }
}

resource "aws_ecrpublic_repository_policy" "policy" {
  repository_name = aws_ecrpublic_repository.repo.repository_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicRead"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "ecr-public:GetAuthorizationToken",
          "ecr-public:BatchCheckLayerAvailability",
          "ecr-public:GetDownloadUrlForLayer",
          "ecr-public:DescribeRepositories",
          "ecr-public:ListImages",
          "ecr-public:DescribeImages"
        ]
      }
    ]
  })
}

output "repository_uri" {
  value       = aws_ecrpublic_repository.repo.repository_uri
  description = "The URI of the public ECR repository"
}
