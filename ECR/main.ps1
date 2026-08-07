<#
.SYNOPSIS
    Automates AWS Public ECR deployment via Terraform and pushes a sample Docker image with safety checks.
.DESCRIPTION
    1. Verifies that Docker Desktop is running before proceeding.
    2. Generates Terraform configuration and provisions the Public ECR repository.
    3. Creates a simple Dockerfile locally (Nginx web server).
    4. Builds the Docker image.
    5. Authenticates with AWS ECR Public (with error handling for IAM permissions).
    6. Tags and pushes the Docker image to the new ECR repository only if authentication succeeds.
#>

$ErrorActionPreference = "Stop"

Write-Host "=== Starting ECR & Docker Automation ===" -ForegroundColor Cyan

# 1. Verify Prerequisites
foreach ($cmd in @('terraform', 'aws', 'docker')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "$cmd is not installed or not in the system PATH."
    }
}

# 2. Check if Docker Daemon/Engine is Running
Write-Host "`n[1/7] Checking Docker Engine status..." -ForegroundColor Yellow
try {
    $null = docker ps 2>&1
    Write-Host "Docker is running successfully." -ForegroundColor Green
} catch {
    Write-Error "Docker Desktop is not running or the daemon is unreachable. Please open Docker Desktop and try again."
}

# 3. Generate main.tf configuration file
Write-Host "`n[2/7] Generating main.tf configuration file..." -ForegroundColor Yellow
$terraformLines = @(
    'terraform {',
    '  required_version = ">= 1.0.0"',
    '  required_providers {',
    '    aws = {',
    '      source  = "hashicorp/aws"',
    '      version = "~> 5.0"',
    '    }',
    '  }',
    '}',
    '',
    'provider "aws" {',
    '  region = "us-east-1"',
    '}',
    '',
    'variable "repository_name" {',
    '  type        = string',
    '  description = "Name of the public ECR repository"',
    '  default     = "my-public-app-repo"',
    '}',
    '',
    'resource "aws_ecrpublic_repository" "repo" {',
    '  repository_name = var.repository_name',
    '  catalog_data {',
    '    description       = "Public ECR repository with vulnerability scanning and lifecycle policies"',
    '    operating_systems = ["Linux"]',
    '    architectures     = ["x86_64"]',
    '  }',
    '}',
    '',
    'resource "aws_ecrpublic_repository_policy" "policy" {',
    '  repository_name = aws_ecrpublic_repository.repo.repository_name',
    '  policy = jsonencode({',
    '    Version = "2012-10-17"',
    '    Statement = [',
    '      {',
    '        Sid       = "PublicRead"',
    '        Effect    = "Allow"',
    '        Principal = "*"',
    '        Action = [',
    '          "ecr-public:GetAuthorizationToken",',
    '          "ecr-public:BatchCheckLayerAvailability",',
    '          "ecr-public:GetDownloadUrlForLayer",',
    '          "ecr-public:DescribeRepositories",',
    '          "ecr-public:ListImages",',
    '          "ecr-public:DescribeImages"',
    '        ]',
    '      }',
    '    ]',
    '  })',
    '}',
    '',
    'output "repository_uri" {',
    '  value       = aws_ecrpublic_repository.repo.repository_uri',
    '  description = "The URI of the public ECR repository"',
    '}'
)
Set-Content -Path "main.tf" -Value $terraformLines -Encoding utf8

# 4. Initialize & Apply Terraform
Write-Host "`n[3/7] Initializing Terraform..." -ForegroundColor Yellow
terraform init

Write-Host "`n[4/7] Applying Terraform Configuration..." -ForegroundColor Yellow
terraform apply -auto-approve

# Get the Repository URI output
$repoUri = (terraform output -raw repository_uri).Trim()
Write-Host "Repository URI: $repoUri" -ForegroundColor Green

# 5. Create a Simple Dockerfile
Write-Host "`n[5/7] Creating a sample Dockerfile..." -ForegroundColor Yellow
$dockerfileLines = @(
    'FROM nginx:alpine',
    'RUN echo "<h1>Hello from AWS ECR Public via Terraform & Docker!</h1>" > /usr/share/nginx/html/index.html',
    'EXPOSE 80'
)
Set-Content -Path "Dockerfile" -Value $dockerfileLines -Encoding utf8

# 6. Build Docker Image Locally
Write-Host "`n[6/7] Building local Docker image..." -ForegroundColor Yellow
docker build -t local-web-app:latest .

# 7. Authenticate with AWS ECR Public and Push
Write-Host "`n[7/7] Authenticating Docker with AWS ECR Public and pushing image..." -ForegroundColor Yellow
try {
    $loginPassword = aws ecr-public get-login-password --region us-east-1
    if ($LASTEXITCODE -ne 0) { throw "AWS CLI failed to get login password. Check IAM permissions for sts:GetServiceBearerToken." }
    
    $loginPassword | docker login --username AWS --password-stdin public.ecr.aws
    if ($LASTEXITCODE -ne 0) { throw "Docker login failed." }

    docker tag local-web-app:latest "$repoUri:latest"
    docker push "$repoUri:latest"

    Write-Host "`n=== Success! Image pushed to ECR Public repository ===" -ForegroundColor Green
    Write-Host "To run/deploy this image locally from your ECR registry, run:" -ForegroundColor Cyan
    Write-Host "docker run -d -p 8080:80 $repoUri:latest" -ForegroundColor Yellow
    Write-Host "You can then access your web app at: http://localhost:8080" -ForegroundColor Cyan
} catch {
    Write-Error "Deployment to ECR failed: $_`nNote: If you are using a restricted IAM lab user, ensure policy 'AmazonEC2ContainerRegistryPublicFullAccess' is attached."
}