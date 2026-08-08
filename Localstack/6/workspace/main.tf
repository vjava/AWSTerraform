terraform {
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
  s3_use_path_style           = true

  endpoints {
    s3            = "http://localhost:4566"
    dynamodb      = "http://localhost:4566"
    sns           = "http://localhost:4566"
    sqs           = "http://localhost:4566"
    lambda        = "http://localhost:4566"
    iam           = "http://localhost:4566"
    stepfunctions = "http://localhost:4566"
    events        = "http://localhost:4566"
    apigateway    = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "raw_bucket" {
  bucket        = "raw-transactions-bucket"
  force_destroy = true
}

resource "aws_dynamodb_table" "transactions" {
  name         = "TransactionsTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "transaction_id"

  attribute {
    name = "transaction_id"
    type = "S"
  }
}

resource "aws_sns_topic" "topic" {
  name = "TransactionSuccessTopic"
}

resource "aws_sqs_queue" "queue" {
  name = "TransactionAuditQueue"
}

resource "aws_sqs_queue" "dlq" {
  name = "TransactionDLQ"
}

resource "aws_sns_topic_subscription" "sns_to_sqs" {
  topic_arn = aws_sns_topic.topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.queue.arn
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role" "sfn_role" {
  name = "stepfunctions_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "states.amazonaws.com" } }]
  })
}

resource "aws_iam_role" "apigw_role" {
  name = "apigateway_dynamodb_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "apigw_policy" {
  name = "apigateway_access_policy"
  role = aws_iam_role.apigw_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["dynamodb:Scan", "dynamodb:GetItem"]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.transactions.arn
      },
      {
        Action   = ["sqs:ReceiveMessage", "sqs:GetQueueAttributes"]
        Effect   = "Allow"
        Resource = aws_sqs_queue.dlq.arn
      }
    ]
  })
}

resource "aws_lambda_function" "processor" {
  filename         = "lambda.zip"
  function_name    = "ProcessTransactionLambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.10"
  timeout          = 30
  source_code_hash = filebase64sha256("lambda.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.transactions.name
      DLQ_URL    = aws_sqs_queue.dlq.id
    }
  }
}

resource "aws_sfn_state_machine" "sfn_state_machine" {
  name     = "CSVIngestionStateMachine"
  role_arn = aws_iam_role.sfn_role.arn
  type     = "EXPRESS"

  definition = jsonencode({
    Comment = "Orchestrated CSV Ingestion Pipeline",
    StartAt = "ParseAndValidateCSV",
    States = {
      ParseAndValidateCSV = {
        Type     = "Task",
        Resource = aws_lambda_function.processor.arn,
        Next     = "PublishSuccessSNS"
      },
      PublishSuccessSNS = {
        Type     = "Task",
        Resource = "arn:aws:states:::sns:publish",
        Parameters = {
          TopicArn  = aws_sns_topic.topic.arn,
          Subject   = "Step Functions Pipeline Completed",
          "Message.$" = "$"
        },
        End = true
      }
    }
  })
}

resource "aws_api_gateway_rest_api" "api" {
  name = "TransactionServiceAPI"
}

resource "aws_api_gateway_resource" "transactions" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "transactions"
}

resource "aws_api_gateway_method" "get_transactions" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.transactions.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "dynamodb_scan" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.transactions.id
  http_method             = aws_api_gateway_method.get_transactions.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:us-east-1:dynamodb:action/Scan"
  credentials             = aws_iam_role.apigw_role.arn
  passthrough_behavior    = "WHEN_NO_MATCH"

  request_templates = {
    "application/json" = "{\"TableName\": \"TransactionsTable\"}"
  }
}

resource "aws_api_gateway_method_response" "resp_transactions_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.transactions.id
  http_method = aws_api_gateway_method.get_transactions.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "dynamodb_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.transactions.id
  http_method = aws_api_gateway_method.get_transactions.http_method
  status_code = aws_api_gateway_method_response.resp_transactions_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  response_templates = {
    "application/json" = "$input.json('$')"
  }

  depends_on = [aws_api_gateway_integration.dynamodb_scan]
}

resource "aws_api_gateway_resource" "dlq" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "dlq"
}

resource "aws_api_gateway_method" "get_dlq" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.dlq.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "sqs_dlq" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.dlq.id
  http_method             = aws_api_gateway_method.get_dlq.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:us-east-1:sqs:path/000000000000/TransactionDLQ"
  credentials             = aws_iam_role.apigw_role.arn
  passthrough_behavior    = "WHEN_NO_MATCH"

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-encoding'"
  }

  request_templates = {
    "application/json" = "Action=ReceiveMessage&MaxNumberOfMessages=10&VisibilityTimeout=0"
  }
}

resource "aws_api_gateway_method_response" "resp_dlq_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.dlq.id
  http_method = aws_api_gateway_method.get_dlq.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "sqs_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.dlq.id
  http_method = aws_api_gateway_method.get_dlq.http_method
  status_code = aws_api_gateway_method_response.resp_dlq_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  response_templates = {
    "application/json" = "$input.json('$')"
  }

  depends_on = [aws_api_gateway_integration.sqs_dlq]
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.dynamodb_scan,
    aws_api_gateway_integration.sqs_dlq
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}

output "transactions_api_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.api.id}/prod/_user_request_/transactions"
}

output "dlq_api_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.api.id}/prod/_user_request_/dlq"
}
