# ==============================================================================
# S3 버킷 (미디어 파일 저장)
# ==============================================================================

# S3 버킷 생성
resource "aws_s3_bucket" "media" {
  bucket = "${local.project_name_normalized}-media-bucket"

  # demo/dev: terraform destroy 시 파일 포함 삭제 가능
  # prod: 보호 (파일 먼저 삭제해야 버킷 삭제 가능)
  force_destroy = var.environment == "prod" ? false : true

  tags = {
    Name = "${local.project_name_normalized}-media-bucket"
  }
}

# 퍼블릭 액세스 차단 (보안)
resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CORS 설정 (프론트엔드에서 Presigned URL 업로드 시 필요)
resource "aws_s3_bucket_cors_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"]  # 프로덕션에서는 실제 도메인으로 변경 권장
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# demo/dev 환경: 30일 지난 파일 자동 삭제 (비용 절감)
resource "aws_s3_bucket_lifecycle_configuration" "media_non_prod" {
  count  = var.environment == "prod" ? 0 : 1
  bucket = aws_s3_bucket.media.id

  rule {
    id     = "delete-old-files"
    status = "Enabled"

    filter {}  # 모든 객체에 적용

    expiration {
      days = 30
    }
  }
}
