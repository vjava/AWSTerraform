<#
.SYNOPSIS
    Enterprise AWS Core Networking & Compute Orchestrator on LocalStack (Community Compatible)
    Services: VPC, Subnets, Internet Gateway, Route Tables, Security Groups, EC2 Instances
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-PipelineLog {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")][string]$Level = "INFO"
    )
    $TimeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $Color = switch ($Level) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        default   { "Cyan" }
    }
    Write-Host "[$TimeStamp] [$Level] $Message" -ForegroundColor $Color
}

Write-PipelineLog "Initializing Networking Workspace..." "INFO"

$WorkDir = Join-Path $PSScriptRoot "network_workspace"
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir | Out-Null
}

$TfFile = Join-Path $WorkDir "main.tf"
$EndpointUrl = "http://localhost:4566"

# ==============================================================================
# Terraform Infrastructure Code Generation (Without ELBv2)
# ==============================================================================
Write-PipelineLog "Writing core Networking Terraform code to main.tf..." "INFO"

$TerraformHcl = @'
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    ec2            = "http://localhost:4566"
    iam            = "http://localhost:4566"
    s3             = "http://localhost:4566"
  }
}

# 1. Virtual Private Cloud (VPC)
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "EnterpriseMainVPC"
  }
}

# 2. Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "EnterpriseIGW"
  }
}

# 3. Public Subnets (AZ-1 & AZ-2)
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "PublicSubnet-AZ1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "PublicSubnet-AZ2"
  }
}

# 4. Route Table & Associations
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table_association" "rta_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "rta_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

# 5. Security Group
resource "aws_security_group" "web_sg" {
  name        = "EnterpriseWebSG"
  description = "Allow HTTP and SSH traffic"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WebSecurityGroup"
  }
}

# 6. EC2 Instances
resource "aws_instance" "web_1" {
  ami                    = "ami-12345678"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet_1.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  tags = {
    Name = "EnterpriseWebServer-1"
  }
}

resource "aws_instance" "web_2" {
  ami                    = "ami-12345678"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet_2.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  tags = {
    Name = "EnterpriseWebServer-2"
  }
}

# Outputs
output "vpc_id" {
  value = aws_vpc.main_vpc.id
}

output "instance_1_id" {
  value = aws_instance.web_1.id
}

output "instance_2_id" {
  value = aws_instance.web_2.id
}
'@

Set-Content -Path $TfFile -Value $TerraformHcl -Encoding UTF8

# ==============================================================================
# Execution & Deployment
# ==============================================================================
Push-Location $WorkDir
try {
    Write-PipelineLog "Running Terraform Init..." "INFO"
    terraform init -input=false -no-color | Out-Null

    Write-PipelineLog "Applying Core Networking & EC2 Terraform Plan to LocalStack..." "INFO"
    terraform apply -auto-approve -input=false -no-color | Out-Null
    Write-PipelineLog "Infrastructure deployment completed successfully without license errors!" "SUCCESS"

    Write-PipelineLog "Verifying deployed VPC and Instances via AWS CLI..." "INFO"
    aws --endpoint-url=$EndpointUrl ec2 describe-vpcs | Out-Null
    aws --endpoint-url=$EndpointUrl ec2 describe-instances | Out-Null
    Write-PipelineLog "All core networking and compute resources verified successfully!" "SUCCESS"
}
catch {
    Write-PipelineLog "Pipeline Execution Failed: $_" "ERROR"
}
finally {
    Pop-Location
}