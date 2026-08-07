terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Dynamically query active AWS Region and Available AZs
provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-2.0.*-x86_64-gp2"]
  }
}

# ------------------------------------------------------------------------------
# PHASE 1: DYNAMIC MULTI-AZ VPC INFRASTRUCTURE
# ------------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "Master-Architect-VPC"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet-1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet-2"
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "Private-Subnet-1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "Private-Subnet-2"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "Master-IGW"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id

  tags = {
    Name = "Master-NAT-GW"
  }

  depends_on = [aws_internet_gateway.igw]
}

# ------------------------------------------------------------------------------
# PHASE 2: ROUTING & CHAINED SECURITY GROUPS
# ------------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Public-RouteTable"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "Private-RouteTable"
  }
}

resource "aws_route_table_association" "pub_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "pub_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "priv_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "priv_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

# Security Group Chaining: ALB-SG -> Web-SG -> DB-SG
resource "aws_security_group" "alb_sg" {
  name        = "ALB-SG"
  description = "Public Inbound HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
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

resource "aws_security_group" "web_sg" {
  name        = "Web-SG"
  description = "Private App Traffic from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name        = "DB-SG"
  description = "Private DB Access from Web Tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------------------------------
# PHASE 3: COMPLIANT TARGET EC2 NODES
# ------------------------------------------------------------------------------
resource "aws_instance" "web_1" {
  ami                                  = data.aws_ami.amazon_linux.id
  instance_type                        = "t3.micro"
  subnet_id                            = aws_subnet.private_1.id
  vpc_security_group_ids               = [aws_security_group.web_sg.id]
  instance_initiated_shutdown_behavior = "terminate"

  credit_specification {
    cpu_credits = "standard"
  }

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              EC2_AZ=$(wget -q -O - http://169.254.169.254/latest/meta-data/placement/availability-zone)
              EC2_ID=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)
              echo "<h1>AWS Architecture Lab - Target Server</h1><p><b>Instance ID:</b> $EC2_ID</p><p><b>Availability Zone:</b> $EC2_AZ</p>" > /var/www/html/index.html
              echo "OK" > /var/www/html/healthz
              EOF

  tags = {
    Name = "Web-Server-1"
  }
}

resource "aws_instance" "web_2" {
  ami                                  = data.aws_ami.amazon_linux.id
  instance_type                        = "t3.micro"
  subnet_id                            = aws_subnet.private_2.id
  vpc_security_group_ids               = [aws_security_group.web_sg.id]
  instance_initiated_shutdown_behavior = "terminate"

  credit_specification {
    cpu_credits = "standard"
  }

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              EC2_AZ=$(wget -q -O - http://169.254.169.254/latest/meta-data/placement/availability-zone)
              EC2_ID=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)
              echo "<h1>AWS Architecture Lab - Target Server</h1><p><b>Instance ID:</b> $EC2_ID</p><p><b>Availability Zone:</b> $EC2_AZ</p>" > /var/www/html/index.html
              echo "OK" > /var/www/html/healthz
              EOF

  tags = {
    Name = "Web-Server-2"
  }
}

# ------------------------------------------------------------------------------
# PHASE 4: APPLICATION LOAD BALANCER
# ------------------------------------------------------------------------------
resource "aws_lb_target_group" "web_tg" {
  name        = "Architect-Web-TG"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/healthz"
    protocol            = "HTTP"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "web_1" {
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.web_1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "web_2" {
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.web_2.id
  port             = 80
}

resource "aws_lb" "alb" {
  name               = "Architect-ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# ------------------------------------------------------------------------------
# DYNAMIC OUTPUTS
# ------------------------------------------------------------------------------
output "vpc_id" {
  value = aws_vpc.main.id
}

output "alb_endpoint" {
  value = "http://${aws_lb.alb.dns_name}"
}
