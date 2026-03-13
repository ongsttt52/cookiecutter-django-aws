{% if cookiecutter.aws_deployment == "ecs-fargate" %}
# ==============================================================================
# ECS (컨테이너 실행 환경)
# ==============================================================================

# ECS 클러스터
resource "aws_ecs_cluster" "main" {
  name = "${local.project_name_normalized}-cluster-${var.environment}"

  tags = {
    Name = "${local.project_name_normalized}-cluster-${var.environment}"
  }
}

# ==============================================================================
# Backend 환경변수 동적 조합
# ==============================================================================

locals {
  # 공통 환경변수 (모든 백엔드 스택에서 사용)
  common_env = [
    {
      name  = "ENVIRONMENT"
      value = var.environment
    },
    {
      name  = "AWS_STORAGE_BUCKET_NAME"
      value = aws_s3_bucket.media.bucket
    },
    {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    },
  ]

{% if cookiecutter.backend_stack == "django" %}
  # Django 전용 환경변수
  stack_env = [
    {
      name  = "DATABASE_URL"
      value = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.main.endpoint}/${var.db_name}"
    },
    {
      name  = "REDIS_URL"
      value = "redis://${aws_elasticache_cluster.main.cache_nodes[0].address}:6379/0"
    },
    {
      name  = "ALLOWED_HOSTS"
      value = "${aws_lb.main.dns_name},*"
    },
    {
      name  = "SECRET_KEY"
      value = var.app_secret_key
    },
    {
      name  = "CORS_ALLOWED_ORIGINS"
      value = "http://${aws_lb.main.dns_name}"
    },
    {
      name  = "DJANGO_SUPERUSER_EMAIL"
      value = var.django_superuser_email
    },
    {
      name  = "DJANGO_SUPERUSER_PASSWORD"
      value = var.django_superuser_password
    },
    {
      name  = "DJANGO_SUPERUSER_USERNAME"
      value = "admin"
    },
  ]
{% else %}
  stack_env = []
{% endif %}

  # 최종 환경변수: 공통 + 스택별 + 사용자 정의
  backend_env = concat(local.common_env, local.stack_env, var.app_env_vars)
}

# ==============================================================================
# Backend ({{cookiecutter.backend_stack}})
# ==============================================================================

# Backend CloudWatch 로그 그룹
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.project_name_normalized}-backend-${var.environment}"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name = "${local.project_name_normalized}-backend-logs-${var.environment}"
  }
}

# Backend Task Definition
resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.project_name_normalized}-backend-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.environment == "prod" ? "512" : "256"
  memory                   = var.environment == "prod" ? "1024" : "512"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "{{cookiecutter.backend_stack}}"
      image = "${aws_ecr_repository.backend.repository_url}:latest"

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = local.backend_env

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "{{cookiecutter.backend_stack}}"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "${local.project_name_normalized}-backend-task-${var.environment}"
  }
}

# Backend Service
resource "aws_ecs_service" "backend" {
  name            = "${local.project_name_normalized}-backend-service-${var.environment}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.environment == "prod" ? 2 : 1

  launch_type = "FARGATE"

  force_new_deployment  = true
  wait_for_steady_state = false

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "{{cookiecutter.backend_stack}}"
    container_port   = var.container_port
  }

  tags = {
    Name = "${local.project_name_normalized}-backend-service-${var.environment}"
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

{% if cookiecutter.use_frontend == "yes" %}
# ==============================================================================
# Frontend (Next.js)
# ==============================================================================

# Frontend CloudWatch 로그 그룹
resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${local.project_name_normalized}-frontend-${var.environment}"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name = "${local.project_name_normalized}-frontend-logs-${var.environment}"
  }
}

# Frontend Task Definition
resource "aws_ecs_task_definition" "frontend" {
  family                   = "${local.project_name_normalized}-frontend-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "next"
      image = "${aws_ecr_repository.frontend.repository_url}:latest"

      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.frontend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "next"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "${local.project_name_normalized}-frontend-task-${var.environment}"
  }
}

# Frontend Service
resource "aws_ecs_service" "frontend" {
  name            = "${local.project_name_normalized}-frontend-service-${var.environment}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1

  launch_type = "FARGATE"

  force_new_deployment  = true
  wait_for_steady_state = false

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "next"
    container_port   = 3000
  }

  tags = {
    Name = "${local.project_name_normalized}-frontend-service-${var.environment}"
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}
{% endif %}
{% endif %}
