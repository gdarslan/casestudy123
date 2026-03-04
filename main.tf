terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# This tells Terraform which cloud to use and where to build resources
provider "aws" {
  region = "eu-central-1" 
}

# A simple test resource to prove the connection actually works
resource "aws_vpc" "test_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "DevOps-Test-VPC"
  }
}