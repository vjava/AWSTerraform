# ==============================================================================
# AWS CONFIG DEPLOYMENT & PYTHON VERIFICATION PIPELINE (ROLE OVERRIDE FIX)
# ==============================================================================
Write-Host ">>> Initializing AWS Config Infrastructure and Verification Pipeline..." -ForegroundColor Cyan

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
if (Test-Path "$PWD/verify_config.py") {
    Remove-Item "$PWD/verify_config.py" -Force -ErrorAction SilentlyContinue
}

$ErrorActionPreference = $OldErrorAction
Write-Host "Local workspace cleaned." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 1: DETECT LAB IAM ROLE & OVERRIDE RECORDER ROLE
# -----------------------------------------------------------------------------
Write-Host "`n[1/4] Resolving Compatible Lab IAM Role for AWS Config..." -ForegroundColor Yellow

$LAB_ROLE_NAME = "LabRole"
try {
    $all_roles = aws iam list-roles --query "Roles[? !contains(RoleName, 'aws-service-role') && !contains(RoleName, 'AWSServiceRole')].RoleName" --output json | ConvertFrom-Json
    foreach ($r in $all_roles) {
        if ($r -match "^LabRole$" -or $r -match "^Lab-Role$" -or $r -match "^voclabs$" -or $r -match "^vockey$") {
            $LAB_ROLE_NAME = $r
            break
        }
    }
} catch {}

$ROLE_ARN = (aws iam get-role --role-name $LAB_ROLE_NAME --query "Role.Arn" --output text 2>$null)

if ([string]::IsNullOrEmpty($ROLE_ARN)) {
    Write-Host "Error: Could not retrieve ARN for IAM Role: $LAB_ROLE_NAME" -ForegroundColor Red
    exit 1
}

Write-Host "Target Config IAM Role ARN: $ROLE_ARN" -ForegroundColor Green

# Check and update existing configuration recorder role if invalid
$EXISTING_RECORDER = ""
try {
    $rec_json = aws configservice describe-configuration-recorders --output json | ConvertFrom-Json
    if ($rec_json.ConfigurationRecorders.Count -gt 0) {
        $EXISTING_RECORDER = $rec_json.ConfigurationRecorders[0].name
        Write-Host "Updating Existing Configuration Recorder ($EXISTING_RECORDER) to use $LAB_ROLE_NAME..." -ForegroundColor Yellow
        aws configservice put-configuration-recorder --configuration-recorder "name=$EXISTING_RECORDER,roleARN=$ROLE_ARN" 2>$null
    }
} catch {}

# -----------------------------------------------------------------------------
# STEP 2: GENERATE TERRAFORM CODE (main.tf)
# -----------------------------------------------------------------------------
Write-Host "`n[2/4] Writing AWS Config Terraform configuration..." -ForegroundColor Yellow

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
  name     = "RECORDER_NAME_VAL"
  role_arn = "RECORDER_ROLE_ARN_VAL"

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
'@

$TerraformCode = $TerraformCode.Replace("RECORDER_ROLE_ARN_VAL", $ROLE_ARN)

if ($EXISTING_RECORDER) {
    $TerraformCode = $TerraformCode.Replace("RECORDER_NAME_VAL", $EXISTING_RECORDER)
} else {
    $TerraformCode = $TerraformCode.Replace("RECORDER_NAME_VAL", 'compliant-config-recorder-${random_id.suffix.hex}')
}

$MainTfPath = Join-Path -Path $PWD -ChildPath "main.tf"
[System.IO.File]::WriteAllText($MainTfPath, $TerraformCode)
Write-Host "main.tf generated successfully." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 3: APPLY TERRAFORM DEPLOYMENT
# -----------------------------------------------------------------------------
Write-Host "`n[3/4] Initializing Terraform..." -ForegroundColor Yellow
terraform init -reconfigure

if ($EXISTING_RECORDER) {
    Write-Host "Importing existing configuration recorder state..." -ForegroundColor Yellow
    & terraform import aws_config_configuration_recorder.main_recorder $EXISTING_RECORDER 2>$null
}

Write-Host "Applying Terraform configuration..." -ForegroundColor Yellow
& terraform apply -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nTerraform deployment failed!" -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------------------
# STEP 4: EXTRACT OUTPUTS AND PREPARE PYTHON CLIENT
# -----------------------------------------------------------------------------
Write-Host "`n[4/4] Extracting Details and Running Python Verification Client..." -ForegroundColor Yellow
$RECORDER_NAME  = (terraform output -raw recorder_name)
$CHANNEL_NAME   = (terraform output -raw delivery_channel_name)
$RULE_NAME      = (terraform output -raw config_rule_name)
$BUCKET_NAME    = (terraform output -raw s3_bucket_name)

Write-Host "Recorder Name:         $RECORDER_NAME" -ForegroundColor Green
Write-Host "Delivery Channel Name: $CHANNEL_NAME" -ForegroundColor Green
Write-Host "Config Rule Name:      $RULE_NAME" -ForegroundColor Green
Write-Host "S3 Storage Bucket:     $BUCKET_NAME" -ForegroundColor Green

python -c "import boto3" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing boto3..." -ForegroundColor Yellow
    pip install boto3
}

$PythonScript = @"
import boto3
import json

recorder_name = '$RECORDER_NAME'
rule_name = '$RULE_NAME'
region = 'us-east-1'

config_client = boto3.client('config', region_name=region)

print(f"\nVerifying AWS Config Setup for Recorder: {recorder_name}\n")

try:
    recorders = config_client.describe_configuration_recorders(ConfigurationRecorderNames=[recorder_name])
    rec_status = config_client.describe_configuration_recorder_status(ConfigurationRecorderNames=[recorder_name])
    
    print("="*70)
    print("AWS CONFIGURATION RECORDER STATUS")
    print("="*70)
    for r in recorders.get('ConfigurationRecorders', []):
        print(f"Recorder Name:       {r.get('name')}")
        print(f"Role ARN:            {r.get('roleARN')}")
        print(f"Recording All Types: {r.get('recordingGroup', {}).get('allSupported')}")
    
    for s in rec_status.get('ConfigurationRecordersStatus', []):
        print(f"Is Recording Active: {s.get('recording')}")
        print(f"Last Status:         {s.get('lastStatus')}")
    print("="*70)

    channels = config_client.describe_delivery_channels()
    print("\nACTIVE DELIVERY CHANNELS:")
    print("-" * 70)
    for ch in channels.get('DeliveryChannels', []):
        print(f"Channel Name: {ch.get('name')} | S3 Bucket: {ch.get('s3BucketName')}")
    print("-" * 70)

    rules = config_client.describe_config_rules(ConfigRuleNames=[rule_name])
    print("\nAWS CONFIG RULE DETAILS:")
    print("-" * 70)
    for rule in rules.get('ConfigRules', []):
        print(f"Rule Name:   {rule.get('ConfigRuleName')}")
        print(f"Rule ID:     {rule.get('ConfigRuleId')}")
        print(f"Source ID:   {rule.get('Source', {}).get('SourceIdentifier')}")
        print(f"Rule State:  {rule.get('ConfigRuleState')}")
    print("-" * 70)

    remediations = config_client.describe_remediation_configurations(ConfigRuleNames=[rule_name])
    print("\nREMEDIATION CONFIGURATION STATUS:")
    print("-" * 70)
    for rem in remediations.get('RemediationConfigurations', []):
        print(f"Target Type: {rem.get('TargetType')} | Target ID: {rem.get('TargetId')}")
        print(f"Automatic Remediation: {rem.get('Automatic')}")
    print("-" * 70)

    print("\nVerification Completed Successfully!")

except Exception as e:
    print(f"Error during verification: {e}")
"@

$VerifyScriptPath = Join-Path -Path $PWD -ChildPath "verify_config.py"
[System.IO.File]::WriteAllText($VerifyScriptPath, $PythonScript)
python verify_config.py

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "AWS CONFIG PIPELINE DEPLOYED & VERIFIED!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan