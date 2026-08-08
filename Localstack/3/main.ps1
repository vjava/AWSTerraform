<#
.SYNOPSIS
    Enterprise Analytics & High-Volume Data Pipeline Orchestrator (Fixed S3 Addressing)
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

Write-PipelineLog "Initializing Enterprise Analytics Workspace..." "INFO"

$WorkDir = Join-Path $PSScriptRoot "enterprise_workspace"
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir | Out-Null
}

$TfFile = Join-Path $WorkDir "main.tf"
$EndpointUrl = "http://localhost:4566"

# ==============================================================================
# 1. Python 100k Employee Batch Ingestion Client
# ==============================================================================
Write-PipelineLog "Generating Python 100k Employee batch ingestion script..." "INFO"

$EmployeeScriptPy = @'
import time
import boto3
from botocore.exceptions import ClientError

def populate_enterprise_employees():
    endpoint_url = "http://localhost:4566"
    region_name = "us-east-1"

    print("Connecting to LocalStack DynamoDB...")
    ddb = boto3.client(
        "dynamodb",
        endpoint_url=endpoint_url,
        region_name=region_name,
        aws_access_key_id="test",
        aws_secret_access_key="test"
    )

    table_name = "EnterpriseEmployees"
    total_records = 100000
    batch_size = 25
    requests = []

    print(f"Starting high-speed batch insertion of {total_records} employee records...")
    start_time = time.time()

    for i in range(1, total_records + 1):
        emp_id = f"EMP-{i:06d}"
        item = {
            "PutRequest": {
                "Item": {
                    "EmployeeId": {"S": emp_id},
                    "FirstName": {"S": f"FirstName{i}"},
                    "LastName": {"S": f"LastName{i}"},
                    "Department": {"S": "Engineering" if i % 2 == 0 else "Finance"},
                    "Email": {"S": f"employee{i}@enterprise.internal"},
                    "Salary": {"N": str(60000 + (i % 40000))}
                }
            }
        }
        requests.append(item)

        if len(requests) == batch_size or i == total_records:
            try:
                response = ddb.batch_write_item(RequestItems={table_name: requests})
                unprocessed = response.get("UnprocessedItems", {})
                while unprocessed:
                    response = ddb.batch_write_item(RequestItems=unprocessed)
                    unprocessed = response.get("UnprocessedItems", {})
            except ClientError as e:
                print(f"Batch write error: {e}")
            requests = []

        if i % 20000 == 0:
            print(f"Progress: {i}/{total_records} records injected...")

    end_time = time.time()
    print(f"Successfully inserted {total_records} records into '{table_name}' in {round(end_time - start_time, 2)} seconds!")

if __name__ == "__main__":
    populate_enterprise_employees()
'@

Set-Content -Path (Join-Path $WorkDir "insert_employees.py") -Value $EmployeeScriptPy -Encoding UTF8

# ==============================================================================
# 2. Terraform HCL Infrastructure Code (Path-Style S3 Enabled)
# ==============================================================================
Write-PipelineLog "Writing complete Enterprise Terraform infrastructure code..." "INFO"

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
'@

Set-Content -Path $TfFile -Value $TerraformHcl -Encoding UTF8

# ==============================================================================
# 3. Execution
# ==============================================================================
Push-Location $WorkDir
try {
    Write-PipelineLog "Running Terraform Init..." "INFO"
    terraform init -input=false -no-color | Out-Null

    Write-PipelineLog "Applying Terraform Plan to LocalStack..." "INFO"
    terraform apply -auto-approve -input=false -no-color | Out-Null
    Write-PipelineLog "Infrastructure deployment completed successfully!" "SUCCESS"
}
catch {
    Write-PipelineLog "Pipeline execution error: $_" "ERROR"
}
finally {
    Pop-Location
}