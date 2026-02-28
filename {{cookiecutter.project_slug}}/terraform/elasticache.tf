{% if cookiecutter.aws_deployment == "ecs-fargate" %}
# ==============================================================================
# ElastiCache Redis (캐시 + Celery 브로커)
# ==============================================================================

# Redis 서브넷 그룹 (Private 서브넷에 배치)
resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.project_name_normalized}-redis-subnet-${var.environment}"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${local.project_name_normalized}-redis-subnet-${var.environment}"
  }
}

# Redis 클러스터
resource "aws_elasticache_cluster" "main" {
  cluster_id = "${local.project_name_normalized}-redis-${var.environment}"

  # 엔진 설정
  engine         = "redis"
  engine_version = "7.0"
  node_type      = local.redis_node_type  # demo/dev: cache.t3.micro, prod: cache.t3.small

  # 노드 개수 (단일 노드)
  num_cache_nodes = 1

  # 포트 설정
  port = 6379

  # 네트워크 설정
  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  # 파라미터 그룹 (기본값 사용)
  parameter_group_name = "default.redis7"

  tags = {
    Name = "${local.project_name_normalized}-redis-${var.environment}"
  }
}
{% endif %}
