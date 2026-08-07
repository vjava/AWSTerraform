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

# 1. S3 BUCKET FOR FIREHOSE DESTINATION
resource "aws_s3_bucket" "kinesis_bucket" {
  bucket        = "kinesis-firehose-store-${random_id.suffix.hex}"
  force_destroy = true
}

# 2. KINESIS DATA STREAM (SOURCE)
resource "aws_kinesis_stream" "data_stream" {
  name             = "compliant-kinesis-stream-${random_id.suffix.hex}"
  shard_count      = 1
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
}

# 3. IAM ROLE DATA SOURCE
data "aws_iam_role" "firehose_role" {
  name = "firehoseDeliveryRole-32ee2431"
}

# 4. KINESIS FIREHOSE DELIVERY STREAM
resource "aws_kinesis_firehose_delivery_stream" "s3_delivery" {
  name        = "compliant-firehose-s3-${random_id.suffix.hex}"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.data_stream.arn
    role_arn           = data.aws_iam_role.firehose_role.arn
  }

  extended_s3_configuration {
    role_arn           = data.aws_iam_role.firehose_role.arn
    bucket_arn         = aws_s3_bucket.kinesis_bucket.arn
    buffering_size     = 5   # Max 5 MB
    buffering_interval = 60  # Min 60 Seconds
    prefix             = "data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "errors/result=!{firehose:error-output-type}/"
  }
}

output "kinesis_stream_name" {
  value = aws_kinesis_stream.data_stream.name
}

output "firehose_stream_name" {
  value = aws_kinesis_firehose_delivery_stream.s3_delivery.name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.kinesis_bucket.id
}