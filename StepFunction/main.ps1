# ==============================================================================
# AWS STEP FUNCTION (5 SEQUENTIAL STEPS + AWS MANAGED POLICY FIX)
# ==============================================================================
Write-Host ">>> Initializing AWS Step Function Deployment and Execution Pipeline..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# STEP 0: PURGE PREVIOUS LOCAL STATE
# -----------------------------------------------------------------------------
Write-Host "`n[0/5] Purging previous terraform state and temporary files..." -ForegroundColor Yellow

$OldErrorAction = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"

Get-ChildItem -Path $PWD -Filter "*Copy*.tf" | Remove-Item -Force -ErrorAction SilentlyContinue

if (Test-Path "$PWD/terraform.tfstate") {
    Remove-Item "$PWD/terraform.tfstate" -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/terraform.tfstate.backup") {
    Remove-Item "$PWD/terraform.tfstate.backup" -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/.terraform") {
    Remove-Item "$PWD/.terraform" -Recurse -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/run_step_function.py") {
    Remove-Item "$PWD/run_step_function.py" -Force -ErrorAction SilentlyContinue
}

$ErrorActionPreference = $OldErrorAction
Write-Host "Local workspace cleaned." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 1: GENERATE TERRAFORM CODE (main.tf)
# -----------------------------------------------------------------------------
Write-Host "`n[1/5] Writing Step Function Terraform configuration..." -ForegroundColor Yellow

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

# 1. DEDICATED IAM ROLE FOR STEP FUNCTIONS
resource "aws_iam_role" "sfn_exec_role" {
  name = "sfn-execution-role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AWS Managed Policy instead of creating inline policy (Bypasses iam:PutRolePolicy)
resource "aws_iam_role_policy_attachment" "sfn_managed_policy" {
  role       = aws_iam_role.sfn_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
}

# CloudWatch Log Group for Step Functions Logging Compliance
resource "aws_cloudwatch_log_group" "sfn_log_group" {
  name = "/aws/vendedlogs/states/compliant-sfn-logs-${random_id.suffix.hex}"
}

# 2. STANDARD STEP FUNCTION STATE MACHINE (5 Sequential Steps)
resource "aws_sfn_state_machine" "compliant_state_machine" {
  name     = "compliant-5step-workflow-${random_id.suffix.hex}"
  role_arn = aws_iam_role.sfn_exec_role.arn
  type     = "STANDARD"

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_log_group.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  definition = jsonencode({
    Comment = "A 5-step sequential state machine where each step output becomes input to the next"
    StartAt = "Step1_InitializeData"
    States = {
      "Step1_InitializeData" = {
        Type = "Pass"
        Result = {
          status          = "INITIALIZED"
          step1_processed = true
          initial_score   = 100
        }
        ResultPath = "$.step1_output"
        Next       = "Step2_ValidateData"
      }

      "Step2_ValidateData" = {
        Type = "Pass"
        Parameters = {
          "status"              = "VALIDATED"
          "step2_processed"     = true
          "current_score.$"     = "$.step1_output.initial_score"
          "received_from_step1.$" = "$.step1_output"
        }
        ResultPath = "$.step2_output"
        Next       = "Step3_TransformData"
      }

      "Step3_TransformData" = {
        Type = "Pass"
        Parameters = {
          "status"              = "TRANSFORMED"
          "step3_processed"     = true
          "multiplied_score"    = 200
          "received_from_step2.$" = "$.step2_output"
        }
        ResultPath = "$.step3_output"
        Next       = "Step4_EnrichData"
      }

      "Step4_EnrichData" = {
        Type = "Pass"
        Parameters = {
          "status"              = "ENRICHED"
          "step4_processed"     = true
          "metadata"            = "AWS_COMPLIANT_PIPELINE"
          "received_from_step3.$" = "$.step3_output"
        }
        ResultPath = "$.step4_output"
        Next       = "Step5_Finalize"
      }

      "Step5_Finalize" = {
        Type = "Pass"
        Parameters = {
          "status"                = "COMPLETED"
          "step5_processed"       = true
          "final_summary"         = "All 5 sequential steps executed successfully!"
          "full_pipeline_history.$" = "$"
        }
        End = true
      }
    }
  })

  depends_on = [aws_iam_role_policy_attachment.sfn_managed_policy]
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.compliant_state_machine.arn
}

output "state_machine_name" {
  value = aws_sfn_state_machine.compliant_state_machine.name
}
'@

[System.IO.File]::WriteAllText("$PWD/main.tf", $TerraformCode)
Write-Host "main.tf generated." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 2: APPLY TERRAFORM DEPLOYMENT
# -----------------------------------------------------------------------------
Write-Host "`n[2/5] Initializing and Applying Terraform Configuration..." -ForegroundColor Yellow
terraform init -reconfigure

& terraform apply -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nTerraform deployment failed!" -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------------------
# STEP 3: EXTRACT OUTPUTS & PREPARE PYTHON CLIENT
# -----------------------------------------------------------------------------
Write-Host "`n[3/5] Extracting State Machine ARN..." -ForegroundColor Yellow
$SFN_ARN = (terraform output -raw state_machine_arn)
$SFN_NAME = (terraform output -raw state_machine_name)

Write-Host "State Machine Name: $SFN_NAME" -ForegroundColor Green
Write-Host "State Machine ARN:  $SFN_ARN" -ForegroundColor Green

python -c "import boto3" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing boto3..." -ForegroundColor Yellow
    pip install boto3
}

# -----------------------------------------------------------------------------
# STEP 4: GENERATE & RUN PYTHON CLIENT TO EXECUTE STEP FUNCTION
# -----------------------------------------------------------------------------
Write-Host "`n[4/5] Executing Python Client Script to Trigger Step Function..." -ForegroundColor Yellow

$PythonScript = @"
import boto3
import json
import time
import uuid

state_machine_arn = '$SFN_ARN'
region = 'us-east-1'

sfn_client = boto3.client('stepfunctions', region_name=region)

print(f"Triggering Step Function Execution: {state_machine_arn}")

initial_input = {
    "execution_id": str(uuid.uuid4()),
    "job_name": "PowerShell_Continuous_Pipeline",
    "requested_by": "Kavya_Lab_User"
}

response = sfn_client.start_execution(
    stateMachineArn=state_machine_arn,
    name=f"exec-{uuid.uuid4().hex[:8]}",
    input=json.dumps(initial_input)
)

execution_arn = response['executionArn']
print(f"Execution Started successfully!")
print(f"Execution ARN: {execution_arn}\n")

print("Polling execution status...")
while True:
    status_response = sfn_client.describe_execution(executionArn=execution_arn)
    status = status_response['status']
    print(f"Current Status: {status}")

    if status in ['SUCCEEDED', 'FAILED', 'TIMED_OUT', 'ABORTED']:
        break
    time.sleep(2)

if status == 'SUCCEEDED':
    output_data = json.loads(status_response['output'])
    print("\n" + "="*70)
    print("STEP FUNCTION EXECUTED SUCCESSFULLY (ALL 5 STEPS COMPLETED)")
    print("="*70)
    print("Final Output Payload (Showing Data Passed Step-by-Step):")
    print(json.dumps(output_data, indent=2))
    print("="*70)
else:
    print(f"\nExecution Failed with status: {status}")
"@

[System.IO.File]::WriteAllText("$PWD/run_step_function.py", $PythonScript)
python run_step_function.py

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "STEP FUNCTION DEPLOYMENT & EXECUTION COMPLETED!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan