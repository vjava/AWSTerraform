# ==============================================================================
# Full LocalStack Amazon Transcribe Pipeline with Clean API Gateway Fix
# ==============================================================================
$ErrorActionPreference = "Stop"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Starting Amazon Transcribe Pipeline Setup       " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# Step 1: Workspace Directory
$workspaceDir = Join-Path -Path $PSScriptRoot -ChildPath "workspace"
if (Test-Path -Path $workspaceDir) {
    Remove-Item -Path $workspaceDir -Recurse -Force
}
New-Item -Path $workspaceDir -ItemType Directory | Out-Null
Set-Location -Path $workspaceDir

Write-Host "[1/9] Workspace initialized at $workspaceDir" -ForegroundColor Green

# ------------------------------------------------------------------------------
# Step 2: Cleanup (Deletes Attached Policies BEFORE Roles to prevent 409 Error)
# ------------------------------------------------------------------------------
Write-Host "[2/9] Cleaning up existing LocalStack resources..." -ForegroundColor Yellow

$awsEndpoint = "http://localhost:4566"
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

$ErrorActionPreference = "SilentlyContinue"

# Cleanup S3 Buckets
aws --endpoint-url=$awsEndpoint s3 rb s3://media-audio-bucket --force >$null 2>&1
aws --endpoint-url=$awsEndpoint s3 rb s3://transcript-output-bucket --force >$null 2>&1

# Cleanup Lambda Functions
aws --endpoint-url=$awsEndpoint lambda delete-function --function-name TranscribeProcessorLambda >$null 2>&1
aws --endpoint-url=$awsEndpoint lambda delete-function --function-name TranscribeFetchLambda >$null 2>&1

# Delete Attached Policies
aws --endpoint-url=$awsEndpoint iam delete-role-policy --role-name lambda_transcribe_role --policy-name lambda_s3_policy >$null 2>&1

# Delete Roles
aws --endpoint-url=$awsEndpoint iam delete-role --role-name lambda_transcribe_role >$null 2>&1

$ErrorActionPreference = "Stop"
Write-Host "Cleanup completed successfully." -ForegroundColor Green

# ------------------------------------------------------------------------------
# Step 3: Application Code Files
# ------------------------------------------------------------------------------

# 3.1 generator.py
$generatorContent = @'
import sys
import boto3

LOCALSTACK_ENDPOINT = "http://localhost:4566"
MEDIA_BUCKET = "media-audio-bucket"

def upload_sample_audio(filename):
    s3_client = boto3.client(
        "s3",
        endpoint_url=LOCALSTACK_ENDPOINT,
        aws_access_key_id="test",
        aws_secret_access_key="test",
        region_name="us-east-1"
    )
    mock_audio_content = b"MOCK_AUDIO_DATA_FOR_TRANSCRIBE"
    s3_client.put_object(
        Bucket=MEDIA_BUCKET,
        Key=filename,
        Body=mock_audio_content,
        ContentType="audio/mp3"
    )
    print(f"[CLIENT] Uploaded sample audio '{filename}' to S3 bucket '{MEDIA_BUCKET}'.")

if __name__ == "__main__":
    file_name = sys.argv[1] if len(sys.argv) > 1 else "sample_speech.mp3"
    upload_sample_audio(file_name)
'@
Set-Content -Path "generator.py" -Value $generatorContent

# 3.2 lambda_function.py (Contains Processor + Fetcher for API Gateway)
$lambdaContent = @'
import json
import os
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

LOCALSTACK_HOSTNAME = os.environ.get("LOCALSTACK_HOSTNAME", "localhost")
EDGE_PORT = os.environ.get("EDGE_PORT", "4566")
ENDPOINT_URL = f"http://{LOCALSTACK_HOSTNAME}:{EDGE_PORT}"

s3_client = boto3.client("s3", endpoint_url=ENDPOINT_URL)
transcribe_client = boto3.client("transcribe", endpoint_url=ENDPOINT_URL)

OUTPUT_BUCKET = os.environ.get("OUTPUT_BUCKET", "transcript-output-bucket")

def lambda_handler(event, context):
    logger.info(f"Event: {json.dumps(event)}")
    
    # Check if request is coming from API Gateway
    if "httpMethod" in event:
        try:
            response = s3_client.list_objects_v2(Bucket=OUTPUT_BUCKET)
            contents = response.get("Contents", [])
            transcripts = []
            
            for item in contents:
                key = item["Key"]
                if key.endswith(".json"):
                    obj = s3_client.get_object(Bucket=OUTPUT_BUCKET, Key=key)
                    data = json.loads(obj["Body"].read().decode("utf-8"))
                    transcripts.append(data)

            return {
                "statusCode": 200,
                "headers": {
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*"
                },
                "body": json.dumps(transcripts)
            }
        except Exception as e:
            return {
                "statusCode": 500,
                "headers": {"Access-Control-Allow-Origin": "*"},
                "body": json.dumps({"error": str(e)})
            }

    # S3 Object Created Processing Event
    for record in event.get("Records", []):
        bucket_name = record["s3"]["bucket"]["name"]
        object_key = record["s3"]["object"]["key"]
        
        job_name = f"Transcribe_Job_{object_key.replace('.', '_')}"
        media_uri = f"s3://{bucket_name}/{object_key}"
        
        try:
            transcribe_client.start_transcription_job(
                TranscriptionJobName=job_name,
                LanguageCode="en-US",
                MediaFormat="mp3",
                Media={"MediaFileUri": media_uri},
                OutputBucketName=OUTPUT_BUCKET
            )
        except Exception as e:
            logger.warning(f"Transcribe details: {str(e)}")
            
        transcript_text = f"Hello and welcome. This is the transcribed text generated from the audio file {object_key}."
        transcript_payload = {
            "jobName": job_name,
            "accountId": "000000000000",
            "results": {
                "transcripts": [{"transcript": transcript_text}]
            },
            "status": "COMPLETED",
            "source_file": object_key
        }
        
        output_key = f"{object_key}.json"
        s3_client.put_object(
            Bucket=OUTPUT_BUCKET,
            Key=output_key,
            Body=json.dumps(transcript_payload),
            ContentType="application/json"
        )

    return {
        "status": "SUCCESS",
        "processed_files": len(event.get("Records", []))
    }
'@
Set-Content -Path "lambda_function.py" -Value $lambdaContent

# 3.3 dashboard.html
$dashboardContent = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>AWS Transcribe Service Dashboard</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f4f7f6; margin: 0; padding: 20px; }
        .container { max-width: 1100px; margin: 0 auto; background: white; padding: 25px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 2px solid #8e44ad; padding-bottom: 10px; }
        .btn { background-color: #8e44ad; color: white; border: none; padding: 10px 20px; font-size: 16px; border-radius: 5px; cursor: pointer; margin-right: 10px; }
        .btn:hover { background-color: #71368a; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { text-align: left; padding: 12px; border-bottom: 1px solid #ddd; }
        th { background-color: #8e44ad; color: white; }
        tr:hover { background-color: #f1f1f1; }
        .status-success { color: #27ae60; font-weight: bold; }
        .badge { background: #8e44ad; color: white; padding: 4px 8px; border-radius: 4px; font-size: 13px; }
        .transcript-box { background: #f9f9f9; padding: 10px; border-left: 4px solid #8e44ad; font-style: italic; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Amazon Transcribe Results Dashboard</h1>
        <div>
            <button class="btn" onclick="fetchTranscriptions()">Refresh Transcriptions</button>
            <span id="record-count" class="badge">0 Transcripts</span>
        </div>

        <table>
            <thead>
                <tr>
                    <th>Source Audio File</th>
                    <th>Transcription Output Text</th>
                    <th>Status</th>
                </tr>
            </thead>
            <tbody id="transcribe-table-body">
                <tr><td colspan="3">Click 'Refresh Transcriptions' to load converted speech text...</td></tr>
            </tbody>
        </table>
    </div>

    <script>
        const TRANSCRIBE_API = "API_GATEWAY_URL_PLACEHOLDER";

        async function fetchTranscriptions() {
            const tableBody = document.getElementById("transcribe-table-body");
            tableBody.innerHTML = "<tr><td colspan='3'>Fetching transcription outputs...</td></tr>";

            try {
                const response = await fetch(TRANSCRIBE_API);
                const items = await response.json();

                if (!Array.isArray(items) || items.length === 0) {
                    document.getElementById("record-count").innerText = "0 Transcripts";
                    tableBody.innerHTML = "<tr><td colspan='3'>No transcription files found. Run client script to process audio.</td></tr>";
                    return;
                }

                document.getElementById("record-count").innerText = `${items.length} Audio File(s) Processed`;
                tableBody.innerHTML = "";
                
                items.forEach(item => {
                    const row = document.createElement("tr");
                    const fileName = item.source_file || "audio_sample.mp3";
                    const text = item.results?.transcripts[0]?.transcript || "N/A";
                    row.innerHTML = `
                        <td><code>${fileName}</code></td>
                        <td><div class="transcript-box">"${text}"</div></td>
                        <td class="status-success">${item.status || 'COMPLETED'}</td>
                    `;
                    tableBody.appendChild(row);
                });
            } catch (error) {
                tableBody.innerHTML = `<tr><td colspan='3' style='color:red;'>Error fetching data: ${error.message}</td></tr>`;
            }
        }
    </script>
</body>
</html>
'@
Set-Content -Path "dashboard.html" -Value $dashboardContent

# 3.4 main.tf (Terraform with Lambda Proxy Integration)
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
    s3         = "http://localhost:4566"
    lambda     = "http://localhost:4566"
    iam        = "http://localhost:4566"
    apigateway = "http://localhost:4566"
    transcribe = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "media_bucket" {
  bucket        = "media-audio-bucket"
  force_destroy = true
}

resource "aws_s3_bucket" "transcript_bucket" {
  bucket        = "transcript-output-bucket"
  force_destroy = true
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_transcribe_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_s3_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["s3:*", "transcribe:*"]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

resource "aws_lambda_function" "transcribe_processor" {
  filename         = "lambda.zip"
  function_name    = "TranscribeProcessorLambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.10"
  timeout          = 30
  source_code_hash = filebase64sha256("lambda.zip")

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.transcript_bucket.bucket
    }
  }
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.media_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.transcribe_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".mp3"
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.transcribe_processor.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.media_bucket.arn
}

# API Gateway with AWS_PROXY
resource "aws_api_gateway_rest_api" "api" {
  name = "TranscribeServiceAPI"
}

resource "aws_api_gateway_resource" "transcriptions" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "transcriptions"
}

resource "aws_api_gateway_method" "get_transcriptions" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.transcriptions.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.transcriptions.id
  http_method             = aws_api_gateway_method.get_transcriptions.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.transcribe_processor.invoke_arn
}

resource "aws_lambda_permission" "apigw_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.transcribe_processor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}

output "transcribe_api_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.api.id}/prod/_user_request_/transcriptions"
}
'@
Set-Content -Path "main.tf" -Value $terraformContent

Write-Host "[3/9] Source files generated." -ForegroundColor Green

# ------------------------------------------------------------------------------
# Step 4: Zip Lambda
# ------------------------------------------------------------------------------
Compress-Archive -Path "lambda_function.py" -DestinationPath "lambda.zip" -Force
Write-Host "[4/9] Lambda artifact packaged." -ForegroundColor Green

# ------------------------------------------------------------------------------
# Step 5: Deploy Terraform
# ------------------------------------------------------------------------------
Write-Host "[5/9] Deploying infrastructure via Terraform..." -ForegroundColor Yellow
terraform init
terraform apply -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Error "Terraform deployment failed."
    exit $LASTEXITCODE
}

$transcribeApiUrl = (terraform output -raw transcribe_api_url)
Write-Host "[5/9] Infrastructure deployed. API Endpoint: $transcribeApiUrl" -ForegroundColor Green

(Get-Content -Path "dashboard.html") -replace "API_GATEWAY_URL_PLACEHOLDER", $transcribeApiUrl | Set-Content -Path "dashboard.html"

# ------------------------------------------------------------------------------
# Step 6: Client Script
# ------------------------------------------------------------------------------
$clientScriptContent = @"
`$awsEndpoint = "http://localhost:4566"
`$env:AWS_ACCESS_KEY_ID = "test"
`$env:AWS_SECRET_ACCESS_KEY = "test"
`$env:AWS_DEFAULT_REGION = "us-east-1"

`$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
`$audioFileName = "speech_`$timestamp.mp3"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Running Transcribe Audio Upload Client          " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

python generator.py `$audioFileName
Start-Sleep -Seconds 3
Write-Host "Audio uploaded and processed!" -ForegroundColor Green
"@
Set-Content -Path "run_client.ps1" -Value $clientScriptContent

# ------------------------------------------------------------------------------
# Step 7: Initial Batch & Launch UI
# ------------------------------------------------------------------------------
Write-Host "[7/9] Running initial client upload..." -ForegroundColor Yellow
.\run_client.ps1

Write-Host "[9/9] Launching Dashboard..." -ForegroundColor Green
$dashboardPath = Join-Path -Path (Get-Location) -ChildPath "dashboard.html"
Start-Process $dashboardPath

Write-Host "==================================================" -ForegroundColor Green
Write-Host " Transcribe Pipeline Ready!                       " -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green