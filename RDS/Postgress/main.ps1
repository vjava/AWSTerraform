# ==============================================================================
# AWS POSTGRESQL DEPLOYMENT & POPULATION (STRICT LAB COMPLIANT)
# ==============================================================================
Write-Host ">>> Starting AWS PostgreSQL Deployment..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# STEP 0: CLEAN UP LOCAL STATE
# -----------------------------------------------------------------------------
Write-Host "`n[0/5] Cleaning up state and temporary files..." -ForegroundColor Yellow

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

$ErrorActionPreference = $OldErrorAction

# -----------------------------------------------------------------------------
# STEP 1: GENERATE main.tf (USING DEFAULT VPC & DB INSTANCE)
# -----------------------------------------------------------------------------
Write-Host "`n[1/5] Writing main.tf configuration..." -ForegroundColor Yellow

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

# Fetch Default VPC
data "aws_vpc" "default" {
  default = true
}

# Fetch Subnets in Default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group
resource "aws_security_group" "rds_sg" {
  name        = "rds-pg-sg-${random_id.suffix.hex}"
  description = "Allow PostgreSQL traffic from anywhere"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-pg-subnet-group-${random_id.suffix.hex}"
  subnet_ids = data.aws_subnets.default.ids
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "postgres_db" {
  identifier             = "compliant-rds-pg-${random_id.suffix.hex}"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"       # Permitted T-series class
  allocated_storage      = 20                  # Max 30 GB limit
  max_allocated_storage  = 20
  storage_type           = "gp2"
  
  db_name                = "transaction_db"
  username               = "postgres"
  password               = "LabPassword123!"
  
  publicly_accessible    = true
  skip_final_snapshot    = true
  
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
}

output "aurora_endpoint" {
  value = aws_db_instance.postgres_db.address
}

output "db_name" {
  value = aws_db_instance.postgres_db.db_name
}
'@

[System.IO.File]::WriteAllText("$PWD/main.tf", $TerraformCode)
Write-Host "main.tf generated successfully." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 2: APPLY TERRAFORM
# -----------------------------------------------------------------------------
Write-Host "`n[2/5] Initializing Terraform..." -ForegroundColor Yellow
terraform init -reconfigure

Write-Host "`n[3/5] Deploying RDS PostgreSQL Instance (This will take ~3-5 minutes)..." -ForegroundColor Yellow
& terraform apply -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nTerraform deployment failed!" -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------------------
# STEP 3: EXTRACT ENDPOINT & PREPARE PYTHON CLIENT
# -----------------------------------------------------------------------------
Write-Host "`n[4/5] Extracting Database Endpoint..." -ForegroundColor Yellow
$DB_HOST = (terraform output -raw aurora_endpoint)
$DB_NAME = (terraform output -raw db_name)

Write-Host "PostgreSQL Host Endpoint: $DB_HOST" -ForegroundColor Green

python -c "import psycopg2" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing psycopg2-binary..." -ForegroundColor Yellow
    pip install psycopg2-binary
}

# -----------------------------------------------------------------------------
# STEP 4: EXECUTE PYTHON POPULATION SCRIPT
# -----------------------------------------------------------------------------
Write-Host "`n[5/5] Connecting to Database and Inserting 1000 records..." -ForegroundColor Yellow

$PythonScript = @"
import psycopg2
from psycopg2.extras import execute_values
import random
import time
import uuid

host = '$DB_HOST'
user = 'postgres'
password = 'LabPassword123!'
database = '$DB_NAME'

print(f"Connecting to PostgreSQL at {host}...")

connected = False
for i in range(15):
    try:
        conn = psycopg2.connect(
            host=host,
            user=user,
            password=password,
            dbname=database,
            port=5432,
            connect_timeout=10
        )
        connected = True
        print("Connected successfully!")
        break
    except Exception as e:
        print(f"Waiting for database instance to accept connections... ({i+1}/15)")
        time.sleep(10)

if not connected:
    print("Error: Could not connect to PostgreSQL Database Endpoint.")
    exit(1)

cursor = conn.cursor()

create_table_query = '''
CREATE TABLE IF NOT EXISTS transactions (
    transaction_id SERIAL PRIMARY KEY,
    reference_code VARCHAR(64) UNIQUE NOT NULL,
    account_number VARCHAR(20) NOT NULL,
    transaction_type VARCHAR(20) NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
'''
cursor.execute(create_table_query)
conn.commit()
print("Table 'transactions' created successfully.")

txn_types = ['CREDIT', 'DEBIT', 'TRANSFER', 'REFUND', 'PAYMENT']
statuses = ['COMPLETED', 'PENDING', 'FAILED', 'PROCESSING']

records = []
for i in range(1, 1001):
    ref_code = f"PGTXN-{uuid.uuid4().hex[:12].upper()}"
    acc_num = f"ACC{random.randint(10000000, 99999999)}"
    t_type = random.choice(txn_types)
    amount = round(random.uniform(5.00, 15000.00), 2)
    status = random.choice(statuses)
    records.append((ref_code, acc_num, t_type, amount, status))

insert_query = '''
INSERT INTO transactions (reference_code, account_number, transaction_type, amount, status)
VALUES %s;
'''
execute_values(cursor, insert_query, records)
conn.commit()

print("Successfully inserted 1000 records into 'transactions' table.")

cursor.execute("SELECT COUNT(*) FROM transactions;")
print(f"Verification: Total records in DB = {cursor.fetchone()[0]}")

cursor.close()
conn.close()
"@

[System.IO.File]::WriteAllText("$PWD/populate_aurora_pg.py", $PythonScript)
python populate_aurora_pg.py

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "POSTGRESQL DEPLOYMENT & DATA INSERTION COMPLETE!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan