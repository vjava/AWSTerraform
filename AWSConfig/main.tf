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

# 1. S3 BUCKET FOR CONFIG SNAPSHOTS AND HISTORY
resource "aws_s3_bucket" "config_bucket" {
  bucket        = "compliant-aws-config-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "config_bucket_policy" {
  bucket = aws_s3_bucket.config_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSConfigBucketPermissionsCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.config_bucket.arn
      },
      {
        Sid       = "AWSConfigBucketExistenceCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.config_bucket.arn
      },
      {
        Sid       = "AWSConfigBucketDelivery"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# 2. CONFIGURATION RECORDER
resource "aws_config_configuration_recorder" "main_recorder" {
  name     = "compliant-config-recorder-33dfe58c"
  role_arn = "arn:aws:iam::654654589397:role/aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS"

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

# 3. DELIVERY CHANNEL
resource "aws_config_delivery_channel" "main_channel" {
  name           = "compliant-config-delivery-channel-${random_id.suffix.hex}"
  s3_bucket_name = aws_s3_bucket.config_bucket.id

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [
    aws_config_configuration_recorder.main_recorder,
    aws_s3_bucket_policy.config_bucket_policy
  ]
}

# 4. ENABLE CONFIGURATION RECORDER
resource "aws_config_configuration_recorder_status" "recorder_status" {
  name       = aws_config_configuration_recorder.main_recorder.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main_channel]
}

# 5. CONFIG RULE
resource "aws_config_config_rule" "s3_public_read_prohibited" {
  name        = "s3-bucket-level-public-read-prohibited-${random_id.suffix.hex}"
  description = "Checks that S3 buckets do not allow public read access"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_LEVEL_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder_status.recorder_status]
}

# 6. REMEDIATION CONFIGURATION
resource "aws_config_remediation_configuration" "s3_remediation" {
  config_rule_name = aws_config_config_rule.s3_public_read_prohibited.name
  target_type      = "SSM_DOCUMENT"
  target_id        = "AWS-DisableS3BucketPublicReadWrite"

  parameter {
    name         = "BucketName"
    resource_value = "RESOURCE_ID"
  }

  automatic                  = false
  maximum_automatic_attempts = 5
  retry_attempt_seconds      = 60
}

output "recorder_name" {
  value = aws_config_configuration_recorder.main_recorder.name
}

output "delivery_channel_name" {
  value = aws_config_delivery_channel.main_channel.name
}

output "config_rule_name" {
  value = aws_config_config_rule.s3_public_read_prohibited.name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.config_bucket.id
}