# ==============================================================================
# 출력값 (terraform apply 후 표시)
# ==============================================================================

# 애플리케이션 URL
output "app_url" {
  description = "애플리케이션 접속 URL"
  value       = "http://${aws_lb.main.dns_name}"
}

# Backend ECR 리포지토리 URL
output "ecr_backend_url" {
  description = "Backend Docker 이미지 푸시할 ECR 주소"
  value       = aws_ecr_repository.backend.repository_url
}

{% if cookiecutter.use_frontend == "yes" %}
# Frontend ECR 리포지토리 URL
output "ecr_frontend_url" {
  description = "Frontend Docker 이미지 푸시할 ECR 주소"
  value       = aws_ecr_repository.frontend.repository_url
}
{% endif %}

# S3 버킷 이름
output "s3_bucket_name" {
  description = "미디어 파일 저장 S3 버킷"
  value       = aws_s3_bucket.media.bucket
}

# RDS 엔드포인트
output "rds_endpoint" {
  description = "PostgreSQL 데이터베이스 엔드포인트"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

# Redis 엔드포인트
output "redis_endpoint" {
  description = "Redis 엔드포인트"
  value       = "${aws_elasticache_cluster.main.cache_nodes[0].address}:6379"
  sensitive   = true
}

# ECS 클러스터 이름
output "ecs_cluster_name" {
  description = "ECS 클러스터 이름"
  value       = aws_ecs_cluster.main.name
}

# Backend ECS 서비스 이름
output "ecs_backend_service_name" {
  description = "Backend ECS 서비스 이름"
  value       = aws_ecs_service.backend.name
}

{% if cookiecutter.use_frontend == "yes" %}
# Frontend ECS 서비스 이름
output "ecs_frontend_service_name" {
  description = "Frontend ECS 서비스 이름"
  value       = aws_ecs_service.frontend.name
}
{% endif %}

# 리전 정보
output "aws_region" {
  description = "AWS 리전"
  value       = var.aws_region
}
