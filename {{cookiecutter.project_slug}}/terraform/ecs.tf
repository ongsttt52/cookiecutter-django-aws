# ==============================================================================
# ECS (컨테이너 실행 환경)
# ==============================================================================

# ECS 클러스터
resource "aws_ecs_cluster" "main" {
  name = "${replace(var.project_name, "_", "-")}-cluster-${var.environment}"

  tags = {
    Name = "${replace(var.project_name, "_", "-")}-cluster-${var.environment}"
  }
}

# ==============================================================================
# Backend (Django)
# ==============================================================================

# Backend CloudWatch 로그 그룹
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${replace(var.project_name, "_", "-")}-backend-${var.environment}"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name = "${replace(var.project_name, "_", "-")}-backend-logs-${var.environment}"
  }
}

# Backend Task Definition
resource "aws_ecs_task_definition" "backend" {
  family                   = "${replace(var.project_name, "_", "-")}-backend-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.environment == "prod" ? "512" : "256"
  memory                   = var.environment == "prod" ? "1024" : "512"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "django"
      image = "${aws_ecr_repository.backend.repository_url}:latest"

      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "DATABASE_URL"
          value = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.main.endpoint}/${var.db_name}"
        },
        {
          name  = "REDIS_URL"
          value = "redis://${aws_elasticache_cluster.main.cache_nodes[0].address}:6379/0"
        },
        {
          name  = "AWS_STORAGE_BUCKET_NAME"
          value = aws_s3_bucket.media.bucket
        },
        {
          name  = "AWS_DEFAULT_REGION"
          value = var.aws_region
        },
        {
          name  = "ALLOWED_HOSTS"
          value = aws_lb.main.dns_name
        },
        {
          name  = "SECRET_KEY"
          value = var.django_secret_key
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "django"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "${replace(var.project_name, "_", "-")}-backend-task-${var.environment}"
  }
}

# Backend Service
resource "aws_ecs_service" "backend" {
  name            = "${replace(var.project_name, "_", "-")}-backend-service-${var.environment}"
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
    container_name   = "django"
    container_port   = 8000
  }

  tags = {
    Name = "${replace(var.project_name, "_", "-")}-backend-service-${var.environment}"
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
  name              = "/ecs/${replace(var.project_name, "_", "-")}-frontend-${var.environment}"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name = "${replace(var.project_name, "_", "-")}-frontend-logs-${var.environment}"
  }
}

# Frontend Task Definition
resource "aws_ecs_task_definition" "frontend" {
  family                   = "${replace(var.project_name, "_", "-")}-frontend-${var.environment}"
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
        },
        {
          name  = "NEXT_PUBLIC_API_URL"
          value = "http://${aws_lb.main.dns_name}"
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
    Name = "${replace(var.project_name, "_", "-")}-frontend-task-${var.environment}"
  }
}

# Frontend Service
resource "aws_ecs_service" "frontend" {
  name            = "${replace(var.project_name, "_", "-")}-frontend-service-${var.environment}"
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
    Name = "${replace(var.project_name, "_", "-")}-frontend-service-${var.environment}"
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}
{% endif %}
