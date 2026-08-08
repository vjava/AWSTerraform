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
