# AWS S3 Max-Security Bucket Provisioning & Python Client Script (.ps1)
# Features Applied:
# - Strict Encryption (SSE-S3 AES256 with S3 Bucket Key)
# - Bucket Versioning Enabled
# - Complete Block Public Access (4/4 controls)
# - Basic Lifecycle Rules (Transition & Old Version Expiration)
# - Python Client File Creation & Read Execution

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

# Generate unique bucket name
$RandomSuffix = Get-Random -Minimum 1000 -Maximum 9999
$BucketName = "hardened-lab-bucket-$RandomSuffix"

Write-Host "=== STEP 1: Creating & Hardening S3 Bucket: $BucketName ===" -ForegroundColor Green

# 1. Create S3 Bucket
$null = New-S3Bucket -BucketName $BucketName -Region $Region
Write-Host "1. Bucket created." -ForegroundColor Cyan

# 2. Enable Bucket Versioning
Write-S3BucketVersioning -BucketName $BucketName -VersioningConfig_Status Enabled
Write-Host "2. Versioning enabled." -ForegroundColor Cyan

# 3. Block ALL Public Access (Max Security Policy via Add-S3PublicAccessBlock)
Add-S3PublicAccessBlock -BucketName $BucketName `
    -PublicAccessBlockConfiguration_BlockPublicAcl $true `
    -PublicAccessBlockConfiguration_BlockPublicPolicy $true `
    -PublicAccessBlockConfiguration_IgnorePublicAcl $true `
    -PublicAccessBlockConfiguration_RestrictPublicBucket $true
Write-Host "3. Block Public Access enforced (4/4 flags)." -ForegroundColor Cyan

# 4. Enforce Default Server-Side Encryption (AES256 + Bucket Key)
Set-S3BucketEncryption -BucketName $BucketName -ServerSideEncryptionConfiguration_ServerSideEncryptionRule @(
    @{
        ServerSideEncryptionByDefault = @{
            ServerSideEncryptionAlgorithm = "AES256"
        }
        BucketKeyEnabled = $true
    }
)
Write-Host "4. Default Encryption (SSE-S3 AES256) & Bucket Key enabled." -ForegroundColor Cyan

# 5. Apply Comprehensive Lifecycle Rules (Transition + Noncurrent Version Expiration)
$Transition = New-Object Amazon.S3.Model.LifecycleTransition
$Transition.Days = 30
$Transition.StorageClass = [Amazon.S3.S3StorageClass]::StandardInfrequentAccess

$NoncurrentExpiration = New-Object Amazon.S3.Model.LifecycleRuleNoncurrentVersionExpiration
$NoncurrentExpiration.NoncurrentDays = 90

$LifecycleRule = New-Object Amazon.S3.Model.LifecycleRule
$LifecycleRule.Id = "MaxPolicyLifecycleRule"
$LifecycleRule.Status = [Amazon.S3.LifecycleRuleStatus]::Enabled
$LifecycleRule.Filter = New-Object Amazon.S3.Model.LifecycleFilter
$LifecycleRule.Filter.LifecycleFilterPredicate = New-Object Amazon.S3.Model.LifecyclePrefixPredicate -Property @{ Prefix = "" }
$LifecycleRule.Transitions = New-Object System.Collections.Generic.List[Amazon.S3.Model.LifecycleTransition]
$LifecycleRule.Transitions.Add($Transition)
$LifecycleRule.NoncurrentVersionExpiration = $NoncurrentExpiration

Write-S3LifecycleConfiguration -BucketName $BucketName -Configuration_Rule @($LifecycleRule)
Write-Host "5. Lifecycle rules applied (30-day Standard-IA transition, 90-day version expiration)." -ForegroundColor Cyan

Write-Host "`n=== STEP 2: Executing Python Client Operations ===" -ForegroundColor Green

# Embedded Python Script to test writing, versioning, reading, and fetching metadata
$PythonCode = @"
import boto3
import sys

bucket_name = "$BucketName"
region = "$Region"
file_key = "secure_document.txt"

try:
    s3_client = boto3.client('s3', region_name=region)

    # 1. Upload Version 1 of file
    content_v1 = "Document Version 1: Initial creation."
    print(f"1. Uploading initial version of '{file_key}'...")
    res1 = s3_client.put_object(
        Bucket=bucket_name,
        Key=file_key,
        Body=content_v1.encode('utf-8'),
        ServerSideEncryption='AES256'
    )
    v1_id = res1.get('VersionId', 'N/A')
    print(f"   Success! Version ID: {v1_id}")

    # 2. Upload Version 2 of file to test versioning rule
    content_v2 = "Document Version 2: Updated content."
    print(f"2. Overwriting '{file_key}' to create Version 2...")
    res2 = s3_client.put_object(
        Bucket=bucket_name,
        Key=file_key,
        Body=content_v2.encode('utf-8'),
        ServerSideEncryption='AES256'
    )
    v2_id = res2.get('VersionId', 'N/A')
    print(f"   Success! New Version ID: {v2_id}")

    # 3. Read latest file version
    print(f"\n3. Reading latest version of '{file_key}'...")
    latest_obj = s3_client.get_object(Bucket=bucket_name, Key=file_key)
    latest_data = latest_obj['Body'].read().decode('utf-8')
    print(f"--- LATEST CONTENT ---\n{latest_data}\n----------------------")

    # 4. Read specific old version (Version 1) using Version ID
    if v1_id != 'N/A':
        print(f"4. Reading historical Version 1 (VersionId: {v1_id})...")
        v1_obj = s3_client.get_object(Bucket=bucket_name, Key=file_key, VersionId=v1_id)
        v1_data = v1_obj['Body'].read().decode('utf-8')
        print(f"--- HISTORICAL V1 CONTENT ---\n{v1_data}\n----------------------------")

except Exception as e:
    print(f"Python Execution Error: {e}")
    sys.exit(1)
"@

# Execute Python script directly via standard input
$PythonCode | python -

Write-Host "=== All Operations Completed Successfully ===" -ForegroundColor Green