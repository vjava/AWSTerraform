# ==============================================================================
# AWS ELASTIC BEANSTALK ALL-IN-ONE AUTOMATION SCRIPT
# ==============================================================================
$ErrorActionPreference = "Stop"
Write-Host ">>> Starting Elastic Beanstalk Automated Deployment..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# STEP 1: GENERATE TERRAFORM CODE (main.tf)
# -----------------------------------------------------------------------------
Write-Host "`n[1/6] Writing main.tf Terraform file..." -ForegroundColor Yellow

$TerraformCode = @'
terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_elastic_beanstalk_solution_stack" "python_latest" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux 2023 v.* running Python 3\\.11$"
}

variable "environment_tier" {
  type        = string
  default     = "WebServer"
}

variable "ebs_instance_profile" {
  type        = string
  default     = "ssm-role"
}

resource "aws_elastic_beanstalk_application" "app" {
  name        = "compliant-eb-app"
  description = "Elastic Beanstalk Application complying with platform and resource rules"
}

resource "aws_elastic_beanstalk_environment" "env" {
  name                = "compliant-eb-env"
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.python_latest.name
  tier                = var.environment_tier

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = var.ebs_instance_profile
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t3.micro"
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = "1"
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = "4"
  }
}

output "cname" {
  value = aws_elastic_beanstalk_environment.env.cname
}

output "application_name" {
  value = aws_elastic_beanstalk_application.app.name
}

output "environment_name" {
  value = aws_elastic_beanstalk_environment.env.name
}
'@

[System.IO.File]::WriteAllText("$PWD/main.tf", $TerraformCode)
Write-Host "main.tf generated." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 2: RUN TERRAFORM INIT & APPLY
# -----------------------------------------------------------------------------
Write-Host "`n[2/6] Running Terraform Init and Apply..." -ForegroundColor Yellow

terraform init
terraform apply -auto-approve

$AppName = (terraform output -raw application_name)
$EnvName = (terraform output -raw environment_name)
$CNAME   = (terraform output -raw cname)

Write-Host "Infrastructure provisioned: $AppName / $EnvName" -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 3: CREATE PYTHON APPLICATION FILES & ZIP BUNDLE
# -----------------------------------------------------------------------------
Write-Host "`n[3/6] Packaging Python Web Application..." -ForegroundColor Yellow

$AppDir = "$PWD/app_src"
New-Item -ItemType Directory -Path $AppDir -Force | Out-Null

$PythonCode = @'
from flask import Flask, jsonify

application = Flask(__name__)

@application.route("/")
def home():
    return jsonify({
        "status": "success",
        "message": "Hello from custom Python application deployed via single PS1 script!",
        "framework": "Flask"
    })

if __name__ == "__main__":
    application.run(host="0.0.0.0", port=5000)
'@
[System.IO.File]::WriteAllText("$AppDir/application.py", $PythonCode)

$ReqsCode = "flask==3.0.3`ngunicorn==22.0.0`n"
[System.IO.File]::WriteAllText("$AppDir/requirements.txt", $ReqsCode)

$ZipPath = "$PWD/app-bundle.zip"
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

Compress-Archive -Path "$AppDir/application.py", "$AppDir/requirements.txt" -DestinationPath $ZipPath -Force
Write-Host "Created deployment package: $ZipPath" -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 4: UPLOAD ZIP TO S3 & REGISTER BEANSTALK VERSION
# -----------------------------------------------------------------------------
Write-Host "`n[4/6] Uploading Bundle to S3 & Registering Version..." -ForegroundColor Yellow

$AccountId = (aws sts get-caller-identity --query "Account" --output text)
$Region    = "us-east-1"
$S3Bucket  = "elasticbeanstalk-$Region-$AccountId"
$S3Key     = "app-bundle-$(Get-Date -Format 'yyyyMMddHHmmss').zip"
$VersionLabel = "v1.0-ps1-deploy"

# Upload to Beanstalk S3 storage bucket
aws s3 cp $ZipPath "s3://$S3Bucket/$S3Key"

# Create application version
aws elasticbeanstalk create-application-version `
    --application-name $AppName `
    --version-label $VersionLabel `
    --description "Automated PS1 deployment" `
    --source-bundle S3Bucket="$S3Bucket",S3Key="$S3Key" | Out-Null

Write-Host "Version $VersionLabel registered successfully." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 5: DEPLOY VERSION & MONITOR PROGRESS
# -----------------------------------------------------------------------------
Write-Host "`n[5/6] Deploying $VersionLabel to $EnvName..." -ForegroundColor Yellow

aws elasticbeanstalk update-environment `
    --environment-name $EnvName `
    --version-label $VersionLabel | Out-Null

do {
    Start-Sleep -Seconds 10
    $EnvInfo = aws elasticbeanstalk describe-environments `
        --environment-names $EnvName `
        --query "Environments[0].[Status, Health, VersionLabel]" `
        --output text
    
    $Status, $Health, $ActiveVersion = $EnvInfo -split "`t"
    Write-Host "Deployment Status: $Status | Health: $Health | Version: $ActiveVersion" -ForegroundColor Yellow
} while ($Status -eq "Updating")

# -----------------------------------------------------------------------------
# STEP 6: VALIDATE ENDPOINT RESPONSE
# -----------------------------------------------------------------------------
Write-Host "`n[6/6] Validating Live Application Response..." -ForegroundColor Yellow

$URL = "http://$CNAME"
$Response = (Invoke-WebRequest -Uri $URL).Content

Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
Write-Host "URL: $URL" -ForegroundColor White
Write-Host "Response Payload:" -ForegroundColor White
Write-Host $Response -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan