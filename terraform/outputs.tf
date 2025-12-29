# Output values from DefectDojo infrastructure

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.defectdojo.id
}

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.defectdojo.id
}

output "elastic_ip" {
  description = "Elastic IP address"
  value       = local.eip_public_ip
}

output "eip_allocation_id" {
  description = "Elastic IP allocation ID (save this for future deployments)"
  value       = local.eip_allocation_id
}

output "defectdojo_url" {
  description = "URL to access DefectDojo"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "http://${local.eip_public_ip}:8080"
}

output "ssh_command" {
  description = "SSH command to connect to instance"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${local.eip_public_ip}"
}

output "s3_backup_bucket" {
  description = "S3 bucket for backups"
  value       = aws_s3_bucket.backups.id
}
