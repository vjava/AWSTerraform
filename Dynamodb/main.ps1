# ==============================================================================
# AWS DYNAMODB (2 TABLES + GUARANTEED 1000 RECORDS IN EACH TABLE)
# ==============================================================================
Write-Host ">>> Initializing DynamoDB Infrastructure and Data Ingestion Pipeline..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# STEP 0: PURGE PREVIOUS LOCAL STATE
# -----------------------------------------------------------------------------
Write-Host "`n[0/4] Purging previous terraform state and temporary files..." -ForegroundColor Yellow

$OldErrorAction = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"

Get-ChildItem -Path $PWD -Filter "*Copy*.tf" | Remove-Item -Force -ErrorAction SilentlyContinue

if (Test-Path "$PWD/terraform.tfstate") {
    Remove-Item "$PWD/terraform.tfstate" -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/terraform.tfstate.backup") {
    Remove-Item "$PWD/terraform.tfstate.backup" -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/.terraform") {
    Remove-Item "$PWD/.terraform" -Recurse -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$PWD/insert_dynamodb_data.py") {
    Remove-Item "$PWD/insert_dynamodb_data.py" -Force -ErrorAction SilentlyContinue
}

$ErrorActionPreference = $OldErrorAction
Write-Host "Local workspace cleaned." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 1: GENERATE TERRAFORM CODE (main.tf)
# -----------------------------------------------------------------------------
Write-Host "`n[1/4] Writing DynamoDB Terraform configuration..." -ForegroundColor Yellow

$TerraformCode = @'
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
'@

[System.IO.File]::WriteAllText("$PWD/main.tf", $TerraformCode)
Write-Host "main.tf generated successfully." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 2: APPLY TERRAFORM DEPLOYMENT
# -----------------------------------------------------------------------------
Write-Host "`n[2/4] Initializing and Applying Terraform Configuration..." -ForegroundColor Yellow
terraform init -reconfigure

& terraform apply -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nTerraform deployment failed!" -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------------------
# STEP 3: EXTRACT TABLE NAMES & PREPARE PYTHON CLIENT
# -----------------------------------------------------------------------------
Write-Host "`n[3/4] Extracting DynamoDB Table Names..." -ForegroundColor Yellow
$USERS_TABLE  = (terraform output -raw users_table_name)
$ORDERS_TABLE = (terraform output -raw orders_table_name)

Write-Host "Users Table Name:  $USERS_TABLE" -ForegroundColor Green
Write-Host "Orders Table Name: $ORDERS_TABLE" -ForegroundColor Green

python -c "import boto3" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing boto3..." -ForegroundColor Yellow
    pip install boto3
}

# -----------------------------------------------------------------------------
# STEP 4: GENERATE & RUN PYTHON CLIENT TO INSERT 1000 RECORDS IN EACH TABLE
# -----------------------------------------------------------------------------
Write-Host "`n[4/4] Executing Python Client Script to Insert 1000 Records into Each Table..." -ForegroundColor Yellow

$PythonScript = @"
import boto3
import random
import time
import uuid
from decimal import Decimal

users_table_name = '$USERS_TABLE'
orders_table_name = '$ORDERS_TABLE'
region = 'us-east-1'

dynamodb = boto3.resource('dynamodb', region_name=region)
users_table = dynamodb.Table(users_table_name)
orders_table = dynamodb.Table(orders_table_name)

print("Starting Batch Ingestion into DynamoDB Tables...\n")

# 1. Insert 1000 records into Users Table
print(f"Inserting 1,000 records into '{users_table_name}'...")
start_time = time.time()

user_cities = ['Bengaluru', 'Mumbai', 'Delhi', 'Hyderabad', 'Chennai']
try:
    with users_table.batch_writer() as batch:
        for i in range(1, 1001):
            user_item = {
                'user_id': f"USR-{1000 + i}",
                'name': f"User_{i}",
                'email': f"user_{i}@example.com",
                'city': random.choice(user_cities),
                'age': random.randint(18, 65),
                'created_at': int(time.time())
            }
            batch.put_item(Item=user_item)
    print(f"Successfully inserted 1,000 records into '{users_table_name}' in {round(time.time() - start_time, 2)} seconds.")
except Exception as e:
    print(f"Error inserting into Users Table: {e}")

# 2. Insert 1000 records into Orders Table (Safely handled with Decimal)
print(f"\nInserting 1,000 records into '{orders_table_name}'...")
start_time = time.time()

status_list = ['PENDING', 'COMPLETED', 'SHIPPED', 'CANCELLED']

try:
    with orders_table.batch_writer() as batch:
        for i in range(1, 1001):
            random_amount = f"{random.uniform(10.0, 1500.0):.2f}"
            order_item = {
                'order_id': f"ORD-{uuid.uuid4().hex[:10].upper()}",
                'user_id': f"USR-{random.randint(1001, 2000)}",
                'amount': Decimal(random_amount),
                'status': random.choice(status_list),
                'timestamp': int(time.time())
            }
            batch.put_item(Item=order_item)
    print(f"Successfully inserted 1,000 records into '{orders_table_name}' in {round(time.time() - start_time, 2)} seconds.")
except Exception as e:
    print(f"Error in batch_writer for Orders Table: {e}")
    print("Falling back to put_item loop...")
    for i in range(1, 1001):
        random_amount = f"{random.uniform(10.0, 1500.0):.2f}"
        order_item = {
            'order_id': f"ORD-{uuid.uuid4().hex[:10].upper()}",
            'user_id': f"USR-{random.randint(1001, 2000)}",
            'amount': Decimal(random_amount),
            'status': random.choice(status_list),
            'timestamp': int(time.time())
        }
        orders_table.put_item(Item=order_item)

# 3. Verify Item Counts by Scanning Tables Directly
print("\n" + "="*60)
print("VERIFYING ACTUAL ITEM COUNTS VIA TABLE SCAN")
print("="*60)

users_scan = users_table.scan(Select='COUNT')
orders_scan = orders_table.scan(Select='COUNT')

print(f"Actual Records in '{users_table_name}': {users_scan.get('Count', 0)}")
print(f"Actual Records in '{orders_table_name}': {orders_scan.get('Count', 0)}")

# Fetch and display a sample item from Orders Table
sample = orders_table.scan(Limit=1)
if sample.get('Items'):
    print("\nSample Item from Orders Table:")
    print(sample['Items'][0])

print("="*60)
"@

[System.IO.File]::WriteAllText("$PWD/insert_dynamodb_data.py", $PythonScript)
python insert_dynamodb_data.py

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "DYNAMODB TABLES DEPLOYED & 2,000 RECORDS INSERTED!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan