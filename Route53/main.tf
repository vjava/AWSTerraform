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

# 1. VPC FOR PRIVATE HOSTED ZONE ASSOCIATION
resource "aws_vpc" "route53_vpc" {
  cidr_block           = "10.100.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "route53-vpc-${random_id.suffix.hex}"
  }
}

# 2. ROUTE 53 PRIVATE HOSTED ZONE
resource "aws_route53_zone" "private_zone" {
  name = "mycompany.internal"

  vpc {
    vpc_id = aws_vpc.route53_vpc.id
  }

  comment = "Private DNS Zone created via Terraform"
}

# 3. ROUTE 53 DNS RECORDS
# (A) Record
resource "aws_route53_record" "app_a_record" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "app.mycompany.internal"
  type    = "A"
  ttl     = 300
  records = ["10.100.1.50"]
}

# (CNAME) Record
resource "aws_route53_record" "api_cname_record" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "api.mycompany.internal"
  type    = "CNAME"
  ttl     = 300
  records = ["app.mycompany.internal"]
}

# (TXT) Record
resource "aws_route53_record" "verification_txt_record" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "verification.mycompany.internal"
  type    = "TXT"
  ttl     = 300
  records = ["v=spf1 include:mycompany.internal ~all"]
}

# 4. ROUTE 53 HEALTH CHECK
resource "aws_route53_health_check" "endpoint_health_check" {
  fqdn              = "example.com"
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = "3"
  request_interval  = "30"

  tags = {
    Name = "demo-health-check-${random_id.suffix.hex}"
  }
}

# OUTPUTS
output "hosted_zone_id" {
  value = aws_route53_zone.private_zone.zone_id
}

output "hosted_zone_name" {
  value = aws_route53_zone.private_zone.name
}

output "health_check_id" {
  value = aws_route53_health_check.endpoint_health_check.id
}