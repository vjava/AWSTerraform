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
# AWS SYSTEMS MANAGER (SSM) PARAMETER STORE (STRING & SECURESTRING)
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "config_db_url" {
  name        = "/config/app/db_url_${random_id.suffix.hex}"
  description = "Database connection string"
  type        = "String"
  value       = "postgres://db.internal.company.com:5432/appdb"

  tags = {
    Environment = "production"
  }
}

resource "aws_ssm_parameter" "config_api_key" {
  name        = "/config/app/api_key_${random_id.suffix.hex}"
  description = "Secure API Key"
  type        = "SecureString"
  value       = "super-secret-api-token-value-12345"

  tags = {
    Environment = "production"
  }
}

# OUTPUTS
output "ssm_db_param_name" {
  value = aws_ssm_parameter.config_db_url.name
}

output "ssm_api_param_name" {
  value = aws_ssm_parameter.config_api_key.name
}