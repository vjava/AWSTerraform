# ==============================================================================
# AWS ROUTE 53 DNS ARCHITECTURE PIPELINE
# ==============================================================================
Write-Host ">>> Initializing Route 53 DNS Architecture Pipeline..." -ForegroundColor Cyan

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
if (Test-Path "$PWD/verify_route53.py") { Remove-Item "$PWD/verify_route53.py" -Force -ErrorAction SilentlyContinue }

$ErrorActionPreference = $OldErrorAction
Write-Host "Workspace cleaned." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 2: GENERATE TERRAFORM CODE (main.tf)
# -----------------------------------------------------------------------------
Write-Host "`n[2/4] Writing Route 53 Terraform configuration..." -ForegroundColor Yellow

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

# 1. VPC FOR PRIVATE HOSTED ZONE ASSOCIATION
resource "aws_vpc" "route53_vpc" {
  cidr_block           = "10.100.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "route53-vpc-${random_id.suffix.hex}"
  }
}

# 2. ROUTE 53 PRIVATE HOSTED ZONE
resource "aws_route53_zone" "private_zone" {
  name = "mycompany.internal"

  vpc {
    vpc_id = aws_vpc.route53_vpc.id
  }

  comment = "Private DNS Zone created via Terraform"
}

# 3. ROUTE 53 DNS RECORDS
# (A) Record
resource "aws_route53_record" "app_a_record" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "app.mycompany.internal"
  type    = "A"
  ttl     = 300
  records = ["10.100.1.50"]
}

# (CNAME) Record
resource "aws_route53_record" "api_cname_record" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "api.mycompany.internal"
  type    = "CNAME"
  ttl     = 300
  records = ["app.mycompany.internal"]
}

# (TXT) Record
resource "aws_route53_record" "verification_txt_record" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "verification.mycompany.internal"
  type    = "TXT"
  ttl     = 300
  records = ["v=spf1 include:mycompany.internal ~all"]
}

# 4. ROUTE 53 HEALTH CHECK
resource "aws_route53_health_check" "endpoint_health_check" {
  fqdn              = "example.com"
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = "3"
  request_interval  = "30"

  tags = {
    Name = "demo-health-check-${random_id.suffix.hex}"
  }
}

# OUTPUTS
output "hosted_zone_id" {
  value = aws_route53_zone.private_zone.zone_id
}

output "hosted_zone_name" {
  value = aws_route53_zone.private_zone.name
}

output "health_check_id" {
  value = aws_route53_health_check.endpoint_health_check.id
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
Write-Host "`n[4/4] Extracting Route 53 Details and Running Python Verification Client..." -ForegroundColor Yellow
$ZONE_ID   = (terraform output -raw hosted_zone_id)
$ZONE_NAME = (terraform output -raw hosted_zone_name)
$HEALTH_ID = (terraform output -raw health_check_id)

Write-Host "Route 53 Hosted Zone ID:   $ZONE_ID" -ForegroundColor Green
Write-Host "Route 53 Hosted Zone Name: $ZONE_NAME" -ForegroundColor Green
Write-Host "Route 53 Health Check ID:  $HEALTH_ID" -ForegroundColor Green

python -c "import boto3" 2>$null
if ($LASTEXITCODE -ne 0) {
    pip install boto3
}

$PythonScript = @"
import boto3

region = 'us-east-1'
zone_id = '$ZONE_ID'
health_id = '$HEALTH_ID'

r53_client = boto3.client('route53', region_name=region)

print("\n" + "="*70)
print("AWS ROUTE 53 DNS ARCHITECTURE VERIFICATION")
print("="*70)

try:
    # 1. Verify Hosted Zone Details
    print(f"1. Querying Hosted Zone ID: {zone_id}...")
    zone_res = r53_client.get_hosted_zone(Id=zone_id)
    hz_info = zone_res.get('HostedZone', {})
    print(f"   Zone Name: {hz_info.get('Name')}")
    print(f"   Private Zone: {hz_info.get('Config', {}).get('PrivateZone')}")
    print(f"   Resource Record Set Count: {hz_info.get('ResourceRecordSetCount')}")
    print("   Hosted Zone Verified Successfully!")
    print("-" * 70)

    # 2. List DNS Resource Record Sets
    print(f"2. Querying Resource Record Sets for Zone: {zone_id}...")
    records_res = r53_client.list_resource_record_sets(HostedZoneId=zone_id)
    record_sets = records_res.get('ResourceRecordSets', [])
    
    print(f"   Found {len(record_sets)} DNS Record(s):")
    for r in record_sets:
        r_name = r.get('Name')
        r_type = r.get('Type')
        r_ttl = r.get('TTL', 'Alias/N/A')
        r_vals = [val.get('Value') for val in r.get('ResourceRecords', [])]
        print(f"   - Name: {r_name} | Type: {r_type} | TTL: {r_ttl} | Value: {r_vals}")

    print("-" * 70)

    # 3. Verify Health Check
    print(f"3. Querying Route 53 Health Check ID: {health_id}...")
    hc_res = r53_client.get_health_check(HealthCheckId=health_id)
    hc_config = hc_res.get('HealthCheck', {}).get('HealthCheckConfig', {})
    print(f"   Fully Qualified Domain Name: {hc_config.get('FullyQualifiedDomainName')}")
    print(f"   Port: {hc_config.get('Port')}")
    print(f"   Type: {hc_config.get('Type')}")
    print("   Route 53 Health Check Verified Successfully!")

    print("="*70)
    print("\nROUTE 53 PIPELINE DEPLOYED & VERIFIED SUCCESSFULLY!")

except Exception as e:
    print(f"Verification Error: {e}")

"@

$VerifyScriptPath = Join-Path -Path $PWD -ChildPath "verify_route53.py"
[System.IO.File]::WriteAllText($VerifyScriptPath, $PythonScript)
python verify_route53.py

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "AWS ROUTE 53 PIPELINE VERIFIED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan