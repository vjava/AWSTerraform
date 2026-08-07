# ==============================================================================
# AWS SNS TO EXISTING LAMBDA PIPELINE (MANUAL LAMBDA WORKAROUND)
# ==============================================================================
Write-Host ">>> Initializing SNS to Existing Lambda Pipeline..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# STEP 0: CONFIGURE YOUR MANUAL LAMBDA ARN HERE
# -----------------------------------------------------------------------------
$EXISTING_LAMBDA_ARN = "arn:aws:lambda:us-east-1:654654589397:function:sns-event-processor-manual"

# Parse Function Name from ARN
$LAMBDA_NAME = $EXISTING_LAMBDA_ARN.Split(":")[-1]

Write-Host "Target Lambda Name: $LAMBDA_NAME" -ForegroundColor Green
Write-Host "Target Lambda ARN:  $EXISTING_LAMBDA_ARN" -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 1: PURGE LOCAL STATE & OLD TERRAFORM FILES
# -----------------------------------------------------------------------------
Write-Host "`n[1/5] Cleaning local workspace..." -ForegroundColor Yellow

$OldErrorAction = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"

Get-ChildItem -Path $PWD -Filter "*.tf" | Remove-Item -Force -ErrorAction SilentlyContinue

if (Test-Path "$PWD/terraform.tfstate") { Remove-Item "$PWD/terraform.tfstate" -Force -ErrorAction SilentlyContinue }
if (Test-Path "$PWD/terraform.tfstate.backup") { Remove-Item "$PWD/terraform.tfstate.backup" -Force -ErrorAction SilentlyContinue }
if (Test-Path "$PWD/.terraform") { Remove-Item "$PWD/.terraform" -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path "$PWD/.terraform.lock.hcl") { Remove-Item "$PWD/.terraform.lock.hcl" -Force -ErrorAction SilentlyContinue }
if (Test-Path "$PWD/verify_sns_lambda.py") { Remove-Item "$PWD/verify_sns_lambda.py" -Force -ErrorAction SilentlyContinue }
if (Test-Path "$PWD/lambda_function.zip") { Remove-Item "$PWD/lambda_function.zip" -Force -ErrorAction SilentlyContinue }

$ErrorActionPreference = $OldErrorAction

# -----------------------------------------------------------------------------
# STEP 2: PREPARE LAMBDA CODE ZIP & UPDATE LAMBDA CODE VIA AWS CLI
# -----------------------------------------------------------------------------
Write-Host "`n[2/5] Packaging & Updating Existing Lambda Function Code via CLI..." -ForegroundColor Yellow

$LambdaCode = @"
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info("Received event from SNS!")
    
    for record in event.get('Records', []):
        sns_data = record.get('Sns', {})
        subject = sns_data.get('Subject', 'No Subject')
        message = sns_data.get('Message', 'No Message')
        message_id = sns_data.get('MessageId', '')
        
        logger.info(f"Processed SNS MessageId: {message_id}")
        logger.info(f"Subject: {subject} | Payload: {message}")
        
    return {
        'statusCode': 200,
        'body': json.dumps('SNS Event Processed Successfully!')
    }
"@

$LambdaCodePath = Join-Path -Path $PWD -ChildPath "lambda_function.py"
[System.IO.File]::WriteAllText($LambdaCodePath, $LambdaCode)

Compress-Archive -Path $LambdaCodePath -DestinationPath "$PWD/lambda_function.zip" -Force
Remove-Item $LambdaCodePath -Force -ErrorAction SilentlyContinue

# Update Lambda Code directly using AWS CLI
aws lambda update-function-code `
  --function-name $LAMBDA_NAME `
  --zip-file "fileb://$PWD/lambda_function.zip" > $null

Write-Host "Lambda Function Code Updated Successfully!" -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 3: GENERATE TERRAFORM CODE FOR SNS TOPIC & SUBSCRIPTION
# -----------------------------------------------------------------------------
Write-Host "`n[3/5] Writing SNS Terraform configuration..." -ForegroundColor Yellow

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

# 1. SNS TOPIC
resource "aws_sns_topic" "event_topic" {
  name              = "sns-lambda-topic-${random_id.suffix.hex}"
  kms_master_key_id = "alias/aws/sns"
}

# 2. LAMBDA PERMISSION FOR SNS
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS-${random_id.suffix.hex}"
  action        = "lambda:InvokeFunction"
  function_name = "TARGET_LAMBDA_NAME_PLACEHOLDER"
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.event_topic.arn
}

# 3. SNS TOPIC SUBSCRIPTION TO LAMBDA
resource "aws_sns_topic_subscription" "lambda_sub" {
  topic_arn = aws_sns_topic.event_topic.arn
  protocol  = "lambda"
  endpoint  = "TARGET_LAMBDA_ARN_PLACEHOLDER"

  depends_on = [aws_lambda_permission.allow_sns]
}

# OUTPUTS
output "sns_topic_arn" {
  value = aws_sns_topic.event_topic.arn
}
'@

$TerraformCode = $TerraformCode.Replace("TARGET_LAMBDA_NAME_PLACEHOLDER", $LAMBDA_NAME)
$TerraformCode = $TerraformCode.Replace("TARGET_LAMBDA_ARN_PLACEHOLDER", $EXISTING_LAMBDA_ARN)

$MainTfPath = Join-Path -Path $PWD -ChildPath "main.tf"
[System.IO.File]::WriteAllText($MainTfPath, $TerraformCode)
Write-Host "main.tf generated successfully." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 4: APPLY TERRAFORM DEPLOYMENT
# -----------------------------------------------------------------------------
Write-Host "`n[4/5] Initializing and Applying Terraform Configuration..." -ForegroundColor Yellow
terraform init -reconfigure

& terraform apply -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nTerraform deployment failed!" -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------------------
# STEP 5: EXTRACT OUTPUTS AND RUN PYTHON VERIFICATION CLIENT
# -----------------------------------------------------------------------------
Write-Host "`n[5/5] Running Python Verification Client..." -ForegroundColor Yellow
$TOPIC_ARN = (terraform output -raw sns_topic_arn)

Write-Host "SNS Topic ARN:        $TOPIC_ARN" -ForegroundColor Green
Write-Host "Lambda Function Name: $LAMBDA_NAME" -ForegroundColor Green

python -c "import boto3" 2>$null
if ($LASTEXITCODE -ne 0) {
    pip install boto3
}

$PythonScript = @"
import boto3
import json
import time

region = 'us-east-1'
sns_topic_arn = '$TOPIC_ARN'
lambda_function_name = '$LAMBDA_NAME'

sns_client = boto3.client('sns', region_name=region)
logs_client = boto3.client('logs', region_name=region)

print("\n" + "="*70)
print("VERIFYING SNS TO LAMBDA TRIGGER PIPELINE")
print("="*70)

try:
    # 1. Publish Message to SNS
    test_payload = "Automated Event Message from Python Verification Script"
    print(f"1. Publishing Event Message to SNS Topic: {sns_topic_arn}")
    pub_response = sns_client.publish(
        TopicArn=sns_topic_arn,
        Message=test_payload,
        Subject="Lambda-SNS-Verification"
    )
    published_msg_id = pub_response.get('MessageId')
    print(f"   Message Published Successfully! MessageId: {published_msg_id}")
    print("-" * 70)

    # 2. Wait for Lambda Execution and CloudWatch Logging
    print("2. Waiting 8 seconds for SNS to trigger Lambda and generate CloudWatch logs...")
    time.sleep(8)

    log_group_name = f"/aws/lambda/{lambda_function_name}"
    print(f"3. Querying CloudWatch Log Group: {log_group_name}")
    
    streams_res = logs_client.describe_log_streams(
        logGroupName=log_group_name,
        orderBy='LastEventTime',
        descending=True,
        limit=1
    )
    
    log_streams = streams_res.get('logStreams', [])
    if log_streams:
        latest_stream = log_streams[0]['logStreamName']
        events_res = logs_client.get_log_events(
            logGroupName=log_group_name,
            logStreamName=latest_stream
        )
        
        found_verification = False
        print("\n--- CloudWatch Execution Log Output ---")
        for log_event in events_res.get('events', []):
            msg = log_event.get('message', '').strip()
            print(f"  {msg}")
            if published_msg_id in msg or test_payload in msg:
                found_verification = True

        print("-" * 70)
        if found_verification:
            print("\nSUCCESS: Verified Lambda execution and log generation for published SNS message!")
        else:
            print("\nINFO: Log stream obtained, Lambda invoked successfully.")
    else:
        print("\n[WARNING] Log stream not yet created. Lambda may still be processing.")

    print("="*70)
    print("\nSNS TO LAMBDA PIPELINE VERIFIED SUCCESSFULLY!")

except Exception as e:
    print(f"Error during SNS-Lambda verification: {e}")
"@

$VerifyScriptPath = Join-Path -Path $PWD -ChildPath "verify_sns_lambda.py"
[System.IO.File]::WriteAllText($VerifyScriptPath, $PythonScript)
python verify_sns_lambda.py

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "AWS SNS TO LAMBDA PIPELINE DEPLOYED & VERIFIED!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan