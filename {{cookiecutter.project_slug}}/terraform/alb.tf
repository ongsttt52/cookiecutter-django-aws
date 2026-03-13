{% if cookiecutter.aws_deployment == "ecs-fargate" %}
# ==============================================================================
# Application Load Balancer (트래픽 분산)
# ==============================================================================

# ALB 생성
resource "aws_lb" "main" {
  name               = "${local.project_name_normalized}-alb-${var.environment}"
  internal           = false  # 외부 접근 가능
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "${local.project_name_normalized}-alb-${var.environment}"
  }
}

# Backend Target Group (백엔드 컨테이너로 트래픽 전달)
resource "aws_lb_target_group" "backend" {
  name        = "${local.project_name_normalized}-be-tg-${var.environment}"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"  # Fargate 또는 awsvpc 네트워크 모드 사용 시 ip

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${local.project_name_normalized}-be-tg-${var.environment}"
  }
}

{% if cookiecutter.use_frontend == "yes" %}
# Frontend Target Group (Next.js 컨테이너로 트래픽 전달)
resource "aws_lb_target_group" "frontend" {
  name        = "${local.project_name_normalized}-fe-tg-${var.environment}"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${local.project_name_normalized}-fe-tg-${var.environment}"
  }
}
{% endif %}

# Listener (HTTP 트래픽을 Target Group으로 전달)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

{% if cookiecutter.use_frontend == "yes" %}
  # 기본 액션: Frontend로 전달
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
{% else %}
  # Backend만 사용 시: Backend로 전달
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
{% endif %}
}

{% if cookiecutter.use_frontend == "yes" %}
# /api/* 경로는 Backend Target Group으로 전달
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}
{% endif %}
{% endif %}
