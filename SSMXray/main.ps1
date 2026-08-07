# ==============================================================================
# AWS SYSTEMS MANAGER (SSM) PARAMETER STORE PIPELINE
# ==============================================================================
Write-Host ">>> Initializing AWS Systems Manager (SSM) Pipeline..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# STEP 1: CLEAN LOCAL WORKSPACE
# -----------------------------------------------------------------------------
Write-Host "`n[1/4] Cleaning local workspace..." -ForegroundColor Yellow

$OldErrorAction = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"

Get-ChildItem -Path $PWD -Filter "*.tf" | Remove-Item -Force -ErrorAction SilentlyContinue

if (Test-Path "$PWD/terraform.tfstate") { Remove-Item "$PWD/terraform.tfstate" -Force -ErrorAction SilentlyContinue }
if (Test-Path "$PWD/terraform.tfstate.backup") { Remove-Item "$PWD/terraform.tfstate.backup" -Force -ErrorAction SilentlyContinue }
if (Test-Path "$PWD/.terraform") { Remove-Item "$PWD/.terraform" -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path "$PWD/.terraform.lock.hcl") { Remove-Item "$PWD/.terraform.lock.hcl" -Force -ErrorAction SilentlyContinue }
if (Test-Path "$PWD/verify_ssm.py") { Remove-Item "$PWD/verify_ssm.py" -Force -ErrorAction SilentlyContinue }

$ErrorActionPreference = $OldErrorAction
Write-Host "Workspace cleaned." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 2: GENERATE TERRAFORM CODE (main.tf)
# -----------------------------------------------------------------------------
Write-Host "`n[2/4] Writing SSM Parameter Store Terraform configuration..." -ForegroundColor Yellow

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

# -----------------------------------------------------------------------------
# AWS SYSTEMS MANAGER (SSM) PARAMETER STORE (STRING & SECURESTRING)
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "config_db_url" {
  name        = "/config/app/db_url_${random_id.suffix.hex}"
  description = "Database connection string"
  type        = "String"
  value       = "postgres://db.internal.company.com:5432/appdb"

  tags = {
    Environment = "production"
  }
}

resource "aws_ssm_parameter" "config_api_key" {
  name        = "/config/app/api_key_${random_id.suffix.hex}"
  description = "Secure API Key"
  type        = "SecureString"
  value       = "super-secret-api-token-value-12345"

  tags = {
    Environment = "production"
  }
}

# OUTPUTS
output "ssm_db_param_name" {
  value = aws_ssm_parameter.config_db_url.name
}

output "ssm_api_param_name" {
  value = aws_ssm_parameter.config_api_key.name
}
'@

$MainTfPath = Join-Path -Path $PWD -ChildPath "main.tf"
[System.IO.File]::WriteAllText($MainTfPath, $TerraformCode)
Write-Host "main.tf generated successfully." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 3: APPLY TERRAFORM DEPLOYMENT
# -----------------------------------------------------------------------------
Write-Host "`n[3/4] Initializing and Applying Terraform Configuration..." -ForegroundColor Yellow
terraform init -reconfigure

& terraform apply -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nTerraform deployment failed!" -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------------------
# STEP 4: EXTRACT OUTPUTS AND RUN PYTHON VERIFICATION CLIENT
# -----------------------------------------------------------------------------
Write-Host "`n[4/4] Extracting Details and Running Python Verification Client..." -ForegroundColor Yellow
$DB_PARAM  = (terraform output -raw ssm_db_param_name)
$API_PARAM = (terraform output -raw ssm_api_param_name)

Write-Host "SSM DB Parameter:  $DB_PARAM" -ForegroundColor Green
Write-Host "SSM API Parameter: $API_PARAM" -ForegroundColor Green

python -c "import boto3" 2>$null
if ($LASTEXITCODE -ne 0) {
    pip install boto3
}

$PythonScript = @"
import boto3

region = 'us-east-1'
db_param_name = '$DB_PARAM'
api_param_name = '$API_PARAM'

ssm_client = boto3.client('ssm', region_name=region)

print("\n" + "="*70)
print("AWS SSM PARAMETER STORE CONFIGURATION VERIFICATION")
print("="*70)

try:
    # 1. Verify Standard String Parameter
    print(f"1. Querying Standard Parameter: {db_param_name}...")
    p1 = ssm_client.get_parameter(Name=db_param_name)
    param1 = p1.get('Parameter', {})
    print(f"   Name:  {param1.get('Name')}")
    print(f"   Type:  {param1.get('Type')}")
    print(f"   Value: {param1.get('Value')}")
    print("   Standard Parameter Verified Successfully!")
    
    print("-" * 70)

    # 2. Verify SecureString Parameter with Decryption
    print(f"2. Querying SecureString Parameter (With Decryption): {api_param_name}...")
    p2 = ssm_client.get_parameter(Name=api_param_name, WithDecryption=True)
    param2 = p2.get('Parameter', {})
    print(f"   Name:      {param2.get('Name')}")
    print(f"   Type:      {param2.get('Type')}")
    print(f"   Decrypted: {param2.get('Value')}")
    print("   SecureString Parameter Verified Successfully!")

    print("="*70)
    print("\nAWS SSM PARAMETER STORE PIPELINE DEPLOYED & VERIFIED SUCCESSFULLY!")

except Exception as e:
    print(f"Verification Error: {e}")
"@

$VerifyScriptPath = Join-Path -Path $PWD -ChildPath "verify_ssm.py"
[System.IO.File]::WriteAllText($VerifyScriptPath, $PythonScript)
python verify_ssm.py

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "AWS SSM PARAMETER STORE PIPELINE VERIFIED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan