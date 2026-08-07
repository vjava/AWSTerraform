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

# 1. SNS TOPIC
resource "aws_sns_topic" "event_topic" {
  name              = "sns-lambda-topic-${random_id.suffix.hex}"
  kms_master_key_id = "alias/aws/sns"
}

# 2. LAMBDA PERMISSION FOR SNS
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS-${random_id.suffix.hex}"
  action        = "lambda:InvokeFunction"
  function_name = "sns-event-processor-manual"
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.event_topic.arn
}

# 3. SNS TOPIC SUBSCRIPTION TO LAMBDA
resource "aws_sns_topic_subscription" "lambda_sub" {
  topic_arn = aws_sns_topic.event_topic.arn
  protocol  = "lambda"
  endpoint  = "arn:aws:lambda:us-east-1:654654589397:function:sns-event-processor-manual"

  depends_on = [aws_lambda_permission.allow_sns]
}

# OUTPUTS
output "sns_topic_arn" {
  value = aws_sns_topic.event_topic.arn
}