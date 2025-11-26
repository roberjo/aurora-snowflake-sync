# ---------------------------------------------------------------------------------------------------------------------
# NETWORK MODULE: VPC
# ---------------------------------------------------------------------------------------------------------------------
# This module creates the networking foundation for the project.
# It sets up a Virtual Private Cloud (VPC) with public and private subnets,
# internet gateways for connectivity, and security groups to control traffic flow.

variable "vpc_cidr" {
  description = "CIDR block for the VPC (e.g., 10.0.0.0/16)."
}
variable "project_name" {
  description = "Project name for resource tagging."
}

# Main VPC
# The isolated network environment for all resources.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Private Subnets
# Used for resources that should not be directly accessible from the internet (e.g., Lambda, Databases).
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-${count.index + 1}"
  }
}

# Public Subnets
# Used for resources that need direct internet access (e.g., Load Balancers, NAT Gateways).
# In this architecture, they might be used for NAT Gateways if the Lambda needs outbound internet access.
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
  }
}

# Internet Gateway
# Allows communication between the VPC and the internet.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Public Route Table
# Routes traffic from public subnets to the Internet Gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Lambda Security Group
# Controls traffic to and from the Lambda function.
# Currently allows all outbound traffic (egress) to reach S3, Vault, etc.
resource "aws_security_group" "lambda_sg" {
  name        = "${var.project_name}-lambda-sg"
  description = "Security group for Lambda function"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-lambda-sg"
  }
}

# Aurora Security Group
# Controls traffic to the Aurora database.
# Explicitly allows ingress on port 5432 (PostgreSQL) ONLY from the Lambda Security Group.
resource "aws_security_group" "aurora_sg" {
  name        = "${var.project_name}-aurora-sg"
  description = "Security group for Aurora"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda_sg.id]
  }

  tags = {
    Name = "${var.project_name}-aurora-sg"
  }
}

data "aws_availability_zones" "available" {}

# Outputs
# Exposes resource IDs for use in other modules.
output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "lambda_sg_id" {
  value = aws_security_group.lambda_sg.id
}

output "aurora_sg_id" {
  value = aws_security_group.aurora_sg.id
}
