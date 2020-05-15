resource "aws_security_group" "aws-common" {
  name   = "${var.swarm_name}-common-security-group"
  vpc_id = aws_vpc.main.id

  # http-outbound-sg
  egress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 4567
    to_port          = 4567
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port = 8000
    to_port   = 9999
    protocol  = "tcp"
    self      = true
  }

  # https-outbound-sg
  egress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # dns-outbound-sg
  egress {
    from_port        = 53
    to_port          = 53
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # dns-outbound-sg
  egress {
    from_port        = 53
    to_port          = 53
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # ntp-outbound-sg
  egress {
    from_port        = 123
    to_port          = 123
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # inbound-ssh-sg
  ingress {
    description = "TF-For Custom SSH Service"
    from_port   = 55051
    to_port     = 55051
    protocol    = "tcp"
    cidr_blocks = ["172.30.0.0/16"]
  }

  # inbound-ssh-sg
  ingress {
    description = "TF-For Custom SSH Service"
    from_port   = 55051
    to_port     = 55051
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # inbound-ssh-sg
  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description = "TF-For HTTP Service"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description = "TF-For HTTPS Service"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port = 8000
    to_port   = 9999
    protocol  = "tcp"
    self      = true
  }

  ingress {
    description = "TF-Allow ping"
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

