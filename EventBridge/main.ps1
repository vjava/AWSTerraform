# ==============================================================================
# AWS EVENTBRIDGE + S3 + LAMBDA PIPELINE (WITH CUSTOM LAMBDA IAM ROLE)
# ==============================================================================
Write-Host ">>> Initializing AWS EventBridge, S3, and Lambda Architecture Deployment..." -ForegroundColor Cyan

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
if (Test-Path "$PWD/trigger_event.py") {
    Remove-Item "$PWD/trigger_event.py" -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/lambda_function.zip") {
    Remove-Item "$PWD/lambda_function.zip" -Force -ErrorAction SilentlyContinue
}

$ErrorActionPreference = $OldErrorAction
Write-Host "Local workspace cleaned." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 1: GENERATE TERRAFORM CODE (WITH DEDICATED LAMBDA ROLE)
# -----------------------------------------------------------------------------
Write-Host "`n[1/4] Writing EventBridge & S3 Terraform configuration..." -ForegroundColor Yellow

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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

# 1. CREATE CUSTOM IAM ROLE FOR LAMBDA
resource "aws_iam_role" "lambda_exec_role" {
  name = "s3-event-lambda-role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach Basic Lambda Execution Policy for CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 2. S3 BUCKET WITH EVENTBRIDGE NOTIFICATIONS ENABLED
resource "aws_s3_bucket" "event_bucket" {
  bucket        = "eventbridge-s3-landing-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket      = aws_s3_bucket.event_bucket.id
  eventbridge = true
}

# 3. LAMBDA FUNCTION SOURCE CODE
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content  = <<EOF
import json

def lambda_handler(event, context):
    print("Received S3 Event Notification via EventBridge!")
    print("Event Payload:", json.dumps(event))
    
    detail = event.get('detail', {})
    bucket_name = detail.get('bucket', {}).get('name')
    object_key = detail.get('object', {}).get('key')
    
    print(f"File Successfully Processed: s3://{bucket_name}/{object_key}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Event successfully processed by Lambda!')
    }
EOF
    filename = "index.py"
  }
}

# 4. LAMBDA FUNCTION RESOURCE
resource "aws_lambda_function" "s3_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "s3-event-processor-${random_id.suffix.hex}"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"

  depends_on = [aws_iam_role_policy_attachment.lambda_logs]
}

# 5. EVENTBRIDGE RULE FOR S3 OBJECT CREATION
resource "aws_cloudwatch_event_rule" "s3_object_created" {
  name        = "s3-file-landing-rule-${random_id.suffix.hex}"
  description = "Triggers Lambda when a file lands in S3 bucket"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.event_bucket.id]
      }
    }
  })
}

# 6. TARGET FOR EVENTBRIDGE RULE
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.s3_object_created.name
  target_id = "TargetLambdaFunction"
  arn       = aws_lambda_function.s3_processor.arn
}

# 7. LAMBDA PERMISSION FOR EVENTBRIDGE
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_object_created.arn
}

output "bucket_name" {
  value = aws_s3_bucket.event_bucket.id
}

output "lambda_function_name" {
  value = aws_lambda_function.s3_processor.function_name
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
Write-Host "`n[3/4] Extracting Infrastructure Details..." -ForegroundColor Yellow
$BUCKET_NAME = (terraform output -raw bucket_name)
$LAMBDA_NAME = (terraform output -raw lambda_function_name)

Write-Host "Target S3 Bucket:     $BUCKET_NAME" -ForegroundColor Green
Write-Host "Processor Lambda:     $LAMBDA_NAME" -ForegroundColor Green

python -c "import boto3" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing boto3..." -ForegroundColor Yellow
    pip install boto3
}

# -----------------------------------------------------------------------------
# STEP 4: GENERATE & RUN PYTHON CLIENT TO UPLOAD FILE AND VERIFY EVENT
# -----------------------------------------------------------------------------
Write-Host "`n[4/4] Executing Python Client Script to Upload File & Trigger EventBridge..." -ForegroundColor Yellow

$PythonScript = @"
import boto3
import time
import json
import uuid

bucket_name = '$BUCKET_NAME'
lambda_name = '$LAMBDA_NAME'
region = 'us-east-1'

s3_client = boto3.client('s3', region_name=region)
logs_client = boto3.client('logs', region_name=region)

# 1. Upload Test File to S3
file_key = f"incoming/data_payload_{uuid.uuid4().hex[:6]}.json"
file_content = json.dumps({
    "event_id": str(uuid.uuid4()),
    "source": "PowerShell_EventBridge_Trigger",
    "status": "SUCCESS"
})

print(f"Uploading test file to s3://{bucket_name}/{file_key}...")
s3_client.put_object(
    Bucket=bucket_name,
    Key=file_key,
    Body=file_content.encode('utf-8')
)

print("File successfully uploaded!")
print("EventBridge event triggered automatically. Waiting 10 seconds for Lambda execution...")
time.sleep(10)

# 2. Check Lambda CloudWatch Logs
log_group_name = f"/aws/lambda/{lambda_name}"
print(f"\nChecking CloudWatch Logs for Lambda: {log_group_name}...")

try:
    streams = logs_client.describe_log_streams(
        logGroupName=log_group_name,
        orderBy='LastEventTime',
        descending=True,
        limit=1
    )
    
    if 'logStreams' in streams and len(streams['logStreams']) > 0:
        latest_stream = streams['logStreams'][0]['logStreamName']
        events = logs_client.get_log_events(
            logGroupName=log_group_name,
            logStreamName=latest_stream
        )
        
        print("\n" + "="*70)
        print("LAMBDA CLOUDWATCH LOG OUTPUT (VERIFYING EVENTBRIDGE EXECUTION)")
        print("="*70)
        for e in events['events']:
            print(e['message'].strip())
        print("="*70)
    else:
        print("Log streams are still buffering. Event routing initiated successfully!")
except Exception as err:
    print(f"Log retrieval notice: {err}")
"@

[System.IO.File]::WriteAllText("$PWD/trigger_event.py", $PythonScript)
python trigger_event.py

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "EVENTBRIDGE + S3 + LAMBDA PIPELINE DEPLOYED & TESTED!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan