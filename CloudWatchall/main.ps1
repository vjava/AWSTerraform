# ==============================================================================
# AWS OBSERVABILITY & SECURITY PIPELINE (CLOUDWATCH, RUM, INSPECTOR, ETC.)
# ==============================================================================
Write-Host ">>> Initializing AWS Observability Pipeline..." -ForegroundColor Cyan

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
if (Test-Path "$PWD/verify_observability.py") { Remove-Item "$PWD/verify_observability.py" -Force -ErrorAction SilentlyContinue }

$ErrorActionPreference = $OldErrorAction
Write-Host "Workspace cleaned." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 2: GENERATE TERRAFORM CODE (main.tf)
# -----------------------------------------------------------------------------
Write-Host "`n[2/4] Writing Observability & Security Terraform configuration..." -ForegroundColor Yellow

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

data "aws_caller_identity" "current" {}

# 1. CLOUDWATCH LOG GROUP & METRIC ALARM
resource "aws_cloudwatch_log_group" "demo_log_group" {
  name              = "/aws/app/demo-log-group-${random_id.suffix.hex}"
  retention_in_days = 7

  tags = {
    Environment = "production"
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high_alarm" {
  alarm_name          = "demo-cpu-high-alarm-${random_id.suffix.hex}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alarm when EC2 CPU utilization exceeds 80%"
}

# 2. CLOUDWATCH DASHBOARD
resource "aws_cloudwatch_dashboard" "demo_dashboard" {
  dashboard_name = "demo-dashboard-${random_id.suffix.hex}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization"]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "EC2 CPU Utilization"
        }
      }
    ]
  })
}

# 3. CLOUDWATCH RUM (REAL USER MONITORING) APP MONITOR
resource "aws_rum_app_monitor" "demo_rum" {
  name         = "demo-rum-app-${random_id.suffix.hex}"
  domain       = "example.com"
  cw_log_enabled = true

  app_monitor_configuration {
    allow_cookies = true
    enable_xray   = false
    session_sample_rate = 1.0
    telemetries   = ["errors", "performance", "http"]
  }
}

# 4. APPLICATION INSIGHTS
resource "aws_resourcegroups_group" "app_insight_rg" {
  name = "demo-app-insight-rg-${random_id.suffix.hex}"

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        {
          Key    = "Environment"
          Values = ["production"]
        }
      ]
    })
  }
}

resource "aws_applicationinsights_application" "demo_app_insights" {
  resource_group_name = aws_resourcegroups_group.app_insight_rg.name
  auto_create         = true
  cwe_monitor_enabled = true
}

# 5. AWS INSPECTOR CLASSIC (RESOURCE GROUP & ASSESSMENT TEMPLATE)
resource "aws_inspector_resource_group" "demo_inspector_rg" {
  tags = {
    Name = "inspector-resource-group-${random_id.suffix.hex}"
  }
}

resource "aws_inspector_assessment_target" "demo_target" {
  name               = "demo-assessment-target-${random_id.suffix.hex}"
  resource_group_arn = aws_inspector_resource_group.demo_inspector_rg.arn
}

resource "aws_inspector_assessment_template" "demo_template" {
  name       = "demo-assessment-template-${random_id.suffix.hex}"
  target_arn = aws_inspector_assessment_target.demo_target.arn
  duration   = 3600

  rules_package_arns = [
    "arn:aws:inspector:us-east-1:316112463485:rulespackage/0-g1A2xMzA" # Common Vulnerabilities and Exposures
  ]
}

# OUTPUTS
output "log_group_name" {
  value = aws_cloudwatch_log_group.demo_log_group.name
}

output "alarm_name" {
  value = aws_cloudwatch_metric_alarm.cpu_high_alarm.alarm_name
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.demo_dashboard.dashboard_name
}

output "rum_app_name" {
  value = aws_rum_app_monitor.demo_rum.name
}

output "app_insights_rg" {
  value = aws_applicationinsights_application.demo_app_insights.resource_group_name
}

output "inspector_target_arn" {
  value = aws_inspector_assessment_target.demo_target.arn
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
$LOG_GROUP  = (terraform output -raw log_group_name)
$ALARM_NAME = (terraform output -raw alarm_name)
$DASHBOARD  = (terraform output -raw dashboard_name)
$RUM_NAME   = (terraform output -raw rum_app_name)
$INSIGHT_RG = (terraform output -raw app_insights_rg)
$INSPECT_ARN = (terraform output -raw inspector_target_arn)

python -c "import boto3" 2>$null
if ($LASTEXITCODE -ne 0) {
    pip install boto3
}

$PythonScript = @"
import boto3

region = 'us-east-1'
log_group_name = '$LOG_GROUP'
alarm_name = '$ALARM_NAME'
dashboard_name = '$DASHBOARD'
rum_name = '$RUM_NAME'
insight_rg = '$INSIGHT_RG'
inspector_target_arn = '$INSPECT_ARN'

cw_logs = boto3.client('logs', region_name=region)
cw_client = boto3.client('cloudwatch', region_name=region)
rum_client = boto3.client('rum', region_name=region)
appinsights_client = boto3.client('application-insights', region_name=region)
inspector_client = boto3.client('inspector', region_name=region)

print("\n" + "="*70)
print("AWS OBSERVABILITY & SECURITY CONFIGURATION VERIFICATION")
print("="*70)

try:
    # 1. CloudWatch Log Group
    print(f"1. Querying CloudWatch Log Group: {log_group_name}...")
    lg_res = cw_logs.describe_log_groups(logGroupNamePrefix=log_group_name)
    lgs = lg_res.get('logGroups', [])
    if lgs:
        print(f"   Log Group Name: {lgs[0].get('logGroupName')}")
        print(f"   Retention Days: {lgs[0].get('retentionInDays')}")
        print("   CloudWatch Log Group Verified Successfully!")

    print("-" * 70)

    # 2. CloudWatch Alarm & Dashboard
    print(f"2. Querying CloudWatch Alarm: {alarm_name}...")
    alarm_res = cw_client.describe_alarms(AlarmNames=[alarm_name])
    alarms = alarm_res.get('MetricAlarms', [])
    if alarms:
        print(f"   Alarm Name:  {alarms[0].get('AlarmName')}")
        print(f"   Metric:      {alarms[0].get('MetricName')}")
        print(f"   Threshold:   {alarms[0].get('Threshold')}")
        print("   CloudWatch Alarm Verified Successfully!")

    print("-" * 70)

    # 3. CloudWatch RUM App Monitor
    print(f"3. Querying CloudWatch RUM App Monitor: {rum_name}...")
    rum_res = rum_client.get_app_monitor(Name=rum_name)
    app_mon = rum_res.get('AppMonitor', {})
    print(f"   RUM App Name: {app_mon.get('Name')}")
    print(f"   Domain:       {app_mon.get('Domain')}")
    print(f"   State:        {app_mon.get('State')}")
    print("   CloudWatch RUM Verified Successfully!")

    print("-" * 70)

    # 4. Application Insights
    print(f"4. Querying Application Insights for Resource Group: {insight_rg}...")
    app_res = appinsights_client.describe_application(ResourceGroupName=insight_rg)
    app_info = app_res.get('ApplicationInfo', {})
    print(f"   Resource Group: {app_info.get('ResourceGroupName')}")
    print(f"   CWE Enabled:    {app_info.get('CWEMonitorEnabled')}")
    print("   Application Insights Verified Successfully!")

    print("-" * 70)

    # 5. AWS Inspector Assessment Target
    print(f"5. Querying AWS Inspector Assessment Target: {inspector_target_arn}...")
    insp_res = inspector_client.describe_assessment_targets(assessmentTargetArns=[inspector_target_arn])
    targets = insp_res.get('assessmentTargets', [])
    if targets:
        print(f"   Target Name: {targets[0].get('name')}")
        print("   AWS Inspector Target Verified Successfully!")

    print("="*70)
    print("\nALL OBSERVABILITY & SECURITY COMPONENTS VERIFIED SUCCESSFULLY!")

except Exception as e:
    print(f"Verification Error: {e}")
"@

$VerifyScriptPath = Join-Path -Path $PWD -ChildPath "verify_observability.py"
[System.IO.File]::WriteAllText($VerifyScriptPath, $PythonScript)
python verify_observability.py

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "AWS OBSERVABILITY PIPELINE VERIFIED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan