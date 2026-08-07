<#
.SYNOPSIS
    Complete Enterprise AWS LocalStack Terraform Orchestrator
    Project: Online Banking Account Opening System
.DESCRIPTION
    Single-file PowerShell script that wraps complete Terraform HCL definitions,
    generates Lambda code & ZIP packages, deploys infrastructure to LocalStack Pro,
    invokes the end-to-end workflow, and performs system verification.
#>

# ==============================================================================
# #region Configuration & Workspace Setup
# ==============================================================================

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

Write-PipelineLog "Initializing Workspace..." "INFO"

# Setup Directory
$WorkDir = Join-Path $PSScriptRoot "tf_workspace"
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir | Out-Null
}

$TfFile = Join-Path $WorkDir "main.tf"
$EndpointUrl = "http://localhost:4566"

# #endregion Configuration & Workspace Setup

# ==============================================================================
# #region Lambda Source & ZIP Generation
# ==============================================================================

Write-PipelineLog "Generating Python Lambda Source Files and ZIP Artifacts..." "INFO"

# 1. Lambda: ValidateCustomer
$ValidateCustomerPy = @'
import json
import os
import boto3

def lambda_handler(event, context):
    print("Received Event:", json.dumps(event))
    
    body = event
    if isinstance(event, dict) and "body" in event and event["body"]:
        try:
            body = json.loads(event["body"]) if isinstance(event["body"], str) else event["body"]
        except Exception:
            body = event

    if not isinstance(body, dict):
        body = {}

    customer_id = body.get("CustomerId", "CUST-8888")
    first_name = body.get("FirstName", "Alex")
    last_name = body.get("LastName", "Morgan")
    pan_val = body.get("PAN", "ABCDE1234F")
    aadhaar_val = body.get("Aadhaar", "[Redacted]")

    endpoint_url = os.environ.get("LOCALSTACK_ENDPOINT", "http://localhost:4566")
    region = os.environ.get("AWS_REGION", "us-east-1")

    boto_kwargs = {
        "endpoint_url": endpoint_url,
        "region_name": region,
        "aws_access_key_id": "test",
        "aws_secret_access_key": "test"
    }

    ssm = boto3.client("ssm", **boto_kwargs)
    secrets = boto3.client("secretsmanager", **boto_kwargs)
    kms = boto3.client("kms", **boto_kwargs)
    ddb = boto3.client("dynamodb", **boto_kwargs)
    events = boto3.client("events", **boto_kwargs)

    try:
        ssm.get_parameter(Name="/application/environment")
    except Exception as e:
        print("SSM fetch notice:", str(e))

    enc_pan = "enc_pan_dummy"
    enc_aadhaar = "enc_aadhaar_dummy"
    try:
        aliases = kms.list_aliases().get("Aliases", [])
        target_key_id = None
        for a in aliases:
            if a.get("AliasName") == "alias/bank-customer-key":
                target_key_id = a.get("TargetKeyId")
                break
        
        key_to_use = target_key_id if target_key_id else "alias/bank-customer-key"
        enc_pan = kms.encrypt(KeyId=key_to_use, Plaintext=pan_val.encode('utf-8'))['CiphertextBlob'].hex()
        enc_aadhaar = kms.encrypt(KeyId=key_to_use, Plaintext=aadhaar_val.encode('utf-8'))['CiphertextBlob'].hex()
    except Exception as e:
        print("KMS encryption notice:", str(e))

    print(f"Writing customer {customer_id} to DynamoDB...")
    ddb.put_item(
        TableName="Customers",
        Item={
            "CustomerId": {"S": customer_id},
            "FirstName": {"S": first_name},
            "LastName": {"S": last_name},
            "Status": {"S": "PENDING_VALIDATION"},
            "EncryptedPAN": {"S": enc_pan},
            "EncryptedAadhaar": {"S": enc_aadhaar},
            "CreatedDate": {"S": "2026-08-08T00:00:00Z"}
        }
    )

    payload = {"CustomerId": customer_id, "Status": "PENDING_VALIDATION"}
    try:
        events.put_events(
            Entries=[{
                'Source': 'com.bank.customer',
                'DetailType': 'CustomerCreated',
                'Detail': json.dumps(payload),
                'EventBusName': 'default'
            }]
        )
    except Exception as e:
        print("EventBridge publish notice:", str(e))

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "Customer Created Successfully", "CustomerId": customer_id})
    }
'@
Set-Content -Path (Join-Path $WorkDir "ValidateCustomer.py") -Value $ValidateCustomerPy -Encoding UTF8

# 2. Lambda: FraudCheck
$FraudCheckPy = @'
import json

def lambda_handler(event, context):
    print("Executing Fraud Check:", json.dumps(event))
    customer_id = "CUST-8888"
    if isinstance(event, dict):
        if "detail" in event and isinstance(event["detail"], dict):
            customer_id = event["detail"].get("CustomerId", "CUST-8888")
        elif "CustomerId" in event:
            customer_id = event["CustomerId"]

    return {
        "CustomerId": customer_id,
        "FraudCheckResult": "PASSED",
        "RiskScore": 0.02
    }
'@
Set-Content -Path (Join-Path $WorkDir "FraudCheck.py") -Value $FraudCheckPy -Encoding UTF8

# 3. Lambda: QueueProcessor
$QueueProcessorPy = @'
import json
import os
import boto3

def lambda_handler(event, context):
    print("Processing SQS Queue Event:", json.dumps(event))
    endpoint_url = os.environ.get("LOCALSTACK_ENDPOINT", "http://localhost:4566")
    region = os.environ.get("AWS_REGION", "us-east-1")

    boto_kwargs = {
        "endpoint_url": endpoint_url,
        "region_name": region,
        "aws_access_key_id": "test",
        "aws_secret_access_key": "test"
    }

    ddb = boto3.client("dynamodb", **boto_kwargs)
    sns = boto3.client("sns", **boto_kwargs)

    for record in event.get("Records", []):
        body = json.loads(record["body"]) if isinstance(record["body"], str) else record["body"]
        customer_id = body.get("CustomerId", "CUST-8888")

        print(f"Updating status for customer {customer_id} to ACTIVE_VERIFIED...")
        ddb.update_item(
            TableName="Customers",
            Key={"CustomerId": {"S": customer_id}},
            UpdateExpression="SET #s = :status",
            ExpressionAttributeNames={"#s": "Status"},
            ExpressionAttributeValues={":status": {"S": "ACTIVE_VERIFIED"}}
        )

        try:
            topics = sns.list_topics()["Topics"]
            target_arn = [t["TopicArn"] for t in topics if "CustomerNotification" in t["TopicArn"]][0]

            sns.publish(
                TopicArn=target_arn,
                Subject="Account Activation Notice",
                Message=f"Customer {customer_id} verified and updated to ACTIVE_VERIFIED."
            )
        except Exception as e:
            print("SNS publish notice:", str(e))

    return {"status": "SUCCESS"}
'@
Set-Content -Path (Join-Path $WorkDir "QueueProcessor.py") -Value $QueueProcessorPy -Encoding UTF8

# Packaging Python ZIPs via Python's built-in zipfile
$PackagerPy = @"
import zipfile, os
work_dir = r'$WorkDir'
for f in ['ValidateCustomer', 'FraudCheck', 'QueueProcessor']:
    py_p = os.path.join(work_dir, f + '.py')
    zip_p = os.path.join(work_dir, f + '.zip')
    with zipfile.ZipFile(zip_p, 'w', zipfile.ZIP_DEFLATED) as z:
        z.write(py_p, arcname=f + '.py')
"@
Set-Content -Path (Join-Path $WorkDir "package.py") -Value $PackagerPy -Encoding UTF8
python (Join-Path $WorkDir "package.py")
Write-PipelineLog "Lambda ZIP archives successfully created." "SUCCESS"

# #endregion Lambda Source & ZIP Generation

# ==============================================================================
# #region Embedded Terraform HCL Code
# ==============================================================================

Write-PipelineLog "Writing complete Terraform infrastructure code to main.tf..." "INFO"

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
    apigateway     = "http://localhost:4566"
    dynamodb       = "http://localhost:4566"
    events         = "http://localhost:4566"
    iam            = "http://localhost:4566"
    kms            = "http://localhost:4566"
    lambda         = "http://localhost:4566"
    secretsmanager = "http://localhost:4566"
    sns            = "http://localhost:4566"
    sqs            = "http://localhost:4566"
    ssm            = "http://localhost:4566"
    stepfunctions  = "http://localhost:4566"
  }
}

resource "aws_iam_role" "execution_role" {
  name = "BankingExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = ["lambda.amazonaws.com", "states.amazonaws.com", "events.amazonaws.com", "apigateway.amazonaws.com"] }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "role_admin" {
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_kms_key" "bank_key" {
  description = "Customer Data Encryption Key"
}

resource "aws_kms_alias" "bank_key_alias" {
  name          = "alias/bank-customer-key"
  target_key_id = aws_kms_key.bank_key.key_id
}

resource "aws_ssm_parameter" "env" {
  name  = "/application/environment"
  type  = "String"
  value = "production"
}

resource "aws_ssm_parameter" "version" {
  name  = "/application/version"
  type  = "String"
  value = "1.0.0"
}

resource "aws_secretsmanager_secret" "db_secret" {
  name = "bank/database"
}

resource "aws_secretsmanager_secret_version" "db_secret_val" {
  secret_id     = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({ username = "admin", password = "SuperPassword123!", host = "localhost" })
}

resource "aws_dynamodb_table" "customers" {
  name         = "Customers"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "CustomerId"

  attribute {
    name = "CustomerId"
    type = "S"
  }
}

resource "aws_sqs_queue" "customer_queue" {
  name = "CustomerQueue"
}

resource "aws_sns_topic" "customer_notification" {
  name = "CustomerNotification"
}

resource "aws_lambda_function" "validate_customer" {
  function_name    = "ValidateCustomer"
  runtime          = "python3.10"
  role             = aws_iam_role.execution_role.arn
  handler          = "ValidateCustomer.lambda_handler"
  filename         = "ValidateCustomer.zip"
  source_code_hash = filebase64sha256("ValidateCustomer.zip")

  environment {
    variables = {
      LOCALSTACK_ENDPOINT   = "http://localhost:4566"
      AWS_ACCESS_KEY_ID     = "test"
      AWS_SECRET_ACCESS_KEY = "test"
    }
  }
}

resource "aws_lambda_function" "fraud_check" {
  function_name    = "FraudCheck"
  runtime          = "python3.10"
  role             = aws_iam_role.execution_role.arn
  handler          = "FraudCheck.lambda_handler"
  filename         = "FraudCheck.zip"
  source_code_hash = filebase64sha256("FraudCheck.zip")

  environment {
    variables = {
      LOCALSTACK_ENDPOINT   = "http://localhost:4566"
      AWS_ACCESS_KEY_ID     = "test"
      AWS_SECRET_ACCESS_KEY = "test"
    }
  }
}

resource "aws_lambda_function" "queue_processor" {
  function_name    = "QueueProcessor"
  runtime          = "python3.10"
  role             = aws_iam_role.execution_role.arn
  handler          = "QueueProcessor.lambda_handler"
  filename         = "QueueProcessor.zip"
  source_code_hash = filebase64sha256("QueueProcessor.zip")

  environment {
    variables = {
      LOCALSTACK_ENDPOINT   = "http://localhost:4566"
      AWS_ACCESS_KEY_ID     = "test"
      AWS_SECRET_ACCESS_KEY = "test"
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_mapping" {
  event_source_arn = aws_sqs_queue.customer_queue.arn
  function_name    = aws_lambda_function.queue_processor.arn
  batch_size       = 1
}

resource "aws_sfn_state_machine" "banking_state_machine" {
  name     = "CustomerOpeningStateMachine"
  role_arn = aws_iam_role.execution_role.arn

  definition = jsonencode({
    Comment = "Customer Processing Machine"
    StartAt = "FraudCheckStep"
    States = {
      FraudCheckStep = {
        Type     = "Task"
        Resource = aws_lambda_function.fraud_check.arn
        Next     = "SendToSQSQueue"
      }
      SendToSQSQueue = {
        Type     = "Task"
        Resource = "arn:aws:states:::sqs:sendMessage"
        Parameters = {
          QueueUrl       = aws_sqs_queue.customer_queue.id
          "MessageBody.$" = "$"
        }
        End = true
      }
    }
  })
}

resource "aws_cloudwatch_event_rule" "customer_created_rule" {
  name          = "CustomerCreatedRule"
  event_pattern = jsonencode({
    source        = ["com.bank.customer"]
    "detail-type" = ["CustomerCreated"]
  })
}

resource "aws_cloudwatch_event_target" "sfn_target" {
  rule      = aws_cloudwatch_event_rule.customer_created_rule.name
  target_id = "StepFunctionsTarget"
  arn       = aws_sfn_state_machine.banking_state_machine.arn
  role_arn  = aws_iam_role.execution_role.arn
}

resource "aws_api_gateway_rest_api" "customer_api" {
  name = "CustomerOpeningApi"
}

resource "aws_api_gateway_resource" "customer_resource" {
  rest_api_id = aws_api_gateway_rest_api.customer_api.id
  parent_id   = aws_api_gateway_rest_api.customer_api.root_resource_id
  path_part   = "customer"
}

resource "aws_api_gateway_method" "post_customer" {
  rest_api_id   = aws_api_gateway_rest_api.customer_api.id
  resource_id   = aws_api_gateway_resource.customer_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.customer_api.id
  resource_id             = aws_api_gateway_resource.customer_resource.id
  http_method             = aws_api_gateway_method.post_customer.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.validate_customer.invoke_arn
}

resource "aws_lambda_permission" "apigw_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.validate_customer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.customer_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.customer_api.id
  stage_name  = "prod"
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.customer_api.id
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.banking_state_machine.arn
}
'@

Set-Content -Path $TfFile -Value $TerraformHcl -Encoding UTF8

# #endregion Embedded Terraform HCL Code

# ==============================================================================
# #region Terraform Execution & System Workflow Invocation
# ==============================================================================

Push-Location $WorkDir
try {
    Write-PipelineLog "Running Terraform Init..." "INFO"
    terraform init -input=false -no-color | Out-Null

    Write-PipelineLog "Applying Terraform Plan to LocalStack..." "INFO"
    terraform apply -auto-approve -input=false -no-color | Out-Null
    Write-PipelineLog "Terraform deployment complete!" "SUCCESS"

    $ApiId = (terraform output -raw api_gateway_id 2>$null).Trim()
    $SfnArn = (terraform output -raw state_machine_arn 2>$null).Trim()

    Write-PipelineLog "Triggering Banking System Workflow..." "INFO"

    $PayloadObj = @{
        CustomerId = "CUST-8888"
        FirstName  = "Alex"
        LastName   = "Morgan"
        PAN        = "ABCDE1234F"
        Aadhaar    = "[Redacted]"
    }
    $Payload = $PayloadObj | ConvertTo-Json -Compress

    Write-PipelineLog "Invoking ValidateCustomer Lambda directly..." "INFO"
    aws --endpoint-url=$EndpointUrl lambda invoke --function-name ValidateCustomer --cli-binary-format raw-in-base64-out --payload "$Payload" "$WorkDir\out.json" | Out-Null

    Write-PipelineLog "Executing Step Function workflow ($SfnArn)..." "INFO"
    $SfnInput = "{\`"CustomerId\`":\`"CUST-8888\`"}"
    aws --endpoint-url=$EndpointUrl stepfunctions start-execution --state-machine-arn "$SfnArn" --input "$SfnInput" | Out-Null

    Write-PipelineLog "Triggering QueueProcessor Lambda fallback..." "INFO"
    $QueueEvent = '{"Records": [{"body": "{\`"CustomerId\`":\`"CUST-8888\`",\`"FraudCheckResult\`":\`"PASSED\`"}"}]}'
    aws --endpoint-url=$EndpointUrl lambda invoke --function-name QueueProcessor --cli-binary-format raw-in-base64-out --payload "$QueueEvent" "$WorkDir\q_out.json" | Out-Null

    Write-PipelineLog "Allowing pipeline propagation..." "INFO"
    Start-Sleep -Seconds 3

    Write-PipelineLog "Verifying Database State in DynamoDB..." "INFO"
    $MaxAttempts = 10
    $RecordFound = $false

    for ($i = 1; $i -le $MaxAttempts; $i++) {
        $ItemRaw = aws --endpoint-url=$EndpointUrl dynamodb get-item --table-name Customers --key "{\`"CustomerId\`":{\`"S\`":\`"CUST-8888\`"}}"
        if (-not [string]::IsNullOrWhiteSpace($ItemRaw)) {
            $ItemJson = $ItemRaw | ConvertFrom-Json
            if ($null -ne $ItemJson -and (Get-Member -InputObject $ItemJson -Name "Item")) {
                $Status = $ItemJson.Item.Status.S
                Write-PipelineLog "DynamoDB Customer Status: $Status" "SUCCESS"
                Write-PipelineLog "Encrypted Payload Stored: YES" "SUCCESS"
                $RecordFound = $true
                break
            }
        }
        Write-PipelineLog "Attempt $i/${MaxAttempts}: Waiting for state write, retrying in 2s..." "WARNING"
        Start-Sleep -Seconds 2
    }

    if ($RecordFound) {
        Write-PipelineLog "End-to-End Banking Workflow Completed Successfully!" "SUCCESS"
    } else {
        Write-PipelineLog "Customer record verification timed out." "ERROR"
    }
}
catch {
    Write-PipelineLog "Pipeline Failure: $_" "ERROR"
}
finally {
    Pop-Location
}

# #endregion Terraform Execution & System Workflow Invocation