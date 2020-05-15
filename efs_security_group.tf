resource "aws_security_group" "efs" {
  count       = var.enable_efs ? 1 : 0
  name        = "${var.swarm_name}-efs-security-group"
  description = "Allows NFS traffic from instances within the VPC."
  vpc_id      = aws_vpc.main.id

  egress {
    cidr_blocks = [var.vpc_cidr]
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
  }

  ingress {
    cidr_blocks = [var.vpc_cidr]
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
  }
}
