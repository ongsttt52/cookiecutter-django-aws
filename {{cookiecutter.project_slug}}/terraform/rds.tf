{% if cookiecutter.aws_deployment == "ecs-fargate" %}
# ==============================================================================
# RDS PostgreSQL 데이터베이스
# ==============================================================================

# RDS 서브넷 그룹 (Private 서브넷에 배치)
resource "aws_db_subnet_group" "main" {
  name       = "${local.project_name_normalized}-db-subnet-${var.environment}"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${local.project_name_normalized}-db-subnet-${var.environment}"
  }
}

# PostgreSQL 데이터베이스
resource "aws_db_instance" "main" {
  identifier = "${local.project_name_normalized}-db-${var.environment}"

  # 엔진 설정
  engine         = "postgres"
  engine_version = "16"
  instance_class = local.db_instance_class  # demo/dev: db.t3.micro, prod: db.t3.small

  # 용량 설정
  allocated_storage     = 20
  max_allocated_storage = 100  # 자동 확장 (최대 100GB)

  # 데이터베이스 정보
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # 네트워크 설정
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false  # 외부 접근 차단

  # 백업 설정
  backup_retention_period = var.environment == "prod" ? 7 : 1  # demo/dev: 1일, prod: 7일
  backup_window           = "03:00-04:00"                      # UTC 기준
  maintenance_window      = "mon:04:00-mon:05:00"

  # 삭제 보호
  skip_final_snapshot       = var.environment == "prod" ? false : true  # demo/dev: 스냅샷 생략, prod: 생성
  final_snapshot_identifier = var.environment == "prod" ? "${local.project_name_normalized}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null
  deletion_protection       = var.environment == "prod" ? true : false  # prod: 삭제 방지

  tags = {
    Name = "${local.project_name_normalized}-db-${var.environment}"
  }
}
{% endif %}
