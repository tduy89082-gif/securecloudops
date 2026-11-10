variable "aws_region" {
  description = "AWS region used by SecureCloudOps"
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Resource name prefix"
  type        = string
  default     = "securecloudops"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR range for the project VPC"
  type        = string
  default     = "10.0.0.0/16"
}
