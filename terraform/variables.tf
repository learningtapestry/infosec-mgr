# Input variables for DefectDojo infrastructure

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 30
}

variable "key_name" {
  description = "Name of SSH key pair"
  type        = string
  default     = "infosec-key"
}

variable "domain_name" {
  description = "Domain name for DefectDojo (optional, for SSL)"
  type        = string
  default     = ""
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "defectdojo_admin_password" {
  description = "Admin password for DefectDojo (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_repo" {
  description = "GitHub repository to clone"
  type        = string
  default     = "https://github.com/learningtapestry/infosec-mgr.git"
}

variable "existing_eip_allocation_id" {
  description = "Allocation ID of existing Elastic IP to use. If empty, creates new EIP."
  type        = string
  default     = ""
}

variable "create_key_pair" {
  description = "Whether to create a new SSH key pair. Set to false if key already exists."
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Email address for infrastructure and backup alerts"
  type        = string
  default     = "admins@learningtapestry.com"
}

