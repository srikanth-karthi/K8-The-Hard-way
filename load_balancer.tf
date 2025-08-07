# Network Load Balancer for Kubernetes API Server (only for multiple control planes)
resource "aws_lb" "kubernetes_api" {
  count              = var.controlplane_count > 1 ? 1 : 0
  name               = "kubernetes-api-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.private.id]
  security_groups    = [aws_security_group.kubernetes_nlb.id]

  enable_deletion_protection = false

  tags = {
    Name = "kubernetes-api-nlb"
  }
}

resource "aws_lb_target_group" "kubernetes_api" {
  count    = var.controlplane_count > 1 ? 1 : 0
  name     = "kubernetes-api-tg"
  port     = 6443
  protocol = "TCP"
  vpc_id   = aws_vpc.kubernetes.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    port                = "traffic-port"
    protocol            = "TCP"
    timeout             = 10
    unhealthy_threshold = 2
    # ✅ Do NOT add matcher here
  }

  tags = {
    Name = "kubernetes-api-tg"
  }
}



# Target Group Attachments for Control Plane Instances
resource "aws_lb_target_group_attachment" "kubernetes_api" {
  count            = var.controlplane_count > 1 ? var.controlplane_count : 0
  target_group_arn = aws_lb_target_group.kubernetes_api[0].arn
  target_id        = aws_instance.controlplane[count.index].id
  port             = 6443
}

# Listener for Kubernetes API Server
resource "aws_lb_listener" "kubernetes_api" {
  count             = var.controlplane_count > 1 ? 1 : 0
  load_balancer_arn = aws_lb.kubernetes_api[0].arn
  port              = "6443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kubernetes_api[0].arn
  }
}