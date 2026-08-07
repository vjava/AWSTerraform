terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    apigateway     = "http://localhost:4566"
    dynamodb       = "http://localhost:4566"
    events         = "http://localhost:4566"
    iam            = "http://localhost:4566"
    kms            = "http://localhost:4566"
    lambda         = "http://localhost:4566"
    secretsmanager = "http://localhost:4566"
    sns            = "http://localhost:4566"
    sqs            = "http://localhost:4566"
    ssm            = "http://localhost:4566"
    stepfunctions  = "http://localhost:4566"
  }
}

resource "aws_iam_role" "execution_role" {
  name = "BankingExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = ["lambda.amazonaws.com", "states.amazonaws.com", "events.amazonaws.com", "apigateway.amazonaws.com"] }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "role_admin" {
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_kms_key" "bank_key" {
  description = "Customer Data Encryption Key"
}

resource "aws_kms_alias" "bank_key_alias" {
  name          = "alias/bank-customer-key"
  target_key_id = aws_kms_key.bank_key.key_id
}

resource "aws_ssm_parameter" "env" {
  name  = "/application/environment"
  type  = "String"
  value = "production"
}

resource "aws_ssm_parameter" "version" {
  name  = "/application/version"
  type  = "String"
  value = "1.0.0"
}

resource "aws_secretsmanager_secret" "db_secret" {
  name = "bank/database"
}

resource "aws_secretsmanager_secret_version" "db_secret_val" {
  secret_id     = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({ username = "admin", password = "SuperPassword123!", host = "localhost" })
}

resource "aws_dynamodb_table" "customers" {
  name         = "Customers"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "CustomerId"

  attribute {
    name = "CustomerId"
    type = "S"
  }
}

resource "aws_sqs_queue" "customer_queue" {
  name = "CustomerQueue"
}

resource "aws_sns_topic" "customer_notification" {
  name = "CustomerNotification"
}

resource "aws_lambda_function" "validate_customer" {
  function_name    = "ValidateCustomer"
  runtime          = "python3.10"
  role             = aws_iam_role.execution_role.arn
  handler          = "ValidateCustomer.lambda_handler"
  filename         = "ValidateCustomer.zip"
  source_code_hash = filebase64sha256("ValidateCustomer.zip")

  environment {
    variables = {
      LOCALSTACK_ENDPOINT   = "http://localhost:4566"
      AWS_ACCESS_KEY_ID     = "test"
      AWS_SECRET_ACCESS_KEY = "test"
    }
  }
}

resource "aws_lambda_function" "fraud_check" {
  function_name    = "FraudCheck"
  runtime          = "python3.10"
  role             = aws_iam_role.execution_role.arn
  handler          = "FraudCheck.lambda_handler"
  filename         = "FraudCheck.zip"
  source_code_hash = filebase64sha256("FraudCheck.zip")

  environment {
    variables = {
      LOCALSTACK_ENDPOINT   = "http://localhost:4566"
      AWS_ACCESS_KEY_ID     = "test"
      AWS_SECRET_ACCESS_KEY = "test"
    }
  }
}

resource "aws_lambda_function" "queue_processor" {
  function_name    = "QueueProcessor"
  runtime          = "python3.10"
  role             = aws_iam_role.execution_role.arn
  handler          = "QueueProcessor.lambda_handler"
  filename         = "QueueProcessor.zip"
  source_code_hash = filebase64sha256("QueueProcessor.zip")

  environment {
    variables = {
      LOCALSTACK_ENDPOINT   = "http://localhost:4566"
      AWS_ACCESS_KEY_ID     = "test"
      AWS_SECRET_ACCESS_KEY = "test"
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_mapping" {
  event_source_arn = aws_sqs_queue.customer_queue.arn
  function_name    = aws_lambda_function.queue_processor.arn
  batch_size       = 1
}

resource "aws_sfn_state_machine" "banking_state_machine" {
  name     = "CustomerOpeningStateMachine"
  role_arn = aws_iam_role.execution_role.arn

  definition = jsonencode({
    Comment = "Customer Processing Machine"
    StartAt = "FraudCheckStep"
    States = {
      FraudCheckStep = {
        Type     = "Task"
        Resource = aws_lambda_function.fraud_check.arn
        Next     = "SendToSQSQueue"
      }
      SendToSQSQueue = {
        Type     = "Task"
        Resource = "arn:aws:states:::sqs:sendMessage"
        Parameters = {
          QueueUrl       = aws_sqs_queue.customer_queue.id
          "MessageBody.$" = "$"
        }
        End = true
      }
    }
  })
}

resource "aws_cloudwatch_event_rule" "customer_created_rule" {
  name          = "CustomerCreatedRule"
  event_pattern = jsonencode({
    source        = ["com.bank.customer"]
    "detail-type" = ["CustomerCreated"]
  })
}

resource "aws_cloudwatch_event_target" "sfn_target" {
  rule      = aws_cloudwatch_event_rule.customer_created_rule.name
  target_id = "StepFunctionsTarget"
  arn       = aws_sfn_state_machine.banking_state_machine.arn
  role_arn  = aws_iam_role.execution_role.arn
}

resource "aws_api_gateway_rest_api" "customer_api" {
  name = "CustomerOpeningApi"
}

resource "aws_api_gateway_resource" "customer_resource" {
  rest_api_id = aws_api_gateway_rest_api.customer_api.id
  parent_id   = aws_api_gateway_rest_api.customer_api.root_resource_id
  path_part   = "customer"
}

resource "aws_api_gateway_method" "post_customer" {
  rest_api_id   = aws_api_gateway_rest_api.customer_api.id
  resource_id   = aws_api_gateway_resource.customer_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.customer_api.id
  resource_id             = aws_api_gateway_resource.customer_resource.id
  http_method             = aws_api_gateway_method.post_customer.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.validate_customer.invoke_arn
}

resource "aws_lambda_permission" "apigw_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.validate_customer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.customer_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.customer_api.id
  stage_name  = "prod"
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.customer_api.id
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.banking_state_machine.arn
}
