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

# 1. SNS TOPIC
resource "aws_sns_topic" "user_updates" {
  name              = "user-updates-topic-${random_id.suffix.hex}"
  kms_master_key_id = "alias/aws/sns"
}

# 2. DEAD LETTER QUEUE (DLQ)
resource "aws_sqs_queue" "app_queue_dlq" {
  name                      = "app-processing-dlq-${random_id.suffix.hex}"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600 # 14 days retention
}

# 3. MAIN SQS QUEUE (WITH REDRIVE POLICY)
resource "aws_sqs_queue" "app_queue" {
  name                       = "app-processing-queue-${random_id.suffix.hex}"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 10 # Long polling
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.app_queue_dlq.arn
    maxReceiveCount     = 3
  })
}

# 4. SQS QUEUE POLICY (ALLOW SNS TO PUBLISH TO SQS)
resource "aws_sqs_queue_policy" "sqs_policy" {
  queue_url = aws_sqs_queue.app_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSNSTopicToPublish"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.app_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.user_updates.arn
          }
        }
      }
    ]
  })
}

# 5. SNS TO SQS SUBSCRIPTION
resource "aws_sns_topic_subscription" "sns_to_sqs" {
  topic_arn = aws_sns_topic.user_updates.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.app_queue.arn
}

# OUTPUTS
output "sns_topic_arn" {
  value = aws_sns_topic.user_updates.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.app_queue.id
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.app_queue.arn
}

output "dlq_queue_url" {
  value = aws_sqs_queue.app_queue_dlq.id
}