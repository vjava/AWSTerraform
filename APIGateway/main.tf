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

# -----------------------------------------------------------------------------
# 1. VPC LINK FOR API GATEWAY
# -----------------------------------------------------------------------------
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "apigw-vpc-${random_id.suffix.hex}" }
}

resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_lb" "nlb" {
  name               = "apigw-nlb-${random_id.suffix.hex}"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.public_subnet.id]
}

resource "aws_api_gateway_vpc_link" "vpc_link" {
  name        = "apigw-vpc-link-${random_id.suffix.hex}"
  target_arns = [aws_lb.nlb.arn]
}

# -----------------------------------------------------------------------------
# 2. REST API (WITH CACHING, THROTTLING, & API KEY AUTH)
# -----------------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "rest_api" {
  name        = "compliant-rest-api-${random_id.suffix.hex}"
  description = "REST API with Throttling and Caching"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  parent_id   = aws_api_gateway_rest_api.rest_api.root_resource_id
  path_part   = "demo"
}

resource "aws_api_gateway_method" "method" {
  rest_api_id      = aws_api_gateway_rest_api.rest_api.id
  resource_id      = aws_api_gateway_resource.resource.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "integration_response" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_templates = {
    "application/json" = "{\"message\": \"Success from REST API Mock Target\"}"
  }

  depends_on = [aws_api_gateway_integration.integration]
}

resource "aws_api_gateway_deployment" "rest_deployment" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id

  depends_on = [aws_api_gateway_integration_response.integration_response]
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "rest_stage" {
  deployment_id = aws_api_gateway_deployment.rest_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.rest_api.id
  stage_name    = "prod"

  cache_cluster_enabled = true
  cache_cluster_size    = "0.5"
}

resource "aws_api_gateway_method_settings" "rest_settings" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  stage_name  = aws_api_gateway_stage.rest_stage.stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
    caching_enabled        = true
  }
}

# API Key and Usage Plan (Basic Auth & Rate Limiting)
resource "aws_api_gateway_api_key" "api_key" {
  name = "compliant-key-${random_id.suffix.hex}"
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "compliant-usage-plan-${random_id.suffix.hex}"

  api_stages {
    api_id = aws_api_gateway_rest_api.rest_api.id
    stage  = aws_api_gateway_stage.rest_stage.stage_name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }
}

resource "aws_api_gateway_usage_plan_key" "usage_plan_key" {
  key_id        = aws_api_gateway_api_key.api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan.id
}

# -----------------------------------------------------------------------------
# 3. HTTP API (API GATEWAY V2)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "http_api" {
  name          = "compliant-http-api-${random_id.suffix.hex}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "http_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "prod"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }
}

# -----------------------------------------------------------------------------
# 4. WEBSOCKET API (API GATEWAY V2)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "websocket_api" {
  name                       = "compliant-websocket-api-${random_id.suffix.hex}"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
}

resource "aws_apigatewayv2_route" "ws_connect_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$connect"
}

resource "aws_apigatewayv2_route" "ws_disconnect_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$disconnect"
}

resource "aws_apigatewayv2_route" "ws_default_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$default"
}

resource "aws_apigatewayv2_stage" "ws_stage" {
  api_id      = aws_apigatewayv2_api.websocket_api.id
  name        = "prod"
  auto_deploy = true
}

# OUTPUTS
output "rest_api_id" {
  value = aws_api_gateway_rest_api.rest_api.id
}

output "rest_api_url" {
  value = aws_api_gateway_stage.rest_stage.invoke_url
}

output "http_api_id" {
  value = aws_apigatewayv2_api.http_api.id
}

output "websocket_api_id" {
  value = aws_apigatewayv2_api.websocket_api.id
}

output "vpc_link_id" {
  value = aws_api_gateway_vpc_link.vpc_link.id
}

output "api_key_value" {
  value     = aws_api_gateway_api_key.api_key.value
  sensitive = true
}