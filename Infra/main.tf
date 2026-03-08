
# A simple test resource to prove the connection actually works
resource "aws_vpc" "test_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "DevOps-Test-VPC"
  }
}
