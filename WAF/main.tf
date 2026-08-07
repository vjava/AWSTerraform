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