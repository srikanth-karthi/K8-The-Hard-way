resource "aws_security_group" "jumpbox" {
  name_prefix = "jumpbox-"
  vpc_id      = aws_vpc.kubernetes.id

  ingress {
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
    Name = "jumpbox"
  }
}

resource "aws_security_group" "kubernetes_controlplane" {
  name_prefix = "kubernetes-controlplane-"
  vpc_id      = aws_vpc.kubernetes.id

  

  # SSH access ONLY from the jumpbox
  ingress {
    description     = "SSH from jumpbox only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.jumpbox.id]
  }

  # Allow VXLAN pod network from all nodes
ingress {
  description = "Pod network VXLAN"
  from_port   = 8472
  to_port     = 8472
  protocol    = "udp"
  cidr_blocks = [var.vpc_cidr]
}

# Allow DNS queries to CoreDNS on workers
ingress {
  description = "Cluster DNS UDP"
  from_port   = 53
  to_port     = 53
  protocol    = "udp"
  cidr_blocks = [var.vpc_cidr]
}


  # API server access (port 6443) for internal clients like kubelets
  ingress {
    description = "API access from VPC"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]  # 👈 includes worker nodes and internal traffic
  }


  # etcd client communication (used by apiserver) — internal only
  ingress {
    description = "etcd ports (internal only)"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  # kubelet/scheduler/controller-manager ports — internal control plane usage
  ingress {
    description = "Kubelet and scheduler"
    from_port   = 10250
    to_port     = 10252
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  # Multi-master: etcd peer-to-peer between master nodes
  ingress {
    description     = "etcd peer communication between masters"
    from_port       = 2380
    to_port         = 2380
    protocol        = "tcp"
    self = true
  }

  # Multi-master: etcd client access from other masters (apiserver)
  ingress {
    description     = "etcd client access between control planes"
    from_port       = 2379
    to_port         = 2379
    protocol        = "tcp"
    self = true
  }

  # Multi-master: kubelet/scheduler/manager comms between masters
  ingress {
    description     = "kubelet and control plane peer communication"
    from_port       = 10250
    to_port         = 10252
    protocol        = "tcp"
    self = true
  }

  # Allow outbound traffic to the internet/VPC
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kubernetes-controlplane"
  }
}

resource "aws_security_group" "kubernetes_workers" {
  name_prefix = "kubernetes-workers-"
  vpc_id      = aws_vpc.kubernetes.id

  ingress {
    description     = "Kubelet access from control plane"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    self = true
  }
    ingress {
    description     = "Kubelet access from Jumphost"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
# add this ONE rule to aws_security_group.kubernetes_workers
ingress {
  description     = "TEMP: all protocols from control-plane"
  from_port       = 0
  to_port         = 0
  protocol        = "-1"
  security_groups = [aws_security_group.kubernetes_controlplane.id]
}


  ingress {
    description     = "All TCP from control-plane (masters)"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.kubernetes_controlplane.id]
  }

  # 🔹 Allow Flannel VXLAN from masters (if using Flannel)
  ingress {
    description     = "VXLAN (UDP 8472) from control-plane"
    from_port       = 8472
    to_port         = 8472
    protocol        = "udp"
    security_groups = [aws_security_group.kubernetes_controlplane.id]
  }

  # 🔹 Allow ICMP from masters (optional but useful for diag)
  ingress {
    description     = "ICMP from control-plane"
    from_port       = -1
    to_port         = -1
    protocol        = "icmp"
    security_groups = [aws_security_group.kubernetes_controlplane.id]
  }

  # Allow control plane to talk to kubelet API
ingress {
  description     = "Kubelet API from control plane"
  from_port       = 10250
  to_port         = 10250
  protocol        = "tcp"
  security_groups = [aws_security_group.kubernetes_controlplane.id]
}

# Allow DNS queries between all nodes
ingress {
  description = "Cluster DNS UDP"
  from_port   = 53
  to_port     = 53
  protocol    = "udp"
  cidr_blocks = [var.vpc_cidr]
}

# Allow VXLAN pod networking (Flannel)
ingress {
  description = "Pod network VXLAN"
  from_port   = 8472
  to_port     = 8472
  protocol    = "udp"
  cidr_blocks = [var.vpc_cidr]
}




  ingress {
    description     = "SSH from jumpbox only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.jumpbox.id]
  }

  ingress {
    description = "NodePort services (optional)"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kubernetes-workers"
  }
}

resource "aws_security_group" "kubernetes_nlb" {
  name_prefix = "kubernetes-nlb-"
  vpc_id      = aws_vpc.kubernetes.id

  ingress {
    description = "Kubernetes API access via NLB"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kubernetes-nlb"
  }
}
