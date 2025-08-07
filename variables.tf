variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
}


variable "jumpbox_instance_type" {
  description = "EC2 instance type for jumpbox"
  type        = string
}

variable "controlplane_instance_type" {
  description = "EC2 instance type for Kubernetes controlplane"
  type        = string
}

variable "worker_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
}

variable "key_name" {
  description = "AWS key pair name"
  type        = string
}

variable "controlplane_count" {
  description = "Number of Kubernetes controlplane nodes"
  type        = number
}

variable "worker_count" {
  description = "Number of Kubernetes worker nodes"
  type        = number
}

variable "volume_size_gb" {
  description = "Root volume size in GB for instances"
  type        = number
}