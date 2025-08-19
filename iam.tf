data "aws_caller_identity" "current" {}

# Trust policy: allow EC2 to assume the role
data "aws_iam_policy_document" "workers_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Create workers IAM role
resource "aws_iam_role" "workers" {
  name               = "worker-role"
  assume_role_policy = data.aws_iam_policy_document.workers_trust.json
  description        = "Worker node role for K8s the Hard Way (ALB controller perms attached)"
}

# (Optional but useful) SSM access to the instances
resource "aws_iam_role_policy_attachment" "workers_ssm_core" {
  role       = aws_iam_role.workers.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile so you can attach this role to the worker EC2 instances
resource "aws_iam_instance_profile" "workers" {
  name = "worker-profile"
  role = aws_iam_role.workers.name
}

# Official AWS Load Balancer Controller policy from file
resource "aws_iam_policy" "lbc_official" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "Official AWS LBC policy (keep file iam_policy.json updated from upstream)"
  policy      = file("${path.module}/iam_policy.json")
}


data "aws_iam_policy_document" "lbc_sg_scope_doc" {
  statement {
    sid    = "LBCSecurityGroupIngressScopedToVPC"
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress"
    ]
    resources = ["*"]

    condition {
      test     = "ArnEquals"
      variable = "ec2:Vpc"
      values   = [aws_vpc.kubernetes.arn]
    }
  }
}

resource "aws_iam_policy" "lbc_sg_scope" {
  name        = "AWSLoadBalancerControllerSGScoped"
  description = "Scope SG ingress/egress edits to this VPC"
  policy      = data.aws_iam_policy_document.lbc_sg_scope_doc.json
}

# Attach both policies to the workers role
resource "aws_iam_role_policy_attachment" "workers_attach_official" {
  role       = aws_iam_role.workers.name
  policy_arn = aws_iam_policy.lbc_official.arn
}

resource "aws_iam_role_policy_attachment" "workers_attach_scope" {
  role       = aws_iam_role.workers.name
  policy_arn = aws_iam_policy.lbc_sg_scope.arn
}

