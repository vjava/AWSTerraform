terraform {
  required_version = ">= 1.0.0"
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

# 1. S3 Bucket for Glue Scripts & Temporary Files
resource "aws_s3_bucket" "glue_bucket" {
  bucket        = "aws-glue-script-bucket-${random_id.suffix.hex}"
  force_destroy = true
}

# 2. Upload Minimal PySpark Script to S3
resource "aws_s3_object" "glue_script" {
  bucket  = aws_s3_bucket.glue_bucket.id
  key     = "scripts/sample_glue_job.py"
  content = <<EOF
import sys
from awsglue.utils import getResolvedOptions

args = getResolvedOptions(sys.argv, ['JOB_NAME'])
print(f"Hello from AWS Glue Job: {args['JOB_NAME']}")
print("Execution Completed Successfully.")
EOF
}

# 3. IAM Role for Glue Service
resource "aws_iam_role" "glue_role" {
  name = "aws_glue_minimal_role_${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

# Managed Attachments (Compatible with AWS Lab Roles & Permissions)
resource "aws_iam_role_policy_attachment" "glue_service_attachment" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_s3_attachment" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# 4. AWS Glue Job (Lowest Resource Configuration)
resource "aws_glue_job" "minimal_job" {
  name              = "minimal-pyspark-job-${random_id.suffix.hex}"
  role_arn          = aws_iam_role.glue_role.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 5
  max_retries       = 0

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.glue_bucket.id}/${aws_s3_object.glue_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                    = "python"
    "--enable-continuous-cloudwatch-log" = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.glue_service_attachment,
    aws_iam_role_policy_attachment.glue_s3_attachment
  ]
}

# OUTPUTS
output "glue_job_name" {
  value       = aws_glue_job.minimal_job.name
  description = "Name of the provisioned Glue Job"
}

output "aws_region" {
  value       = "us-east-1"
  description = "AWS Region where resources are deployed"
}
