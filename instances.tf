data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"]

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "jumpbox" {
  ami                    = data.aws_ami.debian.id
  instance_type          = var.jumpbox_instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.jumpbox.id]
  subnet_id              = aws_subnet.public.id
  private_ip             = "10.240.0.10"

  root_block_device {
    volume_type = "gp3"
    volume_size = var.volume_size_gb
    encrypted   = true
  }
  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash
              hostnamectl set-hostname jumpbox
              EOF

  tags = {
    Name = "jumpbox"
  }
}

resource "aws_instance" "controlplane" {
  count                  = var.controlplane_count
  ami                    = data.aws_ami.debian.id
  instance_type          = var.controlplane_instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.kubernetes_controlplane.id]
  subnet_id              = aws_subnet.private.id
  private_ip             = "10.240.0.7${count.index}"

  root_block_device {
    volume_type = "gp3"
    volume_size = var.volume_size_gb
    encrypted   = true
  }

  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash
              hostnamectl set-hostname server-${count.index}
              EOF

  tags = {
    Name = "controlplane-${count.index}"
  }
}


resource "aws_instance" "workers" {
  count                  = var.worker_count
  ami                    = data.aws_ami.debian.id
  instance_type          = var.worker_instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.kubernetes_workers.id]
  subnet_id              = aws_subnet.private.id
  private_ip             = "10.240.0.8${count.index}"
    source_dest_check = false

  root_block_device {
    volume_type = "gp3"
    volume_size = var.volume_size_gb
    encrypted   = true
  }
  user_data_replace_on_change = true
  user_data                   = <<-EOF
              #!/bin/bash
              hostnamectl set-hostname node-${count.index}
              EOF

  tags = {
    Name = "worker-${count.index}"
  }
}

