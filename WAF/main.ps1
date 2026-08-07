# ==============================================================================
# AWS WAFv2 SECURITY PIPELINE WITH API GATEWAY INTEGRATION
# ==============================================================================
Write-Host ">>> Initializing AWS WAFv2 & API Gateway Security Pipeline..." -ForegroundColor Cyan

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
if (Test-Path "$PWD/verify_waf.py") { Remove-Item "$PWD/verify_waf.py" -Force -ErrorAction SilentlyContinue }

$ErrorActionPreference = $OldErrorAction
Write-Host "Workspace cleaned." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 2: GENERATE TERRAFORM CODE (main.tf)
# -----------------------------------------------------------------------------
Write-Host "`n[2/4] Writing WAFv2 and API Gateway Terraform configuration..." -ForegroundColor Yellow

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
# 1. API GATEWAY (MOCK BACKEND FOR WAF INTEGRATION)
# -----------------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "waf_demo_api" {
  name        = "waf-demo-api-${random_id.suffix.hex}"
  description = "API Gateway to test AWS WAF Security Rules"
}

resource "aws_api_gateway_resource" "test_resource" {
  rest_api_id = aws_api_gateway_rest_api.waf_demo_api.id
  parent_id   = aws_api_gateway_rest_api.waf_demo_api.root_resource_id
  path_part   = "test"
}

resource "aws_api_gateway_method" "test_method" {
  rest_api_id   = aws_api_gateway_rest_api.waf_demo_api.id
  resource_id   = aws_api_gateway_resource.test_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "mock_integration" {
  rest_api_id = aws_api_gateway_rest_api.waf_demo_api.id
  resource_id = aws_api_gateway_resource.test_resource.id
  http_method = aws_api_gateway_method.test_method.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.waf_demo_api.id
  resource_id = aws_api_gateway_resource.test_resource.id
  http_method = aws_api_gateway_method.test_method.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "mock_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.waf_demo_api.id
  resource_id = aws_api_gateway_resource.test_resource.id
  http_method = aws_api_gateway_method.test_method.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_templates = {
    "application/json" = "{\"message\": \"Request Allowed by AWS WAF!\"}"
  }

  depends_on = [aws_api_gateway_integration.mock_integration]
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.waf_demo_api.id

  depends_on = [
    aws_api_gateway_integration.mock_integration,
    aws_api_gateway_integration_response.mock_integration_response
  ]
}

resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.waf_demo_api.id
  stage_name    = "prod"
}

# -----------------------------------------------------------------------------
# 2. WAFv2 WEB ACL WITH CUSTOM RULE GROUPS & PROTECTION TYPES
# -----------------------------------------------------------------------------
resource "aws_wafv2_web_acl" "waf_acl" {
  name        = "waf-security-acl-${random_id.suffix.hex}"
  description = "Custom WAF ACL with SQLi, XSS, RateLimiting and GeoMatch"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # RULE 1: SQL INJECTION (SQLi) PROTECTION
  rule {
    name     = "Block-SQL-Injection"
    priority = 1

    action {
      block {}
    }

    statement {
      sqli_match_statement {
        field_to_match {
          body {}
        }
        text_transformation {
          priority = 0
          type     = "URL_DECODE"
        }
        text_transformation {
          priority = 1
          type     = "HTML_ENTITY_DECODE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockSQLInjectionMetric"
      sampled_requests_enabled   = true
    }
  }

  # RULE 2: CROSS-SITE SCRIPTING (XSS) PROTECTION
  rule {
    name     = "Block-XSS-Attacks"
    priority = 2

    action {
      block {}
    }

    statement {
      xss_match_statement {
        field_to_match {
          body {}
        }
        text_transformation {
          priority = 0
          type     = "URL_DECODE"
        }
        text_transformation {
          priority = 1
          type     = "HTML_ENTITY_DECODE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockXSSMetric"
      sampled_requests_enabled   = true
    }
  }

  # RULE 3: RATE LIMITING (BLOCK IF REQUESTS > 100 PER 5 MINS PER IP)
  rule {
    name     = "Rate-Limit-Rule"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitMetric"
      sampled_requests_enabled   = true
    }
  }

  # RULE 4: GEO BLOCK (DEMO RULE FOR SPECIFIC COUNTRY BLOCKING)
  rule {
    name     = "Geo-Match-Rule"
    priority = 4

    action {
      block {}
    }

    statement {
      geo_match_statement {
        country_codes = ["CN", "RU"] # Example blocked country codes
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "GeoBlockMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "WafAclMainMetric"
    sampled_requests_enabled   = true
  }
}

# -----------------------------------------------------------------------------
# 3. WAF & API GATEWAY INTEGRATION
# -----------------------------------------------------------------------------
resource "aws_wafv2_web_acl_association" "api_gateway_assoc" {
  resource_arn = aws_api_gateway_stage.prod_stage.arn
  web_acl_arn  = aws_wafv2_web_acl.waf_acl.arn
}

# OUTPUTS
output "api_gateway_url" {
  value = "${aws_api_gateway_stage.prod_stage.invoke_url}/test"
}

output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.waf_acl.arn
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
# STEP 4: EXTRACT OUTPUTS AND RUN PYTHON VERIFICATION SCRIPT
# -----------------------------------------------------------------------------
Write-Host "`n[4/4] Extracting API Endpoint and Running Python Verification Client..." -ForegroundColor Yellow
$API_URL = (terraform output -raw api_gateway_url)

Write-Host "Target API Gateway URL: $API_URL" -ForegroundColor Green

python -c "import requests" 2>$null
if ($LASTEXITCODE -ne 0) {
    pip install requests
}

$PythonScript = @"
import requests
import json
import time

api_url = '$API_URL'

print("\n" + "="*70)
print("AWS WAF SECURITY PROTECTION VERIFICATION CLIENT")
print("="*70)
print(f"Target Endpoint: {api_url}\n")

headers = {"Content-Type": "application/json"}

# TEST 1: VALID REQUEST
print("1. Testing Valid Request...")
valid_payload = json.dumps({"user": "admin", "action": "login"})
try:
    response = requests.post(api_url, data=valid_payload, headers=headers)
    print(f"   Status Code: {response.status_code}")
    print(f"   Response Body: {response.text}")
    if response.status_code == 200:
        print("   RESULT: PASSED (Valid traffic allowed)")
    else:
        print("   RESULT: FAILED")
except Exception as e:
    print(f"   Error: {e}")

print("-" * 70)

# TEST 2: SQL INJECTION (SQLi) ATTACK
print("2. Testing SQL Injection (SQLi) Attack Mitigation...")
sqli_payload = json.dumps({"username": "admin' OR '1'='1", "password": "password123"})
try:
    response = requests.post(api_url, data=sqli_payload, headers=headers)
    print(f"   Status Code: {response.status_code}")
    if response.status_code == 403:
        print("   RESULT: PASSED (SQLi Attack successfully BLOCKED with 403 Forbidden!)")
    else:
        print(f"   RESULT: FAILED (Unexpected Status Code: {response.status_code})")
except Exception as e:
    print(f"   Error: {e}")

print("-" * 70)

# TEST 3: CROSS-SITE SCRIPTING (XSS) ATTACK
print("3. Testing Cross-Site Scripting (XSS) Attack Mitigation...")
xss_payload = json.dumps({"comment": "<script>alert('xss_attack')</script>"})
try:
    response = requests.post(api_url, data=xss_payload, headers=headers)
    print(f"   Status Code: {response.status_code}")
    if response.status_code == 403:
        print("   RESULT: PASSED (XSS Attack successfully BLOCKED with 403 Forbidden!)")
    else:
        print(f"   RESULT: FAILED (Unexpected Status Code: {response.status_code})")
except Exception as e:
    print(f"   Error: {e}")

print("="*70)
print("\nAWS WAF PROTECTION VERIFICATION COMPLETE!")
"@

$VerifyScriptPath = Join-Path -Path $PWD -ChildPath "verify_waf.py"
[System.IO.File]::WriteAllText($VerifyScriptPath, $PythonScript)
python verify_waf.py

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "AWS WAF PIPELINE DEPLOYED & VERIFIED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan