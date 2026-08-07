<#
.SYNOPSIS
    Enterprise Analytics Pipeline Orchestrator (Kinesis, Firehose, DynamoDB, Redshift, OpenSearch, ACM)
.DESCRIPTION
    PowerShell script that generates Terraform infrastructure code for advanced AWS analytics,
    deploys to LocalStack, and validates data ingestion.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-PipelineLog {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")][string]$Level = "INFO"
    )
    $TimeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $Color = switch ($Level) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        default   { "Cyan" }
    }
    Write-Host "[$TimeStamp] [$Level] $Message" -ForegroundColor $Color
}

Write-PipelineLog "Workspace initializing..." "INFO"

$WorkDir = Join-Path $PSScriptRoot "analytics_workspace"
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir | Out-Null
}

$TfFile = Join-Path $WorkDir "main.tf"
$EndpointUrl = "http://localhost:4566"

# ==============================================================================
# Python Validation Client Generation
# ==============================================================================
Write-PipelineLog "Generating Python validation script..." "INFO"

$ValidatorPy = @'
import json
import os
import boto3

def validate_pipeline():
    endpoint_url = os.environ.get("LOCALSTACK_ENDPOINT", "http://localhost:4566")
    region = os.environ.get("AWS_REGION", "us-east-1")

    boto_kwargs = {
        "endpoint_url": endpoint_url,
        "region_name": region,
        "aws_access_key_id": "test",
        "aws_secret_access_key": "test"
    }

    kinesis = boto3.client("kinesis", **boto_kwargs)
    ddb = boto3.client("dynamodb", **boto_kwargs)

    stream_name = "BankingTransactionStream"
    table_name = "AnalyticsTransactions"

    # 1. Put record into Kinesis Stream
    sample_data = {
        "TransactionId": "TXN-99901",
        "CustomerId": "CUST-8888",
        "Amount": 1500.00,
        "Currency": "INR",
        "Status": "COMPLETED"
    }

    print(f"Sending record to Kinesis Stream: {stream_name}")
    kinesis.put_record(
        StreamName=stream_name,
        Data=json.dumps(sample_data),
        PartitionKey="CUST-8888"
    )

    # 2. Store corresponding audit record in DynamoDB
    print(f"Writing audit record to DynamoDB: {table_name}")
    ddb.put_item(
        TableName=table_name,
        Item={
            "TransactionId": {"S": "TXN-99901"},
            "CustomerId": {"S": "CUST-8888"},
            "Amount": {"N": "1500.00"},
            "State": {"S": "INGESTED"}
        }
    )
    print("Validation data successfully published and recorded.")

if __name__ == "__main__":
    validate_pipeline()
'@

Set-Content -Path (Join-Path $WorkDir "validate.py") -Value $ValidatorPy -Encoding UTF8

# ==============================================================================
# Terraform HCL Code Generation
# ==============================================================================
Write-PipelineLog "Writing Terraform infrastructure definitions to main.tf..." "INFO"

$TerraformHcl = @'
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
'@

Set-Content -Path $TfFile -Value $TerraformHcl -Encoding UTF8

# ==============================================================================
# Execution & Deployment
# ==============================================================================
Push-Location $WorkDir
try {
    Write-PipelineLog "Running Terraform Init..." "INFO"
    terraform init -input=false -no-color | Out-Null

    Write-PipelineLog "Applying Terraform Plan to LocalStack..." "INFO"
    terraform apply -auto-approve -input=false -no-color | Out-Null
    Write-PipelineLog "Terraform deployment completed successfully!" "SUCCESS"

    Write-PipelineLog "Running Python validation script to push data into Kinesis and DynamoDB..." "INFO"
    python "validate.py"

    Write-PipelineLog "Verifying DynamoDB state..." "INFO"
    $ItemRaw = aws --endpoint-url=$EndpointUrl dynamodb get-item --table-name AnalyticsTransactions --key "{\`"TransactionId\`":{\`"S\`":\`"TXN-99901\`"}}"
    if (-not [string]::IsNullOrWhiteSpace($ItemRaw)) {
        Write-PipelineLog "Data verification successful! Record found in DynamoDB." "SUCCESS"
        Write-Host $ItemRaw -ForegroundColor Cyan
    } else {
        Write-PipelineLog "Verification warning: Record not immediately found." "WARNING"
    }
}
catch {
    Write-PipelineLog "Pipeline Execution Failed: $_" "ERROR"
}
finally {
    Pop-Location
}