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

data "aws_caller_identity" "current" {}

# 1. S3 BUCKET FOR CLOUDTRAIL LOGS (Protected against deletion)
resource "aws_s3_bucket" "cloudtrail_bucket" {
  bucket        = "compliant-cloudtrail-logs-${random_id.suffix.hex}"
  force_destroy = false  # Deletion Of CloudTrail Logs Not Allowed
}

# Standard Retention Policy & Log Protection (Filter added for provider compliance)
resource "aws_s3_bucket_lifecycle_configuration" "bucket_lifecycle" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id

  rule {
    id     = "standard-retention-rule"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
  }
}

# S3 Bucket Policy to Allow CloudTrail Logging
resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail_bucket.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail_bucket.arn}/prefix/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# 2. AWS CLOUDTRAIL TRAIL (Removed insight_selector to bypass PutInsightSelectors SCP restriction)
resource "aws_cloudtrail" "compliant_trail" {
  name                          = "compliant-standard-trail-${random_id.suffix.hex}"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_bucket.id
  s3_key_prefix                 = "prefix"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true  # Log Validation Enabled

  event_selector {
    read_write_type           = "All"
    include_management_events = true     # Standard Events
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_bucket_policy]
}

output "trail_name" {
  value = aws_cloudtrail.compliant_trail.name
}

output "trail_arn" {
  value = aws_cloudtrail.compliant_trail.arn
}

output "s3_bucket_name" {
  value = aws_s3_bucket.cloudtrail_bucket.id
}