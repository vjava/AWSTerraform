# ==============================================================================
# AWS RDS MYSQL DEPLOYMENT & PYTHON CLIENT SCRIPT (COMPLIANT WITH LAB LIMITS)
# ==============================================================================
Write-Host ">>> Initializing Compliant AWS RDS MySQL Deployment..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# STEP 0: CLEAN UP LOCAL STATE & DUPLICATE FILES
# -----------------------------------------------------------------------------
Write-Host "`n[0/5] Purging local terraform state and duplicate files..." -ForegroundColor Yellow

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
# STEP 1: GENERATE TERRAFORM CODE (main.tf)
# -----------------------------------------------------------------------------
Write-Host "`n[1/5] Generating RDS Terraform configuration..." -ForegroundColor Yellow

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

# -----------------------------------------------------------------------------
# VPC & NETWORKING
# -----------------------------------------------------------------------------
resource "aws_vpc" "rds_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "rds-compliant-vpc-${random_id.suffix.hex}" }
}

resource "aws_subnet" "subnet_a" {
  vpc_id                  = aws_vpc.rds_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = { Name = "rds-subnet-a" }
}

resource "aws_subnet" "subnet_b" {
  vpc_id                  = aws_vpc.rds_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = { Name = "rds-subnet-b" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.rds_vpc.id
  tags   = { Name = "rds-igw" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.rds_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "rds-public-rt" }
}

resource "aws_route_table_association" "assoc_a" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "assoc_b" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group-${random_id.suffix.hex}"
  subnet_ids = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]

  tags = { Name = "RDS Subnet Group" }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-mysql-sg-${random_id.suffix.hex}"
  description = "Allow MySQL traffic from anywhere"
  vpc_id      = aws_vpc.rds_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
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

# -----------------------------------------------------------------------------
# RDS MYSQL INSTANCE (Strict Lab Compliance)
# -----------------------------------------------------------------------------
resource "aws_db_instance" "mysql_db" {
  identifier             = "compliant-mysql-db-${random_id.suffix.hex}"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"       # Permitted T-series burstable class
  allocated_storage      = 20                  # Limit: Max 30 GB
  max_allocated_storage  = 20                  # Disables autoscaling beyond lab limit
  storage_type           = "gp2"                 # Standard GP2 Storage (No Provisioned IOPS)
  
  db_name                = "company_db"
  username               = "admin"
  password               = "LabPassword123!"     # Change if needed
  
  multi_az               = false                 # Single-AZ Deployment
  publicly_accessible    = true
  skip_final_snapshot    = true
  
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  tags = {
    Environment = "Lab"
  }
}

output "rds_endpoint" {
  value = aws_db_instance.mysql_db.endpoint
}

output "rds_address" {
  value = aws_db_instance.mysql_db.address
}

output "db_name" {
  value = aws_db_instance.mysql_db.db_name
}
'@

[System.IO.File]::WriteAllText("$PWD/main.tf", $TerraformCode)
Write-Host "main.tf generated." -ForegroundColor Green

# -----------------------------------------------------------------------------
# STEP 2: EXECUTE TERRAFORM
# -----------------------------------------------------------------------------
Write-Host "`n[2/5] Initializing Terraform..." -ForegroundColor Yellow
terraform init -reconfigure

Write-Host "`n[3/5] Applying Terraform configuration (Deploying RDS Instance)..." -ForegroundColor Yellow
& terraform apply -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nTerraform deployment failed!" -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------------------
# STEP 3: EXTRACT OUTPUTS & PREPARE PYTHON CLIENT
# -----------------------------------------------------------------------------
Write-Host "`n[4/5] Extracting Database Endpoint..." -ForegroundColor Yellow
$DB_HOST = (terraform output -raw rds_address)
$DB_NAME = (terraform output -raw db_name)

Write-Host "RDS Host: $DB_HOST" -ForegroundColor Green

# Install mysql-connector-python if missing
Write-Host "Checking required Python packages..." -ForegroundColor Yellow
python -c "import mysql.connector" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing mysql-connector-python..." -ForegroundColor Yellow
    pip install mysql-connector-python
}

# -----------------------------------------------------------------------------
# STEP 4: GENERATE & RUN PYTHON DB POPULATION SCRIPT
# -----------------------------------------------------------------------------
Write-Host "`n[5/5] Executing Python Client to create table and insert 100 records..." -ForegroundColor Yellow

$PythonScript = @"
import mysql.connector
import random
import time

host = '$DB_HOST'
user = 'admin'
password = 'LabPassword123!'
database = '$DB_NAME'

print(f"Connecting to MySQL RDS instance at {host}...")

# Retry loop for DB availability
connected = False
for i in range(12):
    try:
        conn = mysql.connector.connect(
            host=host,
            user=user,
            password=password,
            database=database,
            port=3306,
            connect_timeout=10
        )
        connected = True
        break
    except Exception as e:
        print(f"Waiting for database connection... ({i+1}/12)")
        time.sleep(10)

if not connected:
    print("Error: Could not connect to RDS Instance.")
    exit(1)

cursor = conn.cursor()

# 1. Create Employee Table
create_table_query = '''
CREATE TABLE IF NOT EXISTS employee (
    emp_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    department VARCHAR(50),
    salary DECIMAL(10, 2),
    hire_date DATE
)
'''
cursor.execute(create_table_query)
print("Table 'employee' created successfully.")

# 2. Generate 100 Records
first_names = ['Amit', 'Priya', 'Rahul', 'Sneha', 'Vikas', 'Ananya', 'Rohan', 'Kavya', 'Suresh', 'Pooja']
last_names = ['Sharma', 'Verma', 'Patel', 'Singh', 'Kumar', 'Das', 'Reddy', 'Joshi', 'Nair', 'Gupta']
departments = ['Engineering', 'HR', 'Marketing', 'Sales', 'Finance', 'Operations']

records = []
for i in range(1, 101):
    fn = random.choice(first_names)
    ln = random.choice(last_names)
    dept = random.choice(departments)
    salary = round(random.uniform(40000, 120000), 2)
    hire_date = f"{random.randint(2018, 2025)}-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}"
    records.append((fn, ln, dept, salary, hire_date))

# 3. Batch Insert Records
insert_query = '''
INSERT INTO employee (first_name, last_name, department, salary, hire_date)
VALUES (%s, %s, %s, %s, %s)
'''
cursor.executemany(insert_query, records)
conn.commit()

print(f"Successfully inserted {cursor.rowcount} records into 'employee' table.")

# 4. Verify Total Records
cursor.execute("SELECT COUNT(*) FROM employee;")
total_count = cursor.fetchone()[0]
print(f"Verification: Total records in 'employee' table = {total_count}")

# 5. Display sample records
cursor.execute("SELECT * FROM employee LIMIT 5;")
print("\nSample Output (First 5 records):")
print("-" * 60)
for row in cursor.fetchall():
    print(row)
print("-" * 60)

cursor.close()
conn.close()
"@

[System.IO.File]::WriteAllText("$PWD/populate_db.py", $PythonScript)
python populate_db.py

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "AWS RDS MYSQL DEPLOYMENT & POPULATION COMPLETED!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan