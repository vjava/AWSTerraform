# ========================================================================
# LocalStack Enterprise Lambda Deployment Framework
# Version : 2.0
# ========================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ========================================================================
# Configuration
# ========================================================================

$Endpoint      = "http://localhost:4566"
$Region        = "us-east-1"

$FunctionName  = "hello-python"
$RoleName      = "lambda-role"

$Runtime       = "python3.12"
$Handler       = "lambda_function.lambda_handler"

$WorkingFolder = ".\lambda-demo"

# ========================================================================
# Banner
# ========================================================================

Clear-Host

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "     LocalStack Enterprise Lambda Deployment Framework"
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ========================================================================
# Create Working Folder
# ========================================================================

if (!(Test-Path $WorkingFolder))
{
    New-Item `
        -ItemType Directory `
        -Path $WorkingFolder | Out-Null
}

Set-Location $WorkingFolder

# ========================================================================
# Cleanup
# ========================================================================

Remove-Item lambda.zip -Force -ErrorAction SilentlyContinue
Remove-Item response.json -Force -ErrorAction SilentlyContinue

# ========================================================================
# Generate Lambda Source
# ========================================================================

Write-Host "Generating Python Lambda..." -ForegroundColor Yellow

@'
import json

def lambda_handler(event, context):

    print("========================================")
    print("Hello from LocalStack Lambda")
    print("Incoming Event:")
    print(event)
    print("========================================")

    return {
        "statusCode":200,
        "body":{
            "message":"Hello from LocalStack",
            "name":event.get("name"),
            "city":event.get("city")
        }
    }
'@ | Set-Content lambda_function.py

# ========================================================================
# Event Payload
# ========================================================================

@'
{
    "name":"Vidya",
    "city":"Bangalore"
}
'@ | Set-Content event.json

# ========================================================================
# IAM Trust Policy
# ========================================================================

@'
{
    "Version":"2012-10-17",
    "Statement":[
        {
            "Effect":"Allow",
            "Principal":{
                "Service":"lambda.amazonaws.com"
            },
            "Action":"sts:AssumeRole"
        }
    ]
}
'@ | Set-Content trust-policy.json

# ========================================================================
# Package Lambda
# ========================================================================

Write-Host "Packaging Lambda..." -ForegroundColor Yellow

Compress-Archive `
    -Path lambda_function.py `
    -DestinationPath lambda.zip `
    -Force

# ========================================================================
# IAM Role
# ========================================================================

Write-Host ""
Write-Host "Checking IAM Role..." -ForegroundColor Yellow

$RoleExists = $true

try
{
    aws `
        --endpoint-url=$Endpoint `
        iam get-role `
        --role-name $RoleName *> $null
}
catch
{
    $RoleExists = $false
}

if(!$RoleExists)
{
    Write-Host "Creating IAM Role..." -ForegroundColor Green

    aws `
        --endpoint-url=$Endpoint `
        iam create-role `
        --role-name $RoleName `
        --assume-role-policy-document file://trust-policy.json | Out-Null
}
else
{
    Write-Host "IAM Role already exists." -ForegroundColor Green
}

# ========================================================================
# Check Lambda
# ========================================================================

Write-Host ""
Write-Host "Checking Lambda..." -ForegroundColor Yellow

$LambdaExists = $true

try
{
    aws `
        --endpoint-url=$Endpoint `
        lambda get-function `
        --function-name $FunctionName *> $null
}
catch
{
    $LambdaExists = $false
}

# ========================================================================
# Deploy Lambda
# ========================================================================

if($LambdaExists)
{
    Write-Host "Updating Lambda..." -ForegroundColor Green

    aws `
        --endpoint-url=$Endpoint `
        lambda update-function-code `
        --function-name $FunctionName `
        --zip-file fileb://lambda.zip | Out-Null
}
else
{
    Write-Host "Creating Lambda..." -ForegroundColor Green

    aws `
        --endpoint-url=$Endpoint `
        lambda create-function `
        --function-name $FunctionName `
        --runtime $Runtime `
        --handler $Handler `
        --zip-file fileb://lambda.zip `
        --role arn:aws:iam::000000000000:role/$RoleName | Out-Null
}

# ========================================================================
# Wait Until Active
# ========================================================================

Write-Host ""
Write-Host "Waiting for Lambda to become ACTIVE..." -ForegroundColor Yellow

do
{
    Start-Sleep -Seconds 2

    $State = aws `
        --endpoint-url=$Endpoint `
        lambda get-function `
        --function-name $FunctionName `
        --query "Configuration.State" `
        --output text

    Write-Host "Current State : $State"

} while($State -ne "Active")

Write-Host ""
Write-Host "Lambda is ACTIVE" -ForegroundColor Green

# ========================================================================
# Invoke Lambda
# ========================================================================

Write-Host ""
Write-Host "Invoking Lambda..." -ForegroundColor Yellow

aws `
    --endpoint-url=$Endpoint `
    lambda invoke `
    --function-name $FunctionName `
    --cli-binary-format raw-in-base64-out `
    --payload file://event.json `
    response.json | Out-Null

# ========================================================================
# Display Response
# ========================================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "Lambda Response"
Write-Host "============================================================"

if(Test-Path response.json)
{
    $json = Get-Content response.json -Raw | ConvertFrom-Json
    $json | ConvertTo-Json -Depth 20
}
else
{
    Write-Host "No response generated." -ForegroundColor Red
}

# ========================================================================
# List Functions
# ========================================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "Available Lambda Functions"
Write-Host "============================================================"

aws `
    --endpoint-url=$Endpoint `
    lambda list-functions `
    --query "Functions[*].[FunctionName,Runtime,State,LastModified]" `
    --output table

# ========================================================================
# Recent Logs
# ========================================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "Recent LocalStack Logs"
Write-Host "============================================================"

docker logs localstack-main --tail 20

# ========================================================================
# Summary
# ========================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Deployment Completed Successfully" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green

Write-Host ""
Write-Host "Function Name : $FunctionName"
Write-Host "Runtime       : $Runtime"
Write-Host "Endpoint      : $Endpoint"
Write-Host ""