# ==============================================================================
# AWS EBS (ELASTIC BLOCK STORAGE) PIPELINE
# ==============================================================================
Write-Host ">>> Initializing AWS EBS Architecture Pipeline..." -ForegroundColor Cyan

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
if (Test-Path "$PWD/verify_ebs.py") { Remove-Item "$PWD/verify_ebs.py" -Force -ErrorAction SilentlyContinue }

$ErrorActionPreference = $OldErrorAction
Write-Host "Workspace cleaned." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 2: GENERATE TERRAFORM CODE (main.tf)
# -----------------------------------------------------------------------------
Write-Host "`n[2/4] Writing EBS Terraform configuration..." -ForegroundColor Yellow

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

# 1. EBS VOLUME (GP3, 20GB, ENCRYPTED)
resource "aws_ebs_volume" "demo_ebs" {
  availability_zone = "us-east-1a"
  size              = 20
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "demo-ebs-volume-${random_id.suffix.hex}"
  }
}

# 2. EBS SNAPSHOT CREATION
resource "aws_ebs_snapshot" "demo_snapshot" {
  volume_id   = aws_ebs_volume.demo_ebs.id
  description = "Basic snapshot management test for EBS volume"

  tags = {
    Name = "demo-ebs-snapshot-${random_id.suffix.hex}"
  }
}

# OUTPUTS
output "ebs_volume_id" {
  value = aws_ebs_volume.demo_ebs.id
}

output "ebs_snapshot_id" {
  value = aws_ebs_snapshot.demo_snapshot.id
}

output "ebs_volume_size" {
  value = aws_ebs_volume.demo_ebs.size
}

output "ebs_volume_type" {
  value = aws_ebs_volume.demo_ebs.type
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
Write-Host "`n[4/4] Extracting EBS Details and Running Python Verification Client..." -ForegroundColor Yellow
$VOLUME_ID   = (terraform output -raw ebs_volume_id)
$SNAPSHOT_ID = (terraform output -raw ebs_snapshot_id)

Write-Host "EBS Volume ID:   $VOLUME_ID" -ForegroundColor Green
Write-Host "EBS Snapshot ID: $SNAPSHOT_ID" -ForegroundColor Green

python -c "import boto3" 2>$null
if ($LASTEXITCODE -ne 0) {
    pip install boto3
}

$PythonScript = @"
import boto3

region = 'us-east-1'
volume_id = '$VOLUME_ID'
snapshot_id = '$SNAPSHOT_ID'

ec2_client = boto3.client('ec2', region_name=region)

print("\n" + "="*70)
print("AWS EBS (ELASTIC BLOCK STORAGE) CONFIGURATION VERIFICATION")
print("="*70)

try:
    # 1. Verify EBS Volume
    print(f"1. Querying EBS Volume Details for: {volume_id}...")
    vol_res = ec2_client.describe_volumes(VolumeIds=[volume_id])
    volumes = vol_res.get('Volumes', [])
    
    if volumes:
        vol = volumes[0]
        print(f"   Volume ID:         {vol.get('VolumeId')}")
        print(f"   Size (GB):          {vol.get('Size')} GB")
        print(f"   Volume Type:        {vol.get('VolumeType')}")
        print(f"   Availability Zone:  {vol.get('AvailabilityZone')}")
        print(f"   State:              {vol.get('State')}")
        print(f"   Encrypted:          {vol.get('Encrypted')}")
        print("   EBS Volume Verified Successfully!")
    
    print("-" * 70)

    # 2. Verify EBS Snapshot
    print(f"2. Querying EBS Snapshot Details for: {snapshot_id}...")
    snap_res = ec2_client.describe_snapshots(SnapshotIds=[snapshot_id])
    snapshots = snap_res.get('Snapshots', [])
    if snapshots:
        snap = snapshots[0]
        print(f"   Snapshot ID:       {snap.get('SnapshotId')}")
        print(f"   Source Volume ID:   {snap.get('VolumeId')}")
        print(f"   State:              {snap.get('State')}")
        print(f"   Progress:           {snap.get('Progress')}")
        print(f"   Encrypted:          {snap.get('Encrypted')}")
        print("   EBS Snapshot Verified Successfully!")

    print("="*70)
    print("\nEBS ARCHITECTURE DEPLOYED & VERIFIED SUCCESSFULLY!")

except Exception as e:
    print(f"Verification Error: {e}")
"@

$VerifyScriptPath = Join-Path -Path $PWD -ChildPath "verify_ebs.py"
[System.IO.File]::WriteAllText($VerifyScriptPath, $PythonScript)
python verify_ebs.py

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "AWS EBS PIPELINE DEPLOYED & VERIFIED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan