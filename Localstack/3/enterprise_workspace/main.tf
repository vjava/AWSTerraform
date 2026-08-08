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
  s3_use_path_style           = true

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

resource "aws_iam_role" "enterprise_role" {
  name = "EnterpriseAnalyticsExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = ["firehose.amazonaws.com", "kinesis.amazonaws.com"] }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "admin_access" {
  role       = aws_iam_role.enterprise_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "secure.enterprise.internal"
  validation_method = "DNS"
}

resource "aws_kinesis_stream" "stream" {
  name             = "EnterpriseTelemetryStream"
  shard_count      = 1
  retention_period = 24
}

resource "aws_s3_bucket" "bucket" {
  bucket        = "enterprise-data-lake-local"
  force_destroy = true
}

resource "aws_kinesis_firehose_delivery_stream" "firehose" {
  name        = "EnterpriseFirehoseDelivery"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.enterprise_role.arn
    bucket_arn = aws_s3_bucket.bucket.arn
    buffering_size      = 5
    buffering_interval  = 300
  }
}

resource "aws_dynamodb_table" "employees" {
  name         = "EnterpriseEmployees"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "EmployeeId"

  attribute {
    name = "EmployeeId"
    type = "S"
  }
}

resource "aws_redshift_cluster" "redshift" {
  cluster_identifier  = "enterprise-dw-cluster"
  database_name       = "enterprisedw"
  master_username     = "dbadmin"
  master_password     = "EnterpriseSecure123!"
  node_type           = "dc2.large"
  cluster_type        = "single-node"
  skip_final_snapshot = true
}

resource "aws_opensearch_domain" "opensearch" {
  domain_name    = "enterprise-search-domain"
  engine_version = "OpenSearch_1.3"

  cluster_config {
    instance_type = "t3.small.search"
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
  }
}
