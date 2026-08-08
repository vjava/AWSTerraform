# ==============================================================================
# Full LocalStack Pipeline with SFN, DLQ, API Gateway, Dual UI & Fixed Client
# ==============================================================================
$ErrorActionPreference = "Stop"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Starting Full LocalStack Pipeline Setup         " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# Step 1: Create Workspace Directory
$workspaceDir = Join-Path -Path $PSScriptRoot -ChildPath "workspace"
if (Test-Path -Path $workspaceDir) {
    Remove-Item -Path $workspaceDir -Recurse -Force
}
New-Item -Path $workspaceDir -ItemType Directory | Out-Null
Set-Location -Path $workspaceDir

Write-Host "[1/9] Workspace initialized at $workspaceDir" -ForegroundColor Green

# ------------------------------------------------------------------------------
# Step 2: Resource Cleanup (Deletes Attached Inline Policy BEFORE Role to avoid 409)
# ------------------------------------------------------------------------------
Write-Host "[2/9] Cleaning up existing LocalStack resources..." -ForegroundColor Yellow

$awsEndpoint = "http://localhost:4566"
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

$ErrorActionPreference = "SilentlyContinue"

# Cleanup S3 Bucket
aws --endpoint-url=$awsEndpoint s3 rb s3://raw-transactions-bucket --force >$null 2>&1

# Cleanup DynamoDB Table
aws --endpoint-url=$awsEndpoint dynamodb delete-table --table-name TransactionsTable >$null 2>&1

# Cleanup Step Functions State Machine
$sfnArn = (aws --endpoint-url=$awsEndpoint stepfunctions list-state-machines --query "stateMachines[?name=='CSVIngestionStateMachine'].stateMachineArn" --output text 2>$null)
if ($sfnArn) { aws --endpoint-url=$awsEndpoint stepfunctions delete-state-machine --state-machine-arn $sfnArn >$null 2>&1 }

# Cleanup Lambda Function
aws --endpoint-url=$awsEndpoint lambda delete-function --function-name ProcessTransactionLambda >$null 2>&1

# CRITICAL FIX: Delete Attached Inline Policy BEFORE Role
aws --endpoint-url=$awsEndpoint iam delete-role-policy --role-name apigateway_dynamodb_role --policy-name apigateway_access_policy >$null 2>&1

# Delete IAM Roles
aws --endpoint-url=$awsEndpoint iam delete-role --role-name lambda_execution_role >$null 2>&1
aws --endpoint-url=$awsEndpoint iam delete-role --role-name stepfunctions_execution_role >$null 2>&1
aws --endpoint-url=$awsEndpoint iam delete-role --role-name apigateway_dynamodb_role >$null 2>&1

# Delete SNS Topic
$topicArn = (aws --endpoint-url=$awsEndpoint sns list-topics --query "Topics[?contains(TopicArn, 'TransactionSuccessTopic')].TopicArn" --output text 2>$null)
if ($topicArn) { aws --endpoint-url=$awsEndpoint sns delete-topic --topic-arn $topicArn >$null 2>&1 }

# Delete SQS Queues
$queueUrl = (aws --endpoint-url=$awsEndpoint sqs get-queue-url --queue-name TransactionAuditQueue --query "QueueUrl" --output text 2>$null)
if ($queueUrl) { aws --endpoint-url=$awsEndpoint sqs delete-queue --queue-url $queueUrl >$null 2>&1 }

$dlqUrl = (aws --endpoint-url=$awsEndpoint sqs get-queue-url --queue-name TransactionDLQ --query "QueueUrl" --output text 2>$null)
if ($dlqUrl) { aws --endpoint-url=$awsEndpoint sqs delete-queue --queue-url $dlqUrl >$null 2>&1 }

$ErrorActionPreference = "Stop"
Write-Host "Cleanup completed successfully." -ForegroundColor Green

# ------------------------------------------------------------------------------
# Step 3: Write Application Source Files
# ------------------------------------------------------------------------------

# 3.1 generator.py
$generatorContent = @'
import csv
import random
import uuid
import sys
import boto3
from datetime import datetime, timezone

LOCALSTACK_ENDPOINT = "http://localhost:4566"
BUCKET_NAME = "raw-transactions-bucket"

def generate_mixed_transactions():
    records = []
    # 80 Valid Records
    for _ in range(80):
        records.append({
            "transaction_id": str(uuid.uuid4()),
            "user_id": f"USR_{random.randint(1000, 9999)}",
            "amount": round(random.uniform(10.0, 500.0), 2),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "status": "SUCCESS"
        })
    # 20 Corrupted/Invalid Records
    for i in range(20):
        records.append({
            "transaction_id": str(uuid.uuid4()) if i % 2 == 0 else "",
            "user_id": f"USR_{random.randint(1000, 9999)}" if i % 2 != 0 else "",
            "amount": -25.00 if i % 3 == 0 else "INVALID_AMOUNT",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "status": "CORRUPTED"
        })
    random.shuffle(records)
    return records

def save_to_csv(records, filename):
    fieldnames = ["transaction_id", "user_id", "amount", "timestamp", "status"]
    with open(filename, mode="w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(records)

def upload_to_s3(filename, bucket):
    s3_client = boto3.client(
        "s3",
        endpoint_url=LOCALSTACK_ENDPOINT,
        aws_access_key_id="test",
        aws_secret_access_key="test",
        region_name="us-east-1"
    )
    s3_client.upload_file(filename, bucket, filename)
    print(f"[CLIENT] Uploaded '{filename}' (100 records) to S3 bucket '{bucket}'.")

if __name__ == "__main__":
    file_name = sys.argv[1] if len(sys.argv) > 1 else "transactions.csv"
    print(f"[CLIENT] Generating 100 new mock records (80 valid + 20 invalid)...")
    txs = generate_mixed_transactions()
    save_to_csv(txs, file_name)
    upload_to_s3(file_name, BUCKET_NAME)
'@
Set-Content -Path "generator.py" -Value $generatorContent

# 3.2 lambda_function.py
$lambdaContent = @'
import json
import csv
import os
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

LOCALSTACK_HOSTNAME = os.environ.get("LOCALSTACK_HOSTNAME", "localhost")
EDGE_PORT = os.environ.get("EDGE_PORT", "4566")
ENDPOINT_URL = f"http://{LOCALSTACK_HOSTNAME}:{EDGE_PORT}"

s3_client = boto3.client("s3", endpoint_url=ENDPOINT_URL)
dynamodb = boto3.resource("dynamodb", endpoint_url=ENDPOINT_URL)
sqs_client = boto3.client("sqs", endpoint_url=ENDPOINT_URL)

TABLE_NAME = os.environ.get("TABLE_NAME", "TransactionsTable")
DLQ_URL = os.environ.get("DLQ_URL", "")

def validate_record(record):
    if not record.get("transaction_id"):
        return False, "Missing transaction_id"
    if not record.get("user_id"):
        return False, "Missing user_id"
    try:
        amount = float(record.get("amount", 0))
        if amount <= 0:
            return False, "Non-positive amount"
    except (ValueError, TypeError):
        return False, "Invalid numeric format"
    return True, "Valid"

def lambda_handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}")
    table = dynamodb.Table(TABLE_NAME)
    processed_count = 0
    invalid_count = 0

    detail = event.get("detail", {})
    bucket = detail.get("bucket", {}).get("name", "raw-transactions-bucket")
    key = detail.get("object", {}).get("key", "transactions.csv")
    
    response = s3_client.get_object(Bucket=bucket, Key=key)
    lines = response["Body"].read().decode("utf-8").splitlines()
    reader = csv.DictReader(lines)
    
    with table.batch_writer() as batch:
        for row in reader:
            is_valid, reason = validate_record(row)
            if is_valid:
                row["amount"] = str(row["amount"])
                batch.put_item(Item=row)
                processed_count += 1
            else:
                invalid_count += 1
                if DLQ_URL:
                    dlq_payload = {
                        "failed_record": row,
                        "rejection_reason": reason,
                        "source_file": key
                    }
                    sqs_client.send_message(
                        QueueUrl=DLQ_URL,
                        MessageBody=json.dumps(dlq_payload)
                    )

    return {
        "status": "COMPLETED",
        "processed_records": processed_count,
        "invalid_records": invalid_count,
        "source_file": key
    }
'@
Set-Content -Path "lambda_function.py" -Value $lambdaContent

# 3.3 sqs_consumer.py
$sqsConsumerContent = @'
import json
import boto3

LOCALSTACK_ENDPOINT = "http://localhost:4566"
sqs = boto3.client("sqs", endpoint_url=LOCALSTACK_ENDPOINT, aws_access_key_id="test", aws_secret_access_key="test", region_name="us-east-1")

def check_queues():
    queue_url = sqs.get_queue_url(QueueName="TransactionAuditQueue")["QueueUrl"]
    dlq_url = sqs.get_queue_url(QueueName="TransactionDLQ")["QueueUrl"]
    
    print("\n[CONSUMER] Audit Queue Check...")
    resp = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=5, WaitTimeSeconds=2)
    for msg in resp.get("Messages", []):
        body = json.loads(msg["Body"])
        payload = json.loads(body["Message"]) if "Message" in body else body
        print("========== SUCCESS AUDIT SUMMARY ==========")
        print(json.dumps(payload, indent=2))

    print("\n[CONSUMER] Dead Letter Queue (DLQ) Check...")
    attr = sqs.get_queue_attributes(QueueUrl=dlq_url, AttributeNames=["ApproximateNumberOfMessages"])
    print(f"DLQ contains {attr['Attributes'].get('ApproximateNumberOfMessages')} rejected items.")

if __name__ == "__main__":
    check_queues()
'@
Set-Content -Path "sqs_consumer.py" -Value $sqsConsumerContent

# 3.4 dashboard.html
$dashboardContent = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Transaction Ingestion Dashboard</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f4f7f6; margin: 0; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 25px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
        .btn { background-color: #3498db; color: white; border: none; padding: 10px 20px; font-size: 16px; border-radius: 5px; cursor: pointer; margin-right: 10px; }
        .btn:hover { background-color: #2980b9; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { text-align: left; padding: 12px; border-bottom: 1px solid #ddd; }
        th { background-color: #3498db; color: white; }
        .th-dlq { background-color: #e74c3c; }
        tr:hover { background-color: #f1f1f1; }
        .status-success { color: #27ae60; font-weight: bold; }
        .status-rejected { color: #c0392b; font-weight: bold; }
        .badge { background: #27ae60; color: white; padding: 4px 8px; border-radius: 4px; font-size: 13px; margin-right: 10px; }
        .badge-dlq { background: #e74c3c; }
        .section-title { margin-top: 30px; font-size: 20px; color: #34495e; border-bottom: 1px solid #ccc; padding-bottom: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>AWS LocalStack Pipeline Dashboard</h1>
        <div>
            <button class="btn" onclick="fetchAllData()">Refresh All Records</button>
            <span id="valid-count" class="badge">0 Valid Records (DynamoDB)</span>
            <span id="dlq-count" class="badge badge-dlq">0 DLQ Rejected Records (SQS)</span>
        </div>

        <div class="section-title">Valid Records (Ingested to DynamoDB via GET /transactions)</div>
        <table>
            <thead>
                <tr>
                    <th>Transaction ID</th>
                    <th>User ID</th>
                    <th>Amount ($)</th>
                    <th>Timestamp</th>
                    <th>Status</th>
                </tr>
            </thead>
            <tbody id="valid-table-body">
                <tr><td colspan="5">Click 'Refresh All Records' to load...</td></tr>
            </tbody>
        </table>

        <div class="section-title">Rejected Records (Captured in DLQ via GET /dlq)</div>
        <table>
            <thead>
                <tr>
                    <th class="th-dlq">Rejection Reason</th>
                    <th class="th-dlq">Transaction ID</th>
                    <th class="th-dlq">User ID</th>
                    <th class="th-dlq">Raw Amount</th>
                    <th class="th-dlq">Source File</th>
                </tr>
            </thead>
            <tbody id="dlq-table-body">
                <tr><td colspan="5">Click 'Refresh All Records' to load...</td></tr>
            </tbody>
        </table>
    </div>

    <script>
        const TRANSACTIONS_API = "API_GATEWAY_URL_PLACEHOLDER";
        const DLQ_API = "DLQ_API_URL_PLACEHOLDER";

        async function fetchAllData() {
            fetchValidTransactions();
            fetchDLQRecords();
        }

        async function fetchValidTransactions() {
            const tableBody = document.getElementById("valid-table-body");
            tableBody.innerHTML = "<tr><td colspan='5'>Loading DynamoDB records...</td></tr>";

            try {
                const response = await fetch(TRANSACTIONS_API);
                const data = await response.json();
                const items = data.Items || [];
                document.getElementById("valid-count").innerText = `${items.length} Valid Records (DynamoDB)`;

                if (items.length === 0) {
                    tableBody.innerHTML = "<tr><td colspan='5'>No valid records found in DynamoDB.</td></tr>";
                    return;
                }

                tableBody.innerHTML = "";
                items.forEach(item => {
                    const row = document.createElement("tr");
                    row.innerHTML = `
                        <td><code>${item.transaction_id.S}</code></td>
                        <td>${item.user_id.S}</td>
                        <td><strong>$${item.amount.S}</strong></td>
                        <td>${item.timestamp.S}</td>
                        <td class="status-success">${item.status.S}</td>
                    `;
                    tableBody.appendChild(row);
                });
            } catch (error) {
                tableBody.innerHTML = `<tr><td colspan='5' style='color:red;'>Error: ${error.message}</td></tr>`;
            }
        }

        async function fetchDLQRecords() {
            const tableBody = document.getElementById("dlq-table-body");
            tableBody.innerHTML = "<tr><td colspan='5'>Loading DLQ rejected messages...</td></tr>";

            try {
                const response = await fetch(DLQ_API);
                const data = await response.json();
                const messages = data.ReceiveMessageResponse?.ReceiveMessageResult?.Message || [];
                const msgList = Array.isArray(messages) ? messages : [messages];
                
                if (msgList.length === 0 || !messages) {
                    document.getElementById("dlq-count").innerText = "0 DLQ Rejected Records (SQS)";
                    tableBody.innerHTML = "<tr><td colspan='5'>No rejected records in DLQ.</td></tr>";
                    return;
                }

                document.getElementById("dlq-count").innerText = `${msgList.length} DLQ Rejected Records (SQS)`;
                tableBody.innerHTML = "";
                msgList.forEach(msg => {
                    const body = JSON.parse(msg.Body);
                    const rec = body.failed_record || {};
                    const row = document.createElement("tr");
                    row.innerHTML = `
                        <td class="status-rejected">${body.rejection_reason || 'Validation Failed'}</td>
                        <td><code>${rec.transaction_id || 'N/A (Missing)'}</code></td>
                        <td>${rec.user_id || 'N/A (Missing)'}</td>
                        <td><strong>${rec.amount || 'N/A'}</strong></td>
                        <td>${body.source_file || 'transactions.csv'}</td>
                    `;
                    tableBody.appendChild(row);
                });
            } catch (error) {
                tableBody.innerHTML = `<tr><td colspan='5' style='color:red;'>Error fetching DLQ: ${error.message}</td></tr>`;
            }
        }
    </script>
</body>
</html>
'@
Set-Content -Path "dashboard.html" -Value $dashboardContent

# 3.5 main.tf
$terraformContent = @'
terraform {
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
    s3            = "http://localhost:4566"
    dynamodb      = "http://localhost:4566"
    sns           = "http://localhost:4566"
    sqs           = "http://localhost:4566"
    lambda        = "http://localhost:4566"
    iam           = "http://localhost:4566"
    stepfunctions = "http://localhost:4566"
    events        = "http://localhost:4566"
    apigateway    = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "raw_bucket" {
  bucket        = "raw-transactions-bucket"
  force_destroy = true
}

resource "aws_dynamodb_table" "transactions" {
  name         = "TransactionsTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "transaction_id"

  attribute {
    name = "transaction_id"
    type = "S"
  }
}

resource "aws_sns_topic" "topic" {
  name = "TransactionSuccessTopic"
}

resource "aws_sqs_queue" "queue" {
  name = "TransactionAuditQueue"
}

resource "aws_sqs_queue" "dlq" {
  name = "TransactionDLQ"
}

resource "aws_sns_topic_subscription" "sns_to_sqs" {
  topic_arn = aws_sns_topic.topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.queue.arn
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role" "sfn_role" {
  name = "stepfunctions_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "states.amazonaws.com" } }]
  })
}

resource "aws_iam_role" "apigw_role" {
  name = "apigateway_dynamodb_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "apigw_policy" {
  name = "apigateway_access_policy"
  role = aws_iam_role.apigw_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["dynamodb:Scan", "dynamodb:GetItem"]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.transactions.arn
      },
      {
        Action   = ["sqs:ReceiveMessage", "sqs:GetQueueAttributes"]
        Effect   = "Allow"
        Resource = aws_sqs_queue.dlq.arn
      }
    ]
  })
}

resource "aws_lambda_function" "processor" {
  filename         = "lambda.zip"
  function_name    = "ProcessTransactionLambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.10"
  timeout          = 30
  source_code_hash = filebase64sha256("lambda.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.transactions.name
      DLQ_URL    = aws_sqs_queue.dlq.id
    }
  }
}

resource "aws_sfn_state_machine" "sfn_state_machine" {
  name     = "CSVIngestionStateMachine"
  role_arn = aws_iam_role.sfn_role.arn
  type     = "EXPRESS"

  definition = jsonencode({
    Comment = "Orchestrated CSV Ingestion Pipeline",
    StartAt = "ParseAndValidateCSV",
    States = {
      ParseAndValidateCSV = {
        Type     = "Task",
        Resource = aws_lambda_function.processor.arn,
        Next     = "PublishSuccessSNS"
      },
      PublishSuccessSNS = {
        Type     = "Task",
        Resource = "arn:aws:states:::sns:publish",
        Parameters = {
          TopicArn  = aws_sns_topic.topic.arn,
          Subject   = "Step Functions Pipeline Completed",
          "Message.$" = "$"
        },
        End = true
      }
    }
  })
}

resource "aws_api_gateway_rest_api" "api" {
  name = "TransactionServiceAPI"
}

resource "aws_api_gateway_resource" "transactions" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "transactions"
}

resource "aws_api_gateway_method" "get_transactions" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.transactions.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "dynamodb_scan" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.transactions.id
  http_method             = aws_api_gateway_method.get_transactions.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:us-east-1:dynamodb:action/Scan"
  credentials             = aws_iam_role.apigw_role.arn
  passthrough_behavior    = "WHEN_NO_MATCH"

  request_templates = {
    "application/json" = "{\"TableName\": \"TransactionsTable\"}"
  }
}

resource "aws_api_gateway_method_response" "resp_transactions_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.transactions.id
  http_method = aws_api_gateway_method.get_transactions.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "dynamodb_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.transactions.id
  http_method = aws_api_gateway_method.get_transactions.http_method
  status_code = aws_api_gateway_method_response.resp_transactions_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  response_templates = {
    "application/json" = "$input.json('$')"
  }

  depends_on = [aws_api_gateway_integration.dynamodb_scan]
}

resource "aws_api_gateway_resource" "dlq" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "dlq"
}

resource "aws_api_gateway_method" "get_dlq" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.dlq.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "sqs_dlq" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.dlq.id
  http_method             = aws_api_gateway_method.get_dlq.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:us-east-1:sqs:path/000000000000/TransactionDLQ"
  credentials             = aws_iam_role.apigw_role.arn
  passthrough_behavior    = "WHEN_NO_MATCH"

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-encoding'"
  }

  request_templates = {
    "application/json" = "Action=ReceiveMessage&MaxNumberOfMessages=10&VisibilityTimeout=0"
  }
}

resource "aws_api_gateway_method_response" "resp_dlq_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.dlq.id
  http_method = aws_api_gateway_method.get_dlq.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "sqs_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.dlq.id
  http_method = aws_api_gateway_method.get_dlq.http_method
  status_code = aws_api_gateway_method_response.resp_dlq_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  response_templates = {
    "application/json" = "$input.json('$')"
  }

  depends_on = [aws_api_gateway_integration.sqs_dlq]
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.dynamodb_scan,
    aws_api_gateway_integration.sqs_dlq
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}

output "transactions_api_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.api.id}/prod/_user_request_/transactions"
}

output "dlq_api_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.api.id}/prod/_user_request_/dlq"
}
'@
Set-Content -Path "main.tf" -Value $terraformContent

Write-Host "[3/9] All application source files generated." -ForegroundColor Green

# ------------------------------------------------------------------------------
# Step 4: Build Lambda Zip
# ------------------------------------------------------------------------------
Compress-Archive -Path "lambda_function.py" -DestinationPath "lambda.zip" -Force
Write-Host "[4/9] Lambda artifact packaged: lambda.zip" -ForegroundColor Green

# ------------------------------------------------------------------------------
# Step 5: Terraform Deployment
# ------------------------------------------------------------------------------
Write-Host "[5/9] Deploying infrastructure via Terraform..." -ForegroundColor Yellow
terraform init
terraform apply -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Error "Terraform deployment failed."
    exit $LASTEXITCODE
}

$transactionsApiUrl = (terraform output -raw transactions_api_url)
$dlqApiUrl = (terraform output -raw dlq_api_url)
Write-Host "[5/9] Infrastructure deployed successfully." -ForegroundColor Green

(Get-Content -Path "dashboard.html") -replace "API_GATEWAY_URL_PLACEHOLDER", $transactionsApiUrl -replace "DLQ_API_URL_PLACEHOLDER", $dlqApiUrl | Set-Content -Path "dashboard.html"

# ------------------------------------------------------------------------------
# Step 6: Create Standalone Local Client Script (FIXED POWERSHELL file:// INPUT)
# ------------------------------------------------------------------------------
$clientScriptContent = @'
# ==============================================================================
# Local Client Testing Tool (run_client.ps1) using file:// input fix
# ==============================================================================
$awsEndpoint = "http://localhost:4566"
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$fileName = "transactions_$timestamp.csv"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Running Local Client Test Ingestion             " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

Write-Host "[1/3] Executing Python generator for 100 NEW records ($fileName)..." -ForegroundColor Yellow
python generator.py $fileName

Write-Host "[2/3] Triggering AWS Step Functions State Machine..." -ForegroundColor Yellow
$stateMachineArn = (aws --endpoint-url=$awsEndpoint stepfunctions list-state-machines --query "stateMachines[?name=='CSVIngestionStateMachine'].stateMachineArn" --output text)

# Write payload to file to bypass PowerShell CLI JSON parsing issues
$payloadJson = '{"detail":{"bucket":{"name":"raw-transactions-bucket"},"object":{"key":"' + $fileName + '"}}}'
$payloadJson | Out-File -FilePath "input.json" -Encoding ascii

aws --endpoint-url=$awsEndpoint stepfunctions start-execution --state-machine-arn $stateMachineArn --input file://input.json >$null

Write-Host "Waiting 5 seconds for processing..." -ForegroundColor Cyan
Start-Sleep -Seconds 5

Write-Host "[3/3] Ingestion finished! Click 'Refresh All Records' on UI Dashboard." -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
'@
Set-Content -Path "run_client.ps1" -Value $clientScriptContent
Write-Host "[6/9] Created standalone local client script: run_client.ps1" -ForegroundColor Green

# ------------------------------------------------------------------------------
# Step 7: Initial Batch Processing via Client Script
# ------------------------------------------------------------------------------
Write-Host "[7/9] Running initial client batch ingestion..." -ForegroundColor Yellow
.\run_client.ps1

# ------------------------------------------------------------------------------
# Step 8: Consume Queues & Verify
# ------------------------------------------------------------------------------
Write-Host "[8/9] Running SQS Audit Check..." -ForegroundColor Yellow
python sqs_consumer.py

# ------------------------------------------------------------------------------
# Step 9: Launch UI Dashboard
# ------------------------------------------------------------------------------
Write-Host "[9/9] Launching Web UI Dashboard in default browser..." -ForegroundColor Green
$dashboardPath = Join-Path -Path (Get-Location) -ChildPath "dashboard.html"
Start-Process $dashboardPath

Write-Host "==================================================" -ForegroundColor Green
Write-Host " Pipeline Execution and Verification Complete!    " -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green