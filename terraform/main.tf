terraform {

  required_version = ">= 1.5"

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

#############################################
# VPC
#############################################

resource "aws_vpc" "main" {

  cidr_block = "10.0.0.0/16"

  enable_dns_hostnames = true

  tags = {
    Name = "github-actions-vpc"
  }
}

#############################################
# PUBLIC SUBNET
#############################################

resource "aws_subnet" "public" {

  vpc_id = aws_vpc.main.id

  cidr_block = "10.0.1.0/24"

  availability_zone = "eu-west-2a"

  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

#############################################
# INTERNET GATEWAY
#############################################

resource "aws_internet_gateway" "igw" {

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

#############################################
# ROUTE TABLE
#############################################

resource "aws_route_table" "public" {

  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"

    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public" {

  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

#############################################
# SECURITY GROUP
#############################################

resource "aws_security_group" "flask" {

  name = "flask-app-sg"

  description = "Allow Flask traffic"

  vpc_id = aws_vpc.main.id

  ingress {

    description = "Flask"

    from_port = 5000

    to_port = 5000

    protocol = "tcp"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  ingress {

    description = "SSH"

    from_port = 22

    to_port = 22

    protocol = "tcp"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  egress {

    from_port = 0

    to_port = 0

    protocol = "-1"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags = {
    Name = "flask-sg"
  }
}

#############################################
# EC2 ROLE
#############################################

resource "aws_iam_role" "ec2_role" {

  name = "GitHubActionsEC2Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

#############################################
# SSM POLICY
#############################################

resource "aws_iam_role_policy_attachment" "ssm" {

  role = aws_iam_role.ec2_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

#############################################
# S3 READ ACCESS
#############################################

resource "aws_iam_role_policy_attachment" "s3" {

  role = aws_iam_role.ec2_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

#############################################
# CLOUDWATCH
#############################################

resource "aws_iam_role_policy_attachment" "cloudwatch" {

  role = aws_iam_role.ec2_role.name

  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

#############################################
# INSTANCE PROFILE
#############################################

resource "aws_iam_instance_profile" "profile" {

  name = "GithubActionsEC2Profile"

  role = aws_iam_role.ec2_role.name
}

#############################################
# AMI
#############################################

data "aws_ami" "amazon_linux" {

  most_recent = true

  owners = ["amazon"]

  filter {

    name = "name"

    values = [
      "al2023-ami-*-x86_64"
    ]
  }
}

#############################################
# EC2
#############################################

resource "aws_instance" "flask" {

  ami = data.aws_ami.amazon_linux.id

  instance_type = "t2.micro"

  subnet_id = aws_subnet.public.id

  vpc_security_group_ids = [
    aws_security_group.flask.id
  ]

  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.profile.name

  user_data = <<-EOF
#!/bin/bash

dnf update -y

dnf install python3 python3-pip unzip git -y

mkdir -p /opt/application

chmod 777 /opt/application

echo "Server Ready" > /tmp/server-status.txt

EOF

  tags = {
    Name        = "FlaskApplication"
    Environment = "Production"
  }
}

#############################################
# OUTPUTS
#############################################

output "instance_id" {

  value = aws_instance.flask.id
}

output "public_ip" {

  value = aws_instance.flask.public_ip
}