$awsEndpoint = "http://localhost:4566"
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$audioFileName = "speech_$timestamp.mp3"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Running Transcribe Audio Upload Client          " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

python generator.py $audioFileName
Start-Sleep -Seconds 3
Write-Host "Audio uploaded and processed!" -ForegroundColor Green
