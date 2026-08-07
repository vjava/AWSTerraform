# Combined AWS S3 Provisioning & Python Client Execution Script (.ps1)
# 1. Provisions 4 S3 Buckets with Encryption (AES256) and Basic Lifecycle Rules.
# 2. Runs an embedded Python client script to write, read, and display data from S3.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Ensure AWS S3 Module is loaded
if (Get-Module -ListAvailable -Name AWS.Tools.S3) {
    Import-Module AWS.Tools.S3
} elseif (Get-Module -ListAvailable -Name AWSPowerShell) {
    Import-Module AWSPowerShell
} else {
    Write-Error "AWS S3 PowerShell Module is missing. Please run:`nInstall-Module -Name AWS.Tools.S3 -AllowClobber -Force -Scope CurrentUser"
    exit
}

$Region = "us-east-1"
Set-DefaultAWSRegion -Region $Region

# Generate 4 unique bucket names
$RandomSuffix = Get-Random -Minimum 1000 -Maximum 9999
$BucketNames = @(
    "lab-app-data-$RandomSuffix",
    "lab-logs-$RandomSuffix",
    "lab-backups-$RandomSuffix",
    "lab-exports-$RandomSuffix"
)

Write-Host "=== STEP 1: Provisioning 4 S3 Buckets ===" -ForegroundColor Green

foreach ($BucketName in $BucketNames) {
    Write-Host "Creating Bucket: $BucketName..." -NoNewline
    
    # 1. Standard Bucket Operation: Create Bucket
    $null = New-S3Bucket -BucketName $BucketName -Region $Region

    # 2. Enforce Standard Encryption (SSE-S3 / AES256)
    Set-S3BucketEncryption -BucketName $BucketName -ServerSideEncryptionConfiguration_ServerSideEncryptionRule @(
        @{
            ServerSideEncryptionByDefault = @{
                ServerSideEncryptionAlgorithm = "AES256"
            }
        }
    )

    # 3. Apply Basic Lifecycle Rule (Transition to Standard-IA after 30 days for all objects)
    $Transition = New-Object Amazon.S3.Model.LifecycleTransition
    $Transition.Days = 30
    $Transition.StorageClass = [Amazon.S3.S3StorageClass]::StandardInfrequentAccess

    $LifecycleRule = New-Object Amazon.S3.Model.LifecycleRule
    $LifecycleRule.Id = "BasicArchiveRule"
    $LifecycleRule.Status = [Amazon.S3.LifecycleRuleStatus]::Enabled
    $LifecycleRule.Filter = New-Object Amazon.S3.Model.LifecycleFilter
    $LifecycleRule.Filter.LifecycleFilterPredicate = New-Object Amazon.S3.Model.LifecyclePrefixPredicate -Property @{ Prefix = "" }
    $LifecycleRule.Transitions = New-Object System.Collections.Generic.List[Amazon.S3.Model.LifecycleTransition]
    $LifecycleRule.Transitions.Add($Transition)

    # Write lifecycle configuration directly passing the rule array
    Write-S3LifecycleConfiguration -BucketName $BucketName -Configuration_Rule @($LifecycleRule)

    Write-Host " [DONE]" -ForegroundColor Green
}

# Target the first bucket for Python file operations
$TargetBucket = $BucketNames[0]

Write-Host "`n=== STEP 2: Executing Python S3 Client Operations ===" -ForegroundColor Green
Write-Host "Target Bucket: $TargetBucket" -ForegroundColor Cyan

# Define embedded Python client script code
$PythonCode = @"
import boto3
import sys

bucket_name = "$TargetBucket"
region = "$Region"
object_key = "demo_file.txt"
content = "Hello from S3! File created and read successfully via Python client."

try:
    s3_client = boto3.client('s3', region_name=region)

    print(f"1. Uploading '{object_key}' to '{bucket_name}'...")
    s3_client.put_object(
        Bucket=bucket_name,
        Key=object_key,
        Body=content.encode('utf-8'),
        ServerSideEncryption='AES256'
    )
    print("   Upload successful!")

    print(f"2. Fetching '{object_key}' from '{bucket_name}'...")
    response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
    retrieved_data = response['Body'].read().decode('utf-8')

    print("\n--- RETRIEVED FILE CONTENT ---")
    print(retrieved_data)
    print("------------------------------\n")

except Exception as e:
    print(f"Python Error: {e}")
    sys.exit(1)
"@

# Execute Python script directly via stdin
$PythonCode | python -

Write-Host "=== All Operations Completed Successfully ===" -ForegroundColor Green