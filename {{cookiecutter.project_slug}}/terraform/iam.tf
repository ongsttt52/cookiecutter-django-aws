{% if cookiecutter.aws_deployment == "ecs-fargate" %}
# ==============================================================================
# IAM 역할 및 정책 (ECS 권한 설정)
# ==============================================================================

# ECS Task Execution Role (ECS가 ECR에서 이미지 가져오고 로그 쓰기 위한 권한)
resource "aws_iam_role" "ecs_execution_role" {
  name = "${local.project_name_normalized}-ecs-execution-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.project_name_normalized}-ecs-execution-role-${var.environment}"
  }
}

# ECS Task Execution Role에 AWS 기본 정책 연결
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Role (Django 앱이 S3에 접근하기 위한 권한)
resource "aws_iam_role" "ecs_task_role" {
  name = "${local.project_name_normalized}-ecs-task-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.project_name_normalized}-ecs-task-role-${var.environment}"
  }
}

# S3 접근 정책 (Presigned URL 생성 위한)
resource "aws_iam_role_policy" "ecs_task_s3_policy" {
  name = "${local.project_name_normalized}-ecs-s3-policy-${var.environment}"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.media.arn,
          "${aws_s3_bucket.media.arn}/*"
        ]
      }
    ]
  })
}
{% endif %}
