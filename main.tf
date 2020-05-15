terraform {
  backend "s3" {
  }
}

locals {
  default_sg      = [aws_security_group.aws-common.id, aws_security_group.aws-swarm.id]
  gluster_sg      = var.enable_gluster ? [aws_security_group.aws-gluster[0].id] : []
  efs_sg          = var.enable_efs ? [aws_security_group.efs[0].id] : []
  security_groups = concat(local.default_sg, local.gluster_sg, local.efs_sg)
}

resource "aws_key_pair" "default" {
  key_name   = var.key_pair_name
  public_key = file(var.key_path)
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.swarm_name}-vpc"
  }
}

resource "aws_subnet" "public" {
  availability_zone = var.availability_zone
  cidr_block        = var.subnet_public_cidr
  vpc_id            = aws_vpc.main.id

  tags = {
    Name = "${var.swarm_name}-subnet-public"
  }
}

resource "aws_subnet" "private" {
  availability_zone = var.availability_zone
  cidr_block        = var.subnet_private_cidr
  vpc_id            = aws_vpc.main.id

  tags = {
    Name = "${var.swarm_name}-subnet-private"
  }
}

resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.swarm_name}-ig"
  }
}

resource "aws_eip" "eip_natgw" {
  vpc           = true
  depends_on    = [aws_internet_gateway.gateway]
  tags = {
    Name = "${var.swarm_name}-eip-natgw"
  }
}

resource "aws_nat_gateway" "natgw" {
  allocation_id   = aws_eip.eip_natgw.id
  subnet_id       = aws_subnet.public.id
  depends_on      = [aws_internet_gateway.gateway]
  tags = {
    Name = "${var.swarm_name}-natgw"
  }
}

resource "aws_vpn_gateway" "vgw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.swarm_name}-vgw"
  }
}

resource "aws_vpn_connection" "vpn" {
  vpn_gateway_id      = aws_vpn_gateway.vgw.id
  customer_gateway_id = var.customer_gateway_id
  type                = "ipsec.1"
  static_routes_only  = true
  tags = {
    Name = "${var.swarm_name}-vpn"
  }    
}

resource "aws_vpn_connection_route" "vpn_route" {
  destination_cidr_block  = "172.30.0.0/16"
  vpn_connection_id       = aws_vpn_connection.vpn.id
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gateway.id
  }

  tags = {
    Name = "${var.swarm_name}-main"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gateway.id
  }
  
  route {
    cidr_block = "172.30.0.0/16"
    gateway_id = aws_internet_gateway.gateway.id
  }

  tags = {
    Name = "${var.swarm_name}-public"
  }
}

resource "aws_main_route_table_association" "main_route" {
  vpc_id         = aws_vpc.main.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "public_route" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id            = aws_vpc.main.id

  route {
    cidr_block      = "0.0.0.0/0"
    nat_gateway_id  = aws_nat_gateway.natgw.id
  }

  route {
    cidr_block      = "172.30.0.0/16"
    gateway_id      = aws_internet_gateway.gateway.id
  }

  tags = {
    Name = "${var.swarm_name}-private"
  }
}

resource "aws_route_table_association" "private_route" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_ebs_volume" "ebs_volume" {
  availability_zone = aws_instance.manager[0].availability_zone
  count             = var.enable_gluster ? var.swarm_manager_count : 0
  size              = 1
}

resource "aws_volume_attachment" "ebs_attachment" {
  count        = var.enable_gluster ? var.swarm_manager_count : 0
  device_name  = "/dev/xvdf"
  force_detach = true
  instance_id  = element(aws_instance.manager.*.id, count.index)
  volume_id    = element(aws_ebs_volume.ebs_volume.*.id, count.index)
}

resource "aws_efs_file_system" "main" {
  count          = var.enable_efs ? 1 : 0
  creation_token = var.swarm_name

  tags = {
    Name = var.swarm_name
  }
}

resource "aws_efs_mount_target" "main" {
  count           = var.enable_efs ? 1 : 0
  file_system_id  = aws_efs_file_system.main[0].id
  subnet_id       = aws_subnet.private.id
  security_groups = [aws_security_group.efs[0].id]
}

resource "aws_instance" "manager" {
  ami                         = var.ami
  availability_zone           = var.availability_zone
  count                       = var.swarm_manager_count
  instance_type               = var.manager_instance_type
  key_name                    = aws_key_pair.default.id
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = true
  vpc_security_group_ids      = local.security_groups
  root_block_device {
    volume_type               = "gp2"
    volume_size               = "30"
    delete_on_termination     = "true"
  }
  ebs_block_device {
    device_name               = "/dev/sdb"
    volume_type               = "gp2"
    volume_size               = "100"
    delete_on_termination     = "true"
  }

  tags = {
    Name = format(
      "%s-%s-%02d",
      var.swarm_name,
      var.swarm_manager_name,
      count.index + 1
    )
    "Node Type" = "${var.swarm_name}-swarm-manager"
  }

  connection {
    host    = coalesce(self.public_ip, self.private_ip)
    type    = "ssh"
    user    = var.ssh_user
    timeout = var.connection_timeout
  }

  provisioner "remote-exec" {
    inline = [
      "echo '127.0.1.1 ${self.tags.Name}' | sudo tee -a /etc/hosts",
      "sudo hostnamectl set-hostname ${self.tags.Name}",
      "echo '\n${var.ssh_public_keys}\n' >> /home/ubuntu/.ssh/authorized_keys",
    ]
  }
}

resource "aws_instance" "worker" {
  ami                         = var.ami
  availability_zone           = var.availability_zone
  count                       = var.swarm_worker_count
  instance_type               = var.worker_instance_type
  key_name                    = aws_key_pair.default.id
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = true
  vpc_security_group_ids      = local.security_groups
  root_block_device {
    volume_type               = "gp2"
    volume_size               = "30"
    delete_on_termination     = "true"
  }
  ebs_block_device {
    device_name               = "/dev/sdb"
    volume_type               = "gp2"
    volume_size               = "100"
    delete_on_termination     = "true"
  }

  tags = {
    Name = format(
      "%s-%s-%02d",
      var.swarm_name,
      var.swarm_worker_name,
      count.index + 1
    )
    "Node Type" = "${var.swarm_name}-swarm-worker"
  }

  connection {
    host    = coalesce(self.public_ip, self.private_ip)
    type    = "ssh"
    user    = var.ssh_user
    timeout = var.connection_timeout
  }

  provisioner "remote-exec" {
    inline = [
      "echo '127.0.1.1 ${self.tags.Name}' | sudo tee -a /etc/hosts",
      "sudo hostnamectl set-hostname ${self.tags.Name}",
      "echo '\n${var.ssh_public_keys}\n' >> /home/ubuntu/.ssh/authorized_keys",
    ]
  }
}

resource "aws_instance" "backup" {
  ami                         = var.ami
  availability_zone           = var.availability_zone
  count                       = var.swarm_backup_count
  instance_type               = var.backup_instance_type
  key_name                    = aws_key_pair.default.id
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = true
  vpc_security_group_ids      = local.security_groups
  root_block_device {
    volume_type               = "gp2"
    volume_size               = "30"
    delete_on_termination     = "true"
  }

  tags = {
    Name = format(
      "%s-%s-%02d",
      var.swarm_name,
      var.swarm_backup_name,
      count.index + 1
    )
    "Node Type" = "${var.swarm_name}-swarm-backup"
  }

  connection {
    host    = coalesce(self.public_ip, self.private_ip)
    type    = "ssh"
    user    = var.ssh_user
    timeout = var.connection_timeout
  }

  provisioner "remote-exec" {
    inline = [
      "echo '127.0.1.1 ${self.tags.Name}' | sudo tee -a /etc/hosts",
      "sudo hostnamectl set-hostname ${self.tags.Name}",
      "echo '\n${var.ssh_public_keys}\n' >> /home/ubuntu/.ssh/authorized_keys",
    ]
  }
}

resource "aws_eip_association" "eip_association" {
  instance_id   = aws_instance.manager[0].id
  allocation_id = var.eip_allocation_id
}

locals {
  all_ips                     = aws_instance.manager.*.public_ip
  first_ip_to_remove          = [aws_instance.manager[0].public_ip]
  list_with_first_ip_in_front = distinct(concat(local.first_ip_to_remove, local.all_ips))
  list_without_first_ip = slice(
    local.list_with_first_ip_in_front,
    1,
    length(local.list_with_first_ip_in_front),
  )

  elastic_ip_list = [aws_eip_association.eip_association.public_ip]

  manager_public_ip_list = concat(local.elastic_ip_list, local.list_without_first_ip)
}

data "template_file" "ansible_inventory" {
  template = file("${path.module}/ansible_inventory.tpl")

  vars = {
    env                 = var.env
    managers            = join("\n", local.manager_public_ip_list)
    workers             = join("\n", aws_instance.worker.*.public_ip)
    manager_private_ips = join("\n", aws_instance.manager.*.private_ip)
    workers_private_ips = join("\n", aws_instance.worker.*.private_ip)
    backup_private_ips = join("\n", aws_instance.backup.*.private_ip)
    efs_host            = var.enable_efs ? "efs dns_name=${aws_efs_mount_target.main[0].dns_name}" : ""
  }
  # managers = "${join("\n", "${var.eip_allocation_id == "null" ? aws_instance.manager.*.public_ip : local.manager_public_ip_list}")}"
  # Conditional operator on list  will be supported on Terraform 0.12. See issue https://github.com/hashicorp/terraform/issues/18259#issuecomment-434809754
}

resource "null_resource" "ansible_inventory_file" {
  triggers = {
    managers            = join("\n", aws_instance.manager.*.public_ip)
    workers             = join("\n", aws_instance.worker.*.public_ip)
    manager_private_ips = join("\n", aws_instance.manager.*.private_ip)
    workers_private_ips = join("\n", aws_instance.worker.*.private_ip)
    backup_private_ips = join("\n", aws_instance.backup.*.private_ip)
  }

  provisioner "local-exec" {
    command = "echo \"${data.template_file.ansible_inventory.rendered}\" > \"${var.env}\".yml"
  }

  depends_on = [aws_eip_association.eip_association]
}
