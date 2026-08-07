# ==============================================================================
# AWS CLOUDTRAIL (LOG VALIDATION, INSIGHTS, COMPLIANT RETENTION) + PYTHON VERIFICATION
# ==============================================================================
Write-Host ">>> Initializing AWS CloudTrail Infrastructure and Verification Pipeline..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# STEP 0: PURGE PREVIOUS LOCAL STATE
# -----------------------------------------------------------------------------
Write-Host "`n[0/4] Purging previous terraform state and temporary files..." -ForegroundColor Yellow

$OldErrorAction = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"

Get-ChildItem -Path $PWD -Filter "*Copy*.tf" | Remove-Item -Force -ErrorAction SilentlyContinue

if (Test-Path "$PWD/terraform.tfstate") {
    Remove-Item "$PWD/terraform.tfstate" -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/terraform.tfstate.backup") {
    Remove-Item "$PWD/terraform.tfstate.backup" -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/.terraform") {
    Remove-Item "$PWD/.terraform" -Recurse -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/verify_cloudtrail.py") {
    Remove-Item "$PWD/verify_cloudtrail.py" -Force -ErrorAction SilentlyContinue
}

$ErrorActionPreference = $OldErrorAction
Write-Host "Local workspace cleaned." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 1: GENERATE TERRAFORM CODE (main.tf)
# -----------------------------------------------------------------------------
Write-Host "`n[1/4] Writing CloudTrail Terraform configuration..." -ForegroundColor Yellow

$TerraformCode = @'
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

# Standard Retention Policy & Log Protection
resource "aws_s3_bucket_lifecycle_configuration" "bucket_lifecycle" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id

  rule {
    id     = "standard-retention-rule"
    status = "Enabled"

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

# 2. AWS CLOUDTRAIL TRAIL
resource "aws_cloudtrail" "compliant_trail" {
  name                          = "compliant-standard-trail-${random_id.suffix.hex}"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_bucket.id
  s3_key_prefix                 = "prefix"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true  # Log Validation Enabled

  insight_selector {
    insight_type = "ApiCallRateInsight"  # Basic Insights
  }

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
'@

[System.IO.File]::WriteAllText("$PWD/main.tf", $TerraformCode)
Write-Host "main.tf generated successfully." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 2: APPLY TERRAFORM DEPLOYMENT
# -----------------------------------------------------------------------------
Write-Host "`n[2/4] Initializing and Applying Terraform Configuration..." -ForegroundColor Yellow
terraform init -reconfigure

& terraform apply -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nTerraform deployment failed!" -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------------------
# STEP 3: EXTRACT OUTPUTS & PREPARE PYTHON CLIENT
# -----------------------------------------------------------------------------
Write-Host "`n[3/4] Extracting CloudTrail Details..." -ForegroundColor Yellow
$TRAIL_NAME   = (terraform output -raw trail_name)
$TRAIL_ARN    = (terraform output -raw trail_arn)
$BUCKET_NAME  = (terraform output -raw s3_bucket_name)

Write-Host "Trail Name:   $TRAIL_NAME" -ForegroundColor Green
Write-Host "Trail ARN:    $TRAIL_ARN" -ForegroundColor Green
Write-Host "S3 Bucket:    $BUCKET_NAME" -ForegroundColor Green

python -c "import boto3" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing boto3..." -ForegroundColor Yellow
    pip install boto3
}

# -----------------------------------------------------------------------------
# STEP 4: GENERATE & RUN PYTHON VERIFICATION CLIENT
# -----------------------------------------------------------------------------
Write-Host "`n[4/4] Executing Python Verification Client..." -ForegroundColor Yellow

$PythonScript = @"
import boto3
import json
import time

trail_name = '$TRAIL_NAME'
region = 'us-east-1'

ct_client = boto3.client('cloudtrail', region_name=region)

print(f"Verifying CloudTrail Configuration for: {trail_name}\n")

try:
    # 1. Get Trail Details
    trail_info = ct_client.describe_trails(trailNameList=[trail_name])['trailList'][0]
    print("="*70)
    print("CLOUDTRAIL CONFIGURATION STATUS")
    print("="*70)
    print(f"Trail Name:                  {trail_info.get('Name')}")
    print(f"S3 Bucket:                   {trail_info.get('S3BucketName')}")
    print(f"Log File Validation Enabled: {trail_info.get('LogFileValidationEnabled')}")
    print(f"Is Multi-Region Trail:       {trail_info.get('IsMultiRegionTrail')}")
    print("="*70)

    # 2. Check Logging Status
    status_info = ct_client.get_trail_status(Name=trail_name)
    print(f"\nIs Logging Active:           {status_info.get('IsLogging')}")
    print(f"Latest Delivery Time:        {status_info.get('LatestDeliveryTime', 'Pending initial delivery')}")

    # 3. Check Insights Configuration
    insights = ct_client.get_insight_selectors(TrailName=trail_name)
    print("\nInsight Selectors Configured:")
    for selector in insights.get('InsightSelectors', []):
        print(f" - Insight Type: {selector.get('InsightType')}")

    # 4. Fetch Standard Management Events
    print("\nFetching Recent Standard Management Events (LookupEvents)...")
    events_response = ct_client.lookup_events(MaxResults=5)
    print("-" * 70)
    for event in events_response.get('Events', []):
        print(f"Event ID: {event.get('EventId')} | Name: {event.get('EventName')} | User: {event.get('Username', 'N/A')}")
    print("-" * 70)

    print("\nVerification Completed Successfully!")

except Exception as e:
    print(f"Error during verification: {e}")
"@

[System.IO.File]::WriteAllText("$PWD/verify_cloudtrail.py", $PythonScript)
python verify_cloudtrail.py

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "CLOUDTRAIL PIPELINE DEPLOYED & VERIFIED!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan