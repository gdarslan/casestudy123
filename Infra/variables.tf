variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "project_name" {
  type    = string
  default = "casestudy1"
}

variable "db_name" {
  type    = string
  default = "casedb"
}

variable "db_username" {
  type    = string
  default = "deniz"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}