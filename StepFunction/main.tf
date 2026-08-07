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