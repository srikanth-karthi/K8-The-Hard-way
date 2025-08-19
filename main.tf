terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}


provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = "srikanth-k8-the-hard-way"
    }
  }
}

resource "aws_vpc" "kubernetes" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_internet_gateway" "kubernetes" {
  vpc_id = aws_vpc.kubernetes.id
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.kubernetes.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name                                         = "public-subnet"
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/srikanth-k8s-hardway" = "shared"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.kubernetes.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name                                         = "private-subnet"
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/srikanth-k8s-hardway" = "shared"
  }
}


resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "nat-gateway-eip"
  }

  depends_on = [aws_internet_gateway.kubernetes]
}

resource "aws_nat_gateway" "kubernetes" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "kubernetes-nat-gateway"
  }

  depends_on = [aws_internet_gateway.kubernetes]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.kubernetes.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kubernetes.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.kubernetes.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.kubernetes.id
  }

  tags = {
    Name = "private-route-table"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}


data "aws_availability_zones" "available" {
  state = "available"
}


resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.kubernetes.id
  cidr_block              = var.public_subnet_cidr_b          # e.g., 10.240.1.0/24 (NON-overlapping)
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name                                         = "public-subnet-b"
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/srikanth-k8s-hardway" = "shared"
  }
}

# attach it to the same public route table (with IGW default route)
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}