# ==============================================================================
# COMPLETE AWS KINESIS DATA STREAM + FIREHOSE + S3 PIPELINE (main.ps1)
# ==============================================================================
Write-Host ">>> Initializing Kinesis Data Stream + Firehose + S3 Architecture..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# STEP 0: CLEAN UP PREVIOUS LOCAL STATE
# -----------------------------------------------------------------------------
Write-Host "`n[0/5] Purging previous local terraform state..." -ForegroundColor Yellow

$OldErrorAction = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"

Get-ChildItem -Path $PWD -Filter "*Copy*.tf" | Remove-Item -Force -ErrorAction SilentlyContinue

if (Test-Path "$PWD/terraform.tfstate") {
    Write-Host "Cleaning up old state..." -ForegroundColor Red
    Remove-Item "$PWD/terraform.tfstate" -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/terraform.tfstate.backup") {
    Remove-Item "$PWD/terraform.tfstate.backup" -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/.terraform") {
    Remove-Item "$PWD/.terraform" -Recurse -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/kinesis_producer.py") {
    Remove-Item "$PWD/kinesis_producer.py" -Force -ErrorAction SilentlyContinue
}

$ErrorActionPreference = $OldErrorAction
Write-Host "Environment cleaned and ready." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 1: DETECT REAL IAM ROLE NAME IN LAB
# -----------------------------------------------------------------------------
Write-Host "`n[1/5] Detecting IAM Role for Firehose..." -ForegroundColor Yellow

$LAB_ROLE_NAME = "firehoseDeliveryRole-32ee2431"

try {
    $roles = aws iam list-roles --query "Roles[*].RoleName" --output text 2>$null
    if ($roles -match "firehoseDeliveryRole-32ee2431") { $LAB_ROLE_NAME = "firehoseDeliveryRole-32ee2431" }
    elseif ($roles -match "firehoseDeliveryRole-c3006d3c") { $LAB_ROLE_NAME = "firehoseDeliveryRole-c3006d3c" }
    elseif ($roles -match "LabRole") { $LAB_ROLE_NAME = "LabRole" }
    elseif ($roles -match "voclabs") { $LAB_ROLE_NAME = "voclabs" }
} catch {
    # Fallback to default
}

Write-Host "Using IAM Role Name: $LAB_ROLE_NAME" -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 2: GENERATE TERRAFORM CONFIGURATION (main.tf)
# -----------------------------------------------------------------------------
Write-Host "`n[2/5] Generating Kinesis & S3 Terraform configuration..." -ForegroundColor Yellow

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
  name = "LAB_ROLE_PLACEHOLDER"
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
'@

$TerraformCode = $TerraformCode.Replace("LAB_ROLE_PLACEHOLDER", $LAB_ROLE_NAME)

[System.IO.File]::WriteAllText("$PWD/main.tf", $TerraformCode)
Write-Host "main.tf generated." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 3: EXECUTE TERRAFORM
# -----------------------------------------------------------------------------
Write-Host "`n[3/5] Initializing and Applying Terraform Configuration..." -ForegroundColor Yellow
terraform init -reconfigure

& terraform apply -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nTerraform deployment failed!" -ForegroundColor Red
    Write-Host "Note: If AccessDeniedException occurs, ensure your AWS IAM User has permissions for kinesis:CreateStream and iam:PassRole." -ForegroundColor Yellow
    exit 1
}

# -----------------------------------------------------------------------------
# STEP 4: EXTRACT OUTPUTS
# -----------------------------------------------------------------------------
Write-Host "`n[4/5] Extracting Infrastructure Details..." -ForegroundColor Yellow
$STREAM_NAME   = (terraform output -raw kinesis_stream_name)
$FIREHOSE_NAME = (terraform output -raw firehose_stream_name)
$BUCKET_NAME   = (terraform output -raw s3_bucket_name)

Write-Host "Kinesis Data Stream: $STREAM_NAME" -ForegroundColor Green
Write-Host "Firehose Delivery:   $FIREHOSE_NAME" -ForegroundColor Green
Write-Host "S3 Storage Bucket:   $BUCKET_NAME" -ForegroundColor Green

python -c "import boto3" 2>$null
if ($LASTEXITCODE -ne 0) {
    pip install boto3
}

# -----------------------------------------------------------------------------
# STEP 5: GENERATE & RUN PYTHON PRODUCER (Sends Records to Kinesis Data Stream)
# -----------------------------------------------------------------------------
Write-Host "`n[5/5] Executing Python Producer to Stream Data into Kinesis..." -ForegroundColor Yellow

$PythonScript = @"
import boto3
import json
import time
import random
import uuid

stream_name = '$STREAM_NAME'
bucket_name = '$BUCKET_NAME'
region = 'us-east-1'

kinesis_client = boto3.client('kinesis', region_name=region)
s3_client = boto3.client('s3', region_name=region)

print(f"Starting Continuous Record Producer to Kinesis Stream: {stream_name}\n")

device_ids = ['DEV-1001', 'DEV-1002', 'DEV-1003', 'DEV-1004']

for record_count in range(1, 21):
    payload = {
        "event_id": str(uuid.uuid4()),
        "device_id": random.choice(device_ids),
        "temperature": round(random.uniform(20.0, 85.0), 2),
        "humidity": round(random.uniform(30.0, 90.0), 2),
        "timestamp": time.time()
    }
    
    data_json = json.dumps(payload) + "\n"
    
    response = kinesis_client.put_record(
        StreamName=stream_name,
        Data=data_json,
        PartitionKey=payload['device_id']
    )
    
    print(f"[{time.strftime('%H:%M:%S')}] Sent Record #{record_count} -> SequenceNo: {response['SequenceNumber'][:20]}...")
    time.sleep(1)

print("\nAll 20 records sent to Kinesis Data Stream!")
print("Waiting for Firehose to flush data to S3 Bucket (60s buffer interval)...")
time.sleep(15)

try:
    response = s3_client.list_objects_v2(Bucket=bucket_name)
    if 'Contents' in response:
        print("\nS3 Bucket Storage Verification:")
        print("-" * 65)
        for obj in response['Contents']:
            print(f"File Key: {obj['Key']} | Size: {obj['Size']} Bytes")
        print("-" * 65)
    else:
        print("\nRecords are currently buffering in Firehose and will land in S3 within 60 seconds.")
except Exception as e:
    print(f"Error checking S3 bucket: {e}")
"@

[System.IO.File]::WriteAllText("$PWD/kinesis_producer.py", $PythonScript)
python kinesis_producer.py

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "KINESIS STREAM + FIREHOSE DEPLOYMENT COMPLETED!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan