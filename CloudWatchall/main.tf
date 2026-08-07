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