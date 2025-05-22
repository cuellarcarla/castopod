provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
}

resource "aws_security_group" "ecs_sg" {
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 9000
    to_port     = 9000
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

resource "aws_db_instance" "castopod_db" {
  allocated_storage    = 20
  engine               = "mariadb"
  engine_version       = "10.5"
  instance_class       = "db.t3.micro"
  identifier           = var.db_name
  username             = var.db_username
  password             = var.db_password
  publicly_accessible  = true
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.ecs_sg.id]
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "castopod-db-subnet-group"
  subnet_ids = [aws_subnet.public.id]
}

resource "aws_ecs_cluster" "main" {
  name = "castopod-cluster"
}

resource "aws_ecs_task_definition" "castopod" {
  family                   = "castopod-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = var.labrole_arn

  container_definitions = jsonencode([
    {
      name      = "castopod"
      image     = "castopod/castopod:latest"
      essential = true
      portMappings = [
        {
          containerPort = 9000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "DB_HOST", value = aws_db_instance.castopod_db.address },
        { name = "DB_PORT", value = "3306" },
        { name = "DB_USER", value = var.db_username },
        { name = "DB_PASSWORD", value = var.db_password },
        { name = "DB_NAME", value = var.db_name },
        { name = "CP_BASEURL", value = "http://${aws_lb.castopod_lb.dns_name}:9000" },
        { name = "CP_ANALYTICS_SALT", value = var.cp_analytics_salt }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/castopod"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_lb" "castopod_lb" {
  name               = "castopod-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.public.id]
  security_groups    = [aws_security_group.ecs_sg.id]
}

resource "aws_lb_target_group" "castopod_tg" {
  name        = "castopod-tg"
  port        = 9000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "castopod_listener" {
  load_balancer_arn = aws_lb.castopod_lb.arn
  port              = "9000"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.castopod_tg.arn
  }
}

resource "aws_ecs_service" "castopod" {
  name            = "castopod-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.castopod.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = [aws_subnet.public.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.castopod_tg.arn
    container_name   = "castopod"
    container_port   = 9000
  }
  depends_on = [aws_lb_listener.castopod_listener]
}
