
data "aws_availability_zones" "available" {}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["137112412989"] # Amazon

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

locals {
  name = var.project_name
  az1  = data.aws_availability_zones.available.names[0]
  az2  = data.aws_availability_zones.available.names[1]
}

# 
# VPC & PEERING (REQ-NCA-P1-02)

resource "aws_vpc" "hub" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "the-hub-vpc" }
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "A-spoke-vpc" }
}

resource "aws_vpc_peering_connection" "hub_to_spoke" {
  peer_vpc_id = aws_vpc.main.id
  vpc_id      = aws_vpc.hub.id
  auto_accept = true
  tags = { Name = "A-hub-spoke-peering" }
}

# 
# HUB NETWORK & BASTION

resource "aws_subnet" "hub_public" {
  vpc_id                  = aws_vpc.hub.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = local.az1
  map_public_ip_on_launch = true
  tags = { Name = "deniz-hub-public" }
}

resource "aws_internet_gateway" "hub_igw" {
  vpc_id = aws_vpc.hub.id
  tags   = { Name = "gtw-hub-igw" }
}

resource "aws_route_table" "hub_rt" {
  vpc_id = aws_vpc.hub.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hub_igw.id
  }
  
  # Spoke VPC'ye giden peering rotası
  route {
    cidr_block                = aws_vpc.main.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_spoke.id
  }
  tags = { Name = "peering-hub-rt" }
}

resource "aws_route_table_association" "hub_assoc" {
  subnet_id      = aws_subnet.hub_public.id
  route_table_id = aws_route_table.hub_rt.id
}

resource "aws_security_group" "bastion_sg" {
  name        = "d-bastion-sg"
  description = "Allow SSH to Bastion"
  vpc_id      = aws_vpc.hub.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Öğrenci işi olduğu için açık, normalde kendi IP'ni yazmalısın.
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "d-bastion-sg" }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.hub_public.id
  key_name      = "deniz-key"
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  tags = { Name = "the-bastion" }
}

# 
# SPOKE NETWORK (MAIN VPC)

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "spoke-gw" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = local.az1
  map_public_ip_on_launch = true
  tags = { Name = "public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = local.az2
  map_public_ip_on_launch = true
  tags = { Name = "public-b" }
}

resource "aws_subnet" "app_private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = local.az1
  tags = { Name = "-app-private-a" }
}

resource "aws_subnet" "app_private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = local.az2
  tags = { Name = "app-private-b" }
}

resource "aws_subnet" "db_private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = local.az1
  tags = { Name = "db-private-a" }
}

resource "aws_subnet" "db_private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.22.0/24"
  availability_zone = local.az2
  tags = { Name = "db-private-b" }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = { Name = "nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.igw]
  tags = { Name = "the-nat" }
}


# SPOKE ROUTING
# 
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  route {
    cidr_block                = aws_vpc.hub.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_spoke.id
  }
  tags = { Name = "public-rt" }
}

resource "aws_route_table_association" "public_a_assoc" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_route_table_association" "public_b_assoc" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  route {
    cidr_block                = aws_vpc.hub.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_spoke.id
  }
  tags = { Name = "private-rt" }
}

resource "aws_route_table_association" "app_private_a_assoc" {
  subnet_id      = aws_subnet.app_private_a.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "app_private_b_assoc" {
  subnet_id      = aws_subnet.app_private_b.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "db_private_a_assoc" {
  subnet_id      = aws_subnet.db_private_a.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "db_private_b_assoc" {
  subnet_id      = aws_subnet.db_private_b.id
  route_table_id = aws_route_table.private_rt.id
}

# 
# SECURITY GROUPS

resource "aws_security_group" "alb_sg" {
  name        = "the-alb-sg"
  description = "Allow HTTP from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "the-alb-sg" }
}

resource "aws_security_group" "app_sg" {
  name        = "the-app-sg"
  description = "Allow HTTP from ALB and SSH from Bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id] # Bastion'dan erişim
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "the-app-sg" }
}

resource "aws_security_group" "db_sg" {
  name        = "a-db-sg"
  description = "Allow MySQL from app and Bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id, aws_security_group.bastion_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "a-db-sg" }
}

# 
# LOAD BALANCER

resource "aws_lb" "app_alb" {
  name               = "applb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]
  tags = { Name = "applb" }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "a-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  tags = { Name = "a-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}


# AUTOSCALING (REQ-NCA-P1-09)
#
resource "aws_launch_template" "app_lt" {
  name_prefix   = "launchtemp-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.app_sg.id]


  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y nginx
    systemctl enable nginx
    systemctl start nginx

    # mevcut web sayfasi ayari
    echo "<h1> web server connected to db.deniztech.internal</h1><p>Hostname: $(hostname)</p>" > /usr/share/nginx/html/index.html
    
    #  monitoring aracini ayağa kaldiriyorum
    sudo usermod -aG docker ec2-user
    docker run -d --name=node-exporter -p 9100:9100 prom/node-exporter
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "tags-app" }
  }
}

resource "aws_autoscaling_group" "app_asg" {
  name                = "localname-asg"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = [
    aws_subnet.app_private_a.id,
    aws_subnet.app_private_b.id
  ]
  target_group_arns = [aws_lb_target_group.app_tg.arn]
  health_check_type = "ELB"


  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
    
  }

  tag {
    key                 = "Name"
    value               = "localname-app-instance"
    propagate_at_launch = true
  }
}




# DATABASE (REQ-NCA-P1-03)

resource "aws_db_subnet_group" "db_subnet_group" {
  name = "db-subnet-group"
  subnet_ids = [
    aws_subnet.db_private_a.id,
    aws_subnet.db_private_b.id
  ]
  tags = { Name = "db-subnet-group" }
}

resource "aws_db_instance" "mysql" {
  identifier             = "cs1-mysql-v2"
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "casedb"
  username               = "admin"
  password               = "denizpassword"
  publicly_accessible    = false
  skip_final_snapshot    = true # Öğrenci hesabı için silerken uğraştırmasın
  multi_az               = false
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = { Name = "cs1-mysql" }
}

#
# PRIVATE DNS (REQ-NCA-P1-04)

resource "aws_route53_zone" "private" {
  name = "deniztech.internal" 
  
  # DNS'i her iki VPC'ye de bağladık ki Bastion'dan da isimle erişebil.
  vpc {
    vpc_id = aws_vpc.main.id
  }
  vpc {
    vpc_id = aws_vpc.hub.id
  }
}

resource "aws_route53_record" "db" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "db.deniztech.internal"
  type    = "CNAME"
  ttl     = 300
  records = [aws_db_instance.mysql.address]
}

# OUTPUTS
# 
output "alb_dns_name" {
  value = aws_lb.app_alb.dns_name
}
output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

