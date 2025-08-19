output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.kubernetes.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "jumpbox_public_ip" {
  description = "Public IP address of jumpbox"
  value       = aws_instance.jumpbox.public_ip
}

output "jumpbox_private_ip" {
  description = "Private IP address of jumpbox"
  value       = aws_instance.jumpbox.private_ip
}


output "controlplane_private_ips" {
  description = "Private IP addresses of controlplane instances"
  value       = aws_instance.controlplane[*].private_ip
}



output "worker_private_ips" {
  description = "Private IP addresses of worker instances"
  value       = aws_instance.workers[*].private_ip
}

output "jumpbox_security_group_id" {
  description = "Security group ID for jumpbox"
  value       = aws_security_group.jumpbox.id
}

output "kubernetes_controlplane_security_group_id" {
  description = "Security group ID for Kubernetes controlplane"
  value       = aws_security_group.kubernetes_controlplane.id
}

output "kubernetes_workers_security_group_id" {
  description = "Security group ID for Kubernetes workers"
  value       = aws_security_group.kubernetes_workers.id
}

output "key_name" {
  description = "Name of the key pair used for instances"
  value       = var.key_name
}

output "internet_gateway_id" {
  description = "ID of the internet gateway"
  value       = aws_internet_gateway.kubernetes.id
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway"
  value       = aws_nat_gateway.kubernetes.id
}

output "nat_gateway_eip" {
  description = "Elastic IP address of the NAT gateway"
  value       = aws_eip.nat.public_ip
}

output "kubernetes_api__dns_name" {
  description = "DNS name of the Kubernetes API Load Balancer"
  value       = var.controlplane_count > 1 ? aws_lb.kubernetes_api[0].dns_name : null
}

output "kubernetes_api_zone_id" {
  description = "Zone ID of the Kubernetes API  Load Balancer"
  value       = var.controlplane_count > 1 ? aws_lb.kubernetes_api[0].zone_id : null
}

output "alb_sg_id" {
  description = "Security group ID for the ALB"
  value       = aws_security_group.alb.id
}

