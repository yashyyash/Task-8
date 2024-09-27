# Provider
provider "aws" {
  region = "us-east-1"  # Update with your preferred AWS region
}

# ECS Cluster
resource "aws_ecs_cluster" "medusa_cluster" {
  name = "medusa-cluster"
}

# VPC Configuration
resource "aws_vpc" "medusa_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "medusa_subnet" {
  vpc_id     = aws_vpc.medusa_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

# Security Group for ECS Service
resource "aws_security_group" "medusa_sg" {
  vpc_id = aws_vpc.medusa_vpc.id

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
}

# ECR Repository for Medusa
resource "aws_ecr_repository" "medusa_repo" {
  name = "medusa-repo"
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "yash-ecs-task-8"
  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "ecs-tasks.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  EOF
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "medusa_task" {
  family                   = "medusa-task"
  container_definitions    = <<DEFINITION
  [
    {
      "name": "medusa-container",
      "image": "${aws_ecr_repository.medusa_repo.repository_url}:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 80,
          "hostPort": 80
        }
      ]
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
}

# ECS Service using Fargate Spot
resource "aws_ecs_service" "medusa_service" {
  name            = "medusa-service"
  cluster         = aws_ecs_cluster.medusa_cluster.id
  task_definition = aws_ecs_task_definition.medusa_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  platform_version = "1.4.0"

  network_configuration {
    subnets         = [aws_subnet.medusa_subnet.id]
    security_groups = [aws_security_group.medusa_sg.id]
  }

  capacity_provider_strategies {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }
}

# Load Balancer (optional if exposing the app publicly)
resource "aws_lb" "medusa_alb" {
  name               = "medusa-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.medusa_sg.id]
  subnets            = [aws_subnet.medusa_subnet.id]
}

resource "aws_lb_target_group" "medusa_tg" {
  name     = "medusa-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.medusa_vpc.id
  target_type = "ip"
}

resource "aws_lb_listener" "medusa_listener" {
  load_balancer_arn = aws_lb.medusa_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.medusa_tg.arn
  }
}
