# ==============================================================================
# ECR (Docker 이미지 저장소)
# ==============================================================================

# Backend ECR 리포지토리
resource "aws_ecr_repository" "backend" {
  name                 = "${replace(var.project_name, "_", "-")}-backend-${var.environment}"
  image_tag_mutability = "MUTABLE"  # 같은 태그 덮어쓰기 가능
  force_delete         = true       # terraform destroy 시 이미지 포함 삭제

  # 이미지 스캔 (보안 취약점 검사)
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${replace(var.project_name, "_", "-")}-backend-ecr-${var.environment}"
  }
}

# Backend ECR 라이프사이클 정책 (오래된 이미지 자동 삭제)
resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "최근 10개 이미지만 유지"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

{% if cookiecutter.use_frontend == "yes" %}
# Frontend ECR 리포지토리
resource "aws_ecr_repository" "frontend" {
  name                 = "${replace(var.project_name, "_", "-")}-frontend-${var.environment}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${replace(var.project_name, "_", "-")}-frontend-ecr-${var.environment}"
  }
}

# Frontend ECR 라이프사이클 정책
resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "최근 10개 이미지만 유지"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
{% endif %}
