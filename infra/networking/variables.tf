variable "aws_region" {
  default = "us-east-1"
}

variable "project" {
  default = "cloudmart"
}

variable "environment" {
  default = "prod"
}

variable "team" {
  default = "ec2much"
}

variable "owner" {
  default = "notec2much@yahoo.com"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  default = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_data_subnet_cidrs" {
  default = ["10.0.21.0/24", "10.0.22.0/24"]
}