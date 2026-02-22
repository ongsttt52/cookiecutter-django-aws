# ==============================================================================
# 보안 그룹 (방화벽 규칙)
# ==============================================================================

# ALB 보안 그룹 (외부에서 HTTP/HTTPS 접근 가능)
resource "aws_security_group" "alb" {
  name        = "${local.project_name_normalized}-alb-sg-${var.environment}"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  # HTTP 접근 허용
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS 접근 허용
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 아웃바운드 모두 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.project_name_normalized}-alb-sg-${var.environment}"
  }
}

# ECS 보안 그룹 (ALB에서만 접근 가능)
resource "aws_security_group" "ecs" {
  name        = "${local.project_name_normalized}-ecs-sg-${var.environment}"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  # ALB에서 Django 포트로 접근 허용
  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

{% if cookiecutter.use_frontend == "yes" %}
  # ALB에서 Next.js 포트로 접근 허용
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
{% endif %}

  # 아웃바운드 모두 허용 (외부 API 호출, S3 접근 등)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.project_name_normalized}-ecs-sg-${var.environment}"
  }
}

# RDS 보안 그룹 (ECS에서만 접근 가능)
resource "aws_security_group" "rds" {
  name        = "${local.project_name_normalized}-rds-sg-${var.environment}"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = aws_vpc.main.id

  # ECS에서 PostgreSQL 포트로 접근 허용
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = {
    Name = "${local.project_name_normalized}-rds-sg-${var.environment}"
  }
}

# Redis 보안 그룹 (ECS에서만 접근 가능)
resource "aws_security_group" "redis" {
  name        = "${local.project_name_normalized}-redis-sg-${var.environment}"
  description = "Security group for ElastiCache Redis"
  vpc_id      = aws_vpc.main.id

  # ECS에서 Redis 포트로 접근 허용
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = {
    Name = "${local.project_name_normalized}-redis-sg-${var.environment}"
  }
}
