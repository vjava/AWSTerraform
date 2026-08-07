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

# 1. TABLE 1: USERS TABLE
resource "aws_dynamodb_table" "users_table" {
  name         = "UsersTable-${random_id.suffix.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }
}

# 2. TABLE 2: ORDERS TABLE
resource "aws_dynamodb_table" "orders_table" {
  name         = "OrdersTable-${random_id.suffix.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }
}

output "users_table_name" {
  value = aws_dynamodb_table.users_table.name
}

output "orders_table_name" {
  value = aws_dynamodb_table.orders_table.name
}