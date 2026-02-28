# ==============================================================================
# 출력값 (terraform apply 후 표시)
# ==============================================================================

{% if cookiecutter.aws_deployment == "ecs-fargate" %}
# 애플리케이션 URL (ALB)
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
{% endif %}

{% if cookiecutter.aws_deployment == "ec2-all-in-one" %}
# 애플리케이션 URL (Elastic IP)
output "app_url" {
  description = "애플리케이션 접속 URL"
  value       = "http://${aws_eip.ec2.public_ip}"
}

# EC2 Public IP
output "ec2_public_ip" {
  description = "EC2 인스턴스 Public IP"
  value       = aws_eip.ec2.public_ip
}

# SSH 접속 명령어
output "ssh_command" {
  description = "EC2 SSH 접속 명령어"
  value       = "ssh -i ~/.ssh/${local.project_name_normalized}-ec2-key ec2-user@${aws_eip.ec2.public_ip}"
}
{% endif %}

# S3 버킷 이름 (공통)
output "s3_bucket_name" {
  description = "미디어 파일 저장 S3 버킷"
  value       = aws_s3_bucket.media.bucket
}

# 리전 정보 (공통)
output "aws_region" {
  description = "AWS 리전"
  value       = var.aws_region
}
