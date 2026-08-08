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
    s3         = "http://localhost:4566"
    lambda     = "http://localhost:4566"
    iam        = "http://localhost:4566"
    apigateway = "http://localhost:4566"
    transcribe = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "media_bucket" {
  bucket        = "media-audio-bucket"
  force_destroy = true
}

resource "aws_s3_bucket" "transcript_bucket" {
  bucket        = "transcript-output-bucket"
  force_destroy = true
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_transcribe_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_s3_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["s3:*", "transcribe:*"]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

resource "aws_lambda_function" "transcribe_processor" {
  filename         = "lambda.zip"
  function_name    = "TranscribeProcessorLambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.10"
  timeout          = 30
  source_code_hash = filebase64sha256("lambda.zip")

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.transcript_bucket.bucket
    }
  }
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.media_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.transcribe_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".mp3"
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.transcribe_processor.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.media_bucket.arn
}

# API Gateway with AWS_PROXY
resource "aws_api_gateway_rest_api" "api" {
  name = "TranscribeServiceAPI"
}

resource "aws_api_gateway_resource" "transcriptions" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "transcriptions"
}

resource "aws_api_gateway_method" "get_transcriptions" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.transcriptions.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.transcriptions.id
  http_method             = aws_api_gateway_method.get_transcriptions.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.transcribe_processor.invoke_arn
}

resource "aws_lambda_permission" "apigw_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.transcribe_processor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}

output "transcribe_api_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.api.id}/prod/_user_request_/transcriptions"
}
