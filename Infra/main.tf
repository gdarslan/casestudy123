
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

# ==========================================
# VPC & PEERING (REQ-NCA-P1-02)
# ==========================================
resource "aws_vpc" "hub" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${local.name}-hub-vpc" }
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${local.name}-spoke-vpc" }
}

resource "aws_vpc_peering_connection" "hub_to_spoke" {
  peer_vpc_id = aws_vpc.main.id
  vpc_id      = aws_vpc.hub.id
  auto_accept = true
  tags = { Name = "${local.name}-hub-spoke-peering" }
}

# ==========================================
# HUB NETWORK & BASTION
# ==========================================
resource "aws_subnet" "hub_public" {
  vpc_id                  = aws_vpc.hub.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = local.az1
  map_public_ip_on_launch = true
  tags = { Name = "${local.name}-hub-public" }
}

resource "aws_internet_gateway" "hub_igw" {
  vpc_id = aws_vpc.hub.id
  tags   = { Name = "${local.name}-hub-igw" }
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
  tags = { Name = "${local.name}-hub-rt" }
}

resource "aws_route_table_association" "hub_assoc" {
  subnet_id      = aws_subnet.hub_public.id
  route_table_id = aws_route_table.hub_rt.id
}

resource "aws_security_group" "bastion_sg" {
  name        = "${local.name}-bastion-sg"
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
  tags = { Name = "${local.name}-bastion-sg" }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.hub_public.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  tags = { Name = "${local.name}-bastion" }
}

# ==========================================
# SPOKE NETWORK (MAIN VPC)
# ==========================================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "${local.name}-igw" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = local.az1
  map_public_ip_on_launch = true
  tags = { Name = "${local.name}-public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = local.az2
  map_public_ip_on_launch = true
  tags = { Name = "${local.name}-public-b" }
}

resource "aws_subnet" "app_private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = local.az1
  tags = { Name = "${local.name}-app-private-a" }
}

resource "aws_subnet" "app_private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = local.az2
  tags = { Name = "${local.name}-app-private-b" }
}

resource "aws_subnet" "db_private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = local.az1
  tags = { Name = "${local.name}-db-private-a" }
}

resource "aws_subnet" "db_private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.22.0/24"
  availability_zone = local.az2
  tags = { Name = "${local.name}-db-private-b" }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = { Name = "${local.name}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.igw]
  tags = { Name = "${local.name}-nat" }
}

# ==========================================
# SPOKE ROUTING
# ==========================================
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
  tags = { Name = "${local.name}-public-rt" }
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
  tags = { Name = "${local.name}-private-rt" }
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

# ==========================================
# SECURITY GROUPS
# ==========================================
resource "aws_security_group" "alb_sg" {
  name        = "${local.name}-alb-sg"
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
  tags = { Name = "${local.name}-alb-sg" }
}

resource "aws_security_group" "app_sg" {
  name        = "${local.name}-app-sg"
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
  tags = { Name = "${local.name}-app-sg" }
}

resource "aws_security_group" "db_sg" {
  name        = "${local.name}-db-sg"
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
  tags = { Name = "${local.name}-db-sg" }
}

# ==========================================
# LOAD BALANCER
# ==========================================
resource "aws_lb" "app_alb" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]
  tags = { Name = "${local.name}-alb" }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "${local.name}-tg"
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
  tags = { Name = "${local.name}-tg" }
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

# ==========================================
# AUTOSCALING (REQ-NCA-P1-09)
# ==========================================
resource "aws_launch_template" "app_lt" {
  name_prefix   = "${local.name}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.app_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y nginx
    systemctl enable nginx
    echo "<h1>${var.project_name} web server connected to db.deniztech.internal</h1><p>Hostname: $(hostname)</p>" > /usr/share/nginx/html/index.html
    systemctl start nginx
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${local.name}-app" }
  }
}

resource "aws_autoscaling_group" "app_asg" {
  name                = "${local.name}-asg"
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
    value               = "${local.name}-app-instance"
    propagate_at_launch = true
  }
}

# Bu politika yük altında sistemi çökmeden ayakta tutar.
resource "aws_autoscaling_policy" "cpu_scaling" {
  name                   = "${local.name}-cpu-policy"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0 
  }
}

# ==========================================
# DATABASE (REQ-NCA-P1-03)
# ==========================================
resource "aws_db_subnet_group" "db_subnet_group" {
  name = "${local.name}-db-subnet-group"
  subnet_ids = [
    aws_subnet.db_private_a.id,
    aws_subnet.db_private_b.id
  ]
  tags = { Name = "${local.name}-db-subnet-group" }
}

resource "aws_db_instance" "mysql" {
  identifier             = "${local.name}-mysql"
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  publicly_accessible    = false
  skip_final_snapshot    = true # Öğrenci hesabı için silerken uğraştırmasın
  multi_az               = false
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = { Name = "${local.name}-mysql" }
}

# ==========================================
# PRIVATE DNS (REQ-NCA-P1-04)
# ==========================================
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

# ==========================================
# OUTPUTS
# ==========================================
output "alb_dns_name" {
  value = aws_lb.app_alb.dns_name
}
output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}