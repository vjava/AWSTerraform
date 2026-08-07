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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

# Fetch Existing Lab IAM Role
data "aws_iam_role" "lab_role" {
  name = "firehoseDeliveryRole-32ee2431"
}

# 1. S3 BUCKET WITH EVENTBRIDGE NOTIFICATIONS ENABLED
resource "aws_s3_bucket" "event_bucket" {
  bucket        = "eventbridge-s3-landing-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket      = aws_s3_bucket.event_bucket.id
  eventbridge = true
}

# 2. LAMBDA FUNCTION SOURCE CODE
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content  = <<EOF
import json

def lambda_handler(event, context):
    print("Received S3 Event Notification via EventBridge!")
    print("Event Payload:", json.dumps(event))
    
    detail = event.get('detail', {})
    bucket_name = detail.get('bucket', {}).get('name')
    object_key = detail.get('object', {}).get('key')
    
    print(f"File Successfully Processed: s3://{bucket_name}/{object_key}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Event successfully processed by Lambda!')
    }
EOF
    filename = "index.py"
  }
}

# 3. LAMBDA FUNCTION RESOURCE (Using Pre-existing Lab Role)
resource "aws_lambda_function" "s3_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "s3-event-processor-${random_id.suffix.hex}"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "index.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
}

# 4. EVENTBRIDGE RULE FOR S3 OBJECT CREATION
resource "aws_cloudwatch_event_rule" "s3_object_created" {
  name        = "s3-file-landing-rule-${random_id.suffix.hex}"
  description = "Triggers Lambda when a file lands in S3 bucket"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.event_bucket.id]
      }
    }
  })
}

# 5. TARGET FOR EVENTBRIDGE RULE
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.s3_object_created.name
  target_id = "TargetLambdaFunction"
  arn       = aws_lambda_function.s3_processor.arn
}

# 6. LAMBDA PERMISSION FOR EVENTBRIDGE
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_object_created.arn
}

output "bucket_name" {
  value = aws_s3_bucket.event_bucket.id
}

output "lambda_function_name" {
  value = aws_lambda_function.s3_processor.function_name
}