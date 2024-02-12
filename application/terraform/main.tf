provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      learn = "observability"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.77.0"

  name = "main-vpc"
  cidr = "10.0.0.0/16"

  azs                  = data.aws_availability_zones.available.names
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_dns_hostnames = true
  enable_dns_support   = true
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_launch_configuration" "lab" {
  name_prefix     = "terraform-aws-asg-"
  image_id        = data.aws_ami.ubuntu.id
  instance_type   = "t3.medium"
  user_data       = "${file("templates/server.yaml")}"
  security_groups = [aws_security_group.lab_server.id]
  key_name        = "vockey"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "lab" {
  name                 = "lab"
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2
  launch_configuration = aws_launch_configuration.lab.name
  vpc_zone_identifier  = module.vpc.public_subnets

  health_check_type    = "ELB"

  tag {
    key                 = "tier"
    value               = "fe"
    propagate_at_launch = true
  }

  tag {
    key                 = "env"
    value               = "lab"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "server"
    propagate_at_launch = true
  }
}

resource "aws_lb" "lab" {
  name               = "asg-lab-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lab_lb.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_listener" "lab" {
  load_balancer_arn = aws_lb.lab.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lab.arn
  }
}

resource "aws_lb_target_group" "lab" {
  name     = "asg-lab"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
}


resource "aws_autoscaling_attachment" "lab" {
  autoscaling_group_name = aws_autoscaling_group.lab.id
  alb_target_group_arn   = aws_lb_target_group.lab.arn
}

resource "aws_security_group" "lab_server" {
  name = "asg-lab-server"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  vpc_id = module.vpc.vpc_id
}

resource "aws_security_group" "lab_lb" {
  name = "asg-lab-lb"
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

  vpc_id = module.vpc.vpc_id
}
