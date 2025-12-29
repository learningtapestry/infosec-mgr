# EC2 instance for DefectDojo

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Look up existing EIP if allocation ID provided
data "aws_eip" "existing" {
  count = var.existing_eip_allocation_id != "" ? 1 : 0
  id    = var.existing_eip_allocation_id
}

# Create new EIP only if no existing allocation ID provided
resource "aws_eip" "new" {
  count  = var.existing_eip_allocation_id == "" ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "defectdojo-eip"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Local values to abstract EIP source
locals {
  eip_allocation_id = var.existing_eip_allocation_id != "" ? data.aws_eip.existing[0].id : aws_eip.new[0].id
  eip_public_ip     = var.existing_eip_allocation_id != "" ? data.aws_eip.existing[0].public_ip : aws_eip.new[0].public_ip
}

# EC2 instance
resource "aws_instance" "defectdojo" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.defectdojo.id]
  iam_instance_profile   = aws_iam_instance_profile.defectdojo.name

  root_block_device {
    volume_size           = var.volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    github_repo    = var.github_repo
    domain_name    = var.domain_name
    admin_password = var.defectdojo_admin_password
    s3_bucket      = aws_s3_bucket.backups.id
  })

  tags = {
    Name = "defectdojo"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Associate EIP with instance
resource "aws_eip_association" "defectdojo" {
  instance_id   = aws_instance.defectdojo.id
  allocation_id = local.eip_allocation_id
}
