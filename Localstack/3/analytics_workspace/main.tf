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
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    acm            = "http://localhost:4566"
    iam            = "http://localhost:4566"
    kinesis        = "http://localhost:4566"
    firehose       = "http://localhost:4566"
    dynamodb       = "http://localhost:4566"
    redshift       = "http://localhost:4566"
    opensearch     = "http://localhost:4566"
    s3             = "http://localhost:4566"
  }
}

# 1. IAM Role for Analytics Pipeline
resource "aws_iam_role" "analytics_role" {
  name = "AnalyticsExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = ["firehose.amazonaws.com", "kinesis.amazonaws.com"] }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "admin_attach" {
  role       = aws_iam_role.analytics_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 2. ACM Certificate
resource "aws_acm_certificate" "cert" {
  domain_name       = "analytics.bank.internal"
  validation_method = "DNS"

  tags = {
    Environment = "Production"
  }
}

# 3. Kinesis Data Stream
resource "aws_kinesis_stream" "banking_stream" {
  name             = "BankingTransactionStream"
  shard_count      = 1
  retention_period = 24
}

# 4. S3 Bucket for Firehose Backup/Destination
resource "aws_s3_bucket" "analytics_bucket" {
  bucket        = "bank-analytics-bucket-local"
  force_destroy = true
}

# 5. Kinesis Firehose Delivery Stream
resource "aws_kinesis_firehose_delivery_stream" "extended_s3_stream" {
  name        = "BankingFirehoseDelivery"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.analytics_role.arn
    bucket_arn = aws_s3_bucket.analytics_bucket.arn
    buffering_size      = 1
    buffering_interval  = 60
  }
}

# 6. DynamoDB Analytics Table
resource "aws_dynamodb_table" "analytics_table" {
  name         = "AnalyticsTransactions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "TransactionId"

  attribute {
    name = "TransactionId"
    type = "S"
  }
}

# 7. Redshift Cluster
resource "aws_redshift_cluster" "redshift" {
  cluster_identifier = "bank-redshift-cluster"
  database_name      = "bankdw"
  master_username    = "adminuser"
  master_password    = "SecureAdmin123!"
  node_type          = "dc2.large"
  cluster_type       = "single-node"
  skip_final_snapshot = true
}

# 8. OpenSearch Domain
resource "aws_opensearch_domain" "opensearch" {
  domain_name    = "bank-search-domain"
  engine_version = "OpenSearch_1.3"

  cluster_config {
    instance_type = "t3.small.search"
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
  }
}

# Outputs
output "kinesis_stream_name" {
  value = aws_kinesis_stream.banking_stream.name
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.analytics_table.name
}

output "acm_certificate_arn" {
  value = aws_acm_certificate.cert.arn
}
