# ==============================================================================
# AWS SNS + SQS DECOUPLING PIPELINE (WITH DLQ & VERIFICATION)
# ==============================================================================
Write-Host ">>> Initializing AWS SNS/SQS Messaging Infrastructure Pipeline..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# STEP 0: PURGE PREVIOUS LOCAL STATE & OLD TERRAFORM FILES
# -----------------------------------------------------------------------------
Write-Host "`n[0/4] Purging previous terraform state and temporary files..." -ForegroundColor Yellow

$OldErrorAction = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"

Get-ChildItem -Path $PWD -Filter "*.tf" | Remove-Item -Force -ErrorAction SilentlyContinue

if (Test-Path "$PWD/terraform.tfstate") {
    Remove-Item "$PWD/terraform.tfstate" -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/terraform.tfstate.backup") {
    Remove-Item "$PWD/terraform.tfstate.backup" -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/.terraform") {
    Remove-Item "$PWD/.terraform" -Recurse -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/.terraform.lock.hcl") {
    Remove-Item "$PWD/.terraform.lock.hcl" -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/verify_messaging.py") {
    Remove-Item "$PWD/verify_messaging.py" -Force -ErrorAction SilentlyContinue
}

$ErrorActionPreference = $OldErrorAction
Write-Host "Local workspace cleaned." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 1: GENERATE TERRAFORM CODE (main.tf)
# -----------------------------------------------------------------------------
Write-Host "`n[1/4] Writing SNS/SQS Terraform configuration..." -ForegroundColor Yellow

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

# 1. SNS TOPIC
resource "aws_sns_topic" "user_updates" {
  name              = "user-updates-topic-${random_id.suffix.hex}"
  kms_master_key_id = "alias/aws/sns"
}

# 2. DEAD LETTER QUEUE (DLQ)
resource "aws_sqs_queue" "app_queue_dlq" {
  name                      = "app-processing-dlq-${random_id.suffix.hex}"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600 # 14 days retention
}

# 3. MAIN SQS QUEUE (WITH REDRIVE POLICY)
resource "aws_sqs_queue" "app_queue" {
  name                       = "app-processing-queue-${random_id.suffix.hex}"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 10 # Long polling
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.app_queue_dlq.arn
    maxReceiveCount     = 3
  })
}

# 4. SQS QUEUE POLICY (ALLOW SNS TO PUBLISH TO SQS)
resource "aws_sqs_queue_policy" "sqs_policy" {
  queue_url = aws_sqs_queue.app_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSNSTopicToPublish"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.app_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.user_updates.arn
          }
        }
      }
    ]
  })
}

# 5. SNS TO SQS SUBSCRIPTION
resource "aws_sns_topic_subscription" "sns_to_sqs" {
  topic_arn = aws_sns_topic.user_updates.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.app_queue.arn
}

# OUTPUTS
output "sns_topic_arn" {
  value = aws_sns_topic.user_updates.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.app_queue.id
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.app_queue.arn
}

output "dlq_queue_url" {
  value = aws_sqs_queue.app_queue_dlq.id
}
'@

$MainTfPath = Join-Path -Path $PWD -ChildPath "main.tf"
[System.IO.File]::WriteAllText($MainTfPath, $TerraformCode)
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
# STEP 3: EXTRACT OUTPUTS AND PREPARE PYTHON CLIENT
# -----------------------------------------------------------------------------
Write-Host "`n[3/4] Extracting Details and Running Python Verification Client..." -ForegroundColor Yellow
$TOPIC_ARN   = (terraform output -raw sns_topic_arn)
$QUEUE_URL   = (terraform output -raw sqs_queue_url)
$DLQ_URL     = (terraform output -raw dlq_queue_url)

Write-Host "SNS Topic ARN: $TOPIC_ARN" -ForegroundColor Green
Write-Host "SQS Queue URL: $QUEUE_URL" -ForegroundColor Green
Write-Host "DLQ Queue URL: $DLQ_URL" -ForegroundColor Green

python -c "import boto3" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing boto3..." -ForegroundColor Yellow
    pip install boto3
}

$PythonScript = @"
import boto3
import json
import time

region = 'us-east-1'
sns_topic_arn = '$TOPIC_ARN'
sqs_queue_url = '$QUEUE_URL'

sns_client = boto3.client('sns', region_name=region)
sqs_client = boto3.client('sqs', region_name=region)

print("\n" + "="*70)
print("VERIFYING SNS TO SQS MESSAGING PIPELINE")
print("="*70)

try:
    # 1. Publish Message to SNS
    message_body = "Hello from Terraform SNS-SQS Pipeline Verification!"
    print(f"Publishing Message to SNS Topic: {sns_topic_arn}")
    pub_response = sns_client.publish(
        TopicArn=sns_topic_arn,
        Message=message_body,
        Subject="Automated Verification"
    )
    print(f"Message Published! MessageId: {pub_response.get('MessageId')}")
    print("-" * 70)

    # 2. Wait for propagation and Consume Message from SQS
    print("Waiting 3 seconds for SNS message to propagate to SQS...")
    time.sleep(3)

    print(f"Polling SQS Queue: {sqs_queue_url}")
    sqs_response = sqs_client.receive_message(
        QueueUrl=sqs_queue_url,
        MaxNumberOfMessages=1,
        WaitTimeSeconds=5
    )

    messages = sqs_response.get('Messages', [])
    if messages:
        msg = messages[0]
        receipt_handle = msg['ReceiptHandle']
        parsed_body = json.loads(msg['Body'])
        
        print("\nMessage Received Successfully in SQS Queue:")
        print(f"  - Message Body Payload: {parsed_body.get('Message')}")
        print(f"  - SNS Topic Source:    {parsed_body.get('TopicArn')}")
        print(f"  - Original Subject:    {parsed_body.get('Subject')}")

        # Delete consumed message
        sqs_client.delete_message(
            QueueUrl=sqs_queue_url,
            ReceiptHandle=receipt_handle
        )
        print("Message deleted from SQS queue post-verification.")
        print("="*70)
        print("\nSNS/SQS Messaging Pipeline Verification Completed Successfully!")
    else:
        print("\n[ERROR] No messages retrieved from SQS Queue. Check Subscription policies.")

except Exception as e:
    print(f"Error during messaging verification: {e}")
"@

$VerifyScriptPath = Join-Path -Path $PWD -ChildPath "verify_messaging.py"
[System.IO.File]::WriteAllText($VerifyScriptPath, $PythonScript)
python verify_messaging.py

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "AWS SNS/SQS PIPELINE DEPLOYED & VERIFIED!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan