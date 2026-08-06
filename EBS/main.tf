terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# -----------------------------------------------------------------------------
# DYNAMIC SOLUTION STACK LOOKUP
# -----------------------------------------------------------------------------

data "aws_elastic_beanstalk_solution_stack" "python_latest" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux 2023 v.* running Python 3\\.11$"
}

# -----------------------------------------------------------------------------
# VARIABLES
# -----------------------------------------------------------------------------

variable "environment_tier" {
  type        = string
  description = "Environment tier: WebServer or Worker"
  default     = "WebServer"

  validation {
    condition     = contains(["WebServer", "Worker"], var.environment_tier)
    error_message = "Violation: Only 'WebServer' and 'Worker' environments are permitted."
  }
}

variable "ebs_instance_profile" {
  type        = string
  description = "Name of existing EC2 Instance Profile"
  default     = "ssm-role"
}

# -----------------------------------------------------------------------------
# ELASTIC BEANSTALK APPLICATION & ENVIRONMENT
# -----------------------------------------------------------------------------

resource "aws_elastic_beanstalk_application" "app" {
  name        = "compliant-eb-app"
  description = "Elastic Beanstalk Application complying with platform and resource rules"
}

resource "aws_elastic_beanstalk_environment" "env" {
  name                = "compliant-eb-env"
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.python_latest.name
  tier                = var.environment_tier

  # EC2 Instance Profile (populates instances with eb-ec2-role)
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = var.ebs_instance_profile
  }

  # Load Balancer Type
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }

  # Capacity & Instance Configuration
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t3.micro"
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = "1"
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = "4"
  }
}

# -----------------------------------------------------------------------------
# OUTPUTS
# -----------------------------------------------------------------------------

output "endpoint_url" {
  description = "The URL to access the deployed Elastic Beanstalk application"
  value       = "http://${aws_elastic_beanstalk_environment.env.cname}"
}