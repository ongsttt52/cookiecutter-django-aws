# ==============================================================================
# 입력 변수 정의
# ==============================================================================

# 프로젝트 기본 정보
variable "project_name" {
  description = "프로젝트 이름 (리소스 이름에 사용)"
  type        = string
  default     = "{{cookiecutter.project_slug}}"

  validation {
    condition     = length(var.project_name) <= 18
    error_message = "project_name must be 18 characters or less to avoid AWS resource name limits (ALB/TG 32-char limit)."
  }
}

variable "environment" {
  description = "환경 (dev=개발용, demo=클라이언트 데모, prod=프로덕션)"
  type        = string
  default     = "demo"
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "{{cookiecutter.aws_region}}"
}

# 데이터베이스 설정
variable "db_username" {
  description = "PostgreSQL 사용자명"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "PostgreSQL 비밀번호"
  type        = string
  sensitive   = true
  default     = "change-this-password"  # terraform apply -var="db_password=실제비밀번호" 로 덮어쓰기
}

variable "django_secret_key" {
  description = "Django SECRET_KEY"
  type        = string
  sensitive   = true
  default     = "django-insecure-change-this-in-production"
}

variable "db_name" {
  description = "데이터베이스 이름"
  type        = string
  default     = "{{cookiecutter.project_slug}}"
}

variable "django_superuser_email" {
  description = "Django superuser email (auto-created on first deploy)"
  type        = string
  default     = "admin@example.com"
}

variable "django_superuser_password" {
  description = "Django superuser password"
  type        = string
  sensitive   = true
  default     = ""
}

{% if cookiecutter.aws_deployment == "ec2-all-in-one" %}
# EC2 SSH Public Key
variable "ec2_public_key" {
  description = "SSH public key for EC2 access"
  type        = string
}
{% endif %}

# 인스턴스 크기 (환경별 자동 선택)
locals {
  # 프로젝트 이름 정규화 (언더스코어를 하이픈으로 변경)
  project_name_normalized = replace(var.project_name, "_", "-")

{% if cookiecutter.aws_deployment == "ecs-fargate" %}
  # dev/demo: 작고 저렴 (빠른 테스트), prod: 크고 안정적
  db_instance_class = var.environment == "prod" ? "db.t3.small" : "db.t3.micro"
  redis_node_type   = var.environment == "prod" ? "cache.t3.small" : "cache.t3.micro"
  ecs_instance_type = var.environment == "prod" ? "t3.medium" : "t3.small"
{% endif %}
{% if cookiecutter.aws_deployment == "ec2-all-in-one" %}
  # EC2 instance type: demo/dev=t3.small (~$15/月), prod=t3.medium
  ec2_instance_type = var.environment == "prod" ? "t3.medium" : "t3.small"
{% endif %}

  # 공통 태그
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
