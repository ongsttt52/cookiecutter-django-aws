# Phase 9A: S3 Presigned URL API + Superuser 자동 생성

> **작성일**: 2026-02-28
> **상태**: 계획 완료, 구현 대기
> **선행 작업**: Phase 8 완료 (EC2 All-in-One + deploy.sh)
> **브랜치**: `feat/phase9a-s3-presigned-superuser` (예정)

---

## 배경

Phase 1~8까지 완료되어 템플릿은 프로덕션 사용 가능 상태이지만:

1. **S3 버킷은 Terraform으로 생성되면서 실제 파일 업로드/다운로드 API가 없음** — 외주 프로젝트에서 바로 활용 불가
2. **배포 직후 Django Admin 접근하려면 수동 superuser 생성 필요** — DX 저하

두 작업은 서로 독립적이므로 순서 무관하게 구현 가능.

---

## 작업 1: S3 Presigned URL API

### 1-1. 신규 파일: `backend/apps/files/` 앱 생성

| 파일 | 내용 |
|------|------|
| `__init__.py` | 빈 파일 |
| `apps.py` | `FilesConfig` — 기존 core 앱 패턴 동일 |
| `urls.py` | `upload/`, `download/` 2개 경로 |
| `views.py` | 핵심 — Presigned URL 생성 로직 |

### 1-2. `views.py` 설계

**엔드포인트:**

| Method | Path | 설명 | 인증 |
|--------|------|------|------|
| POST | `/api/files/upload/` | Upload Presigned URL 생성 | JWT (settings 기본값) |
| POST | `/api/files/download/` | Download Presigned URL 생성 | JWT (settings 기본값) |

**S3 클라이언트 전략:**
- `AWS_ACCESS_KEY_ID`가 `None` (ECS, IAM Role) → credentials 없이 boto3 client 생성
- 값이 있으면 (로컬/EC2) → 명시적 credentials 전달
- `settings.py`의 기존 패턴 (`default=None`) 그대로 활용

```python
from botocore.config import Config as BotoConfig

def get_s3_client():
    kwargs = {
        "region_name": settings.AWS_S3_REGION_NAME,
        "config": BotoConfig(signature_version=settings.AWS_S3_SIGNATURE_VERSION),
    }
    if settings.AWS_ACCESS_KEY_ID and settings.AWS_SECRET_ACCESS_KEY:
        kwargs["aws_access_key_id"] = settings.AWS_ACCESS_KEY_ID
        kwargs["aws_secret_access_key"] = settings.AWS_SECRET_ACCESS_KEY
    return boto3.client("s3", **kwargs)
```

**파일 키 구조:** `uploads/{user_id}/{uuid8}_{filename}`
- 유저별 네임스페이스 분리
- UUID prefix로 파일명 충돌 방지

**보안:**
- 허용 확장자 화이트리스트: jpg, jpeg, png, gif, webp, svg, pdf, doc(x), xls(x), ppt(x), mp4, mov, avi, webm, mp3, wav, zip, tar, gz, csv, json, txt
- Download 시 `file_key` prefix로 소유권 검증 (`uploads/{user_id}/`)
- 에러 시 내부 정보 노출 차단 — `logger.error()` + 제네릭 메시지 (기존 health check 패턴)

**Swagger 문서화:**
- `@extend_schema` 데코레이터 + request/response serializer 클래스
- `tags=["files"]`로 Swagger UI에서 그룹핑

**Upload 뷰 핵심 흐름:**
```
1. request.data에서 filename, content_type 추출
2. 확장자 화이트리스트 검증
3. S3 키 생성: uploads/{user.id}/{uuid8}_{filename}
4. s3_client.generate_presigned_url("put_object", ...) 호출
5. { upload_url, file_key, expires_in } 반환
```

**Download 뷰 핵심 흐름:**
```
1. request.data에서 file_key 추출
2. file_key가 uploads/{user.id}/ 로 시작하는지 소유권 검증
3. s3_client.generate_presigned_url("get_object", ...) 호출
4. { download_url, expires_in } 반환
```

### 1-3. 기존 파일 수정

| 파일 | 위치 | 변경 내용 |
|------|------|-----------|
| `config/settings.py` | `INSTALLED_APPS` (line ~41) | `'apps.files'` 추가 |
| `config/settings.py` | AWS S3 섹션 (line ~156) | `AWS_MAX_FILE_SIZE = 100 * 1024 * 1024` 추가 |
| `config/settings.py` | `SPECTACULAR_SETTINGS` (line ~192) | `'TAGS': [{'name': 'files', 'description': 'S3 Presigned URL 파일 업로드/다운로드'}]` 추가 |
| `config/urls.py` | urlpatterns (line ~7) | `path("api/files/", include("apps.files.urls"))` 추가 |

**참고**: 라인 번호는 구현 시점의 실제 파일과 다를 수 있음. 코드 패턴으로 위치 찾을 것.

---

## 작업 2: Superuser 자동 생성

### 2-1. `backend/entrypoint.sh` 수정

현재 entrypoint.sh (11줄):
```bash
#!/bin/bash
set -e
echo "Running database migrations..."
uv run python manage.py migrate --noinput
echo "Collecting static files..."
uv run python manage.py collectstatic --noinput
echo "Starting server..."
exec "$@"
```

**migrate 후, collectstatic 전에 superuser 생성 로직 추가:**

```bash
# Superuser 자동 생성 (환경변수가 설정된 경우에만)
if [ -n "$DJANGO_SUPERUSER_EMAIL" ] && [ -n "$DJANGO_SUPERUSER_PASSWORD" ]; then
    echo "Creating superuser..."
    uv run python manage.py createsuperuser \
        --noinput \
        --email "$DJANGO_SUPERUSER_EMAIL" \
        --username "${DJANGO_SUPERUSER_USERNAME:-admin}" \
        2>/dev/null || echo "Superuser already exists, skipping."
fi
```

**설계 근거:**
- Django 3.0+ 공식 기능: `--noinput`과 함께 `DJANGO_SUPERUSER_PASSWORD` 환경변수 자동 인식
- `2>/dev/null || echo`: 이미 존재할 때 에러 숨기고 스킵 메시지 (멱등성)
- 환경변수 없으면 아무것도 안 함 → 로컬 개발 시 기존 동작 영향 없음

### 2-2. 환경변수 전파

#### `.env.example` 추가 (주석 처리 상태)
```bash
# Django Superuser (자동 생성 - 선택사항)
# 설정 시 컨테이너 시작 시 자동으로 superuser 생성
# DJANGO_SUPERUSER_EMAIL=admin@example.com
# DJANGO_SUPERUSER_PASSWORD=your-secure-password
# DJANGO_SUPERUSER_USERNAME=admin
```

#### `terraform/variables.tf` 추가
```hcl
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
```

#### `terraform/ecs.tf` — Backend container environment 배열에 추가
```hcl
{ name = "DJANGO_SUPERUSER_EMAIL",    value = var.django_superuser_email },
{ name = "DJANGO_SUPERUSER_PASSWORD", value = var.django_superuser_password },
{ name = "DJANGO_SUPERUSER_USERNAME", value = "admin" },
```
위치: `environment = [` 배열 내, 기존 `CORS_ALLOWED_ORIGINS` 뒤

#### `terraform/user-data.sh` — EC2 `.env` 파일에 추가
```bash
DJANGO_SUPERUSER_EMAIL=${django_superuser_email}
DJANGO_SUPERUSER_PASSWORD=${django_superuser_password}
DJANGO_SUPERUSER_USERNAME=admin
```
위치: `ENVEOF` 직전

#### `.github/workflows/create-infra.yml` — terraform plan `-var` 추가
```yaml
-var="django_superuser_email=admin@example.com" \
-var="django_superuser_password=${{ secrets.DJANGO_SUPERUSER_PASSWORD }}" \
```
위치: 기존 `-var="django_secret_key=..."` 뒤

#### `.github/workflows/destroy.yml` — terraform destroy `-var` 추가
동일하게 추가.

#### `Makefile` — `make init`과 `make setup-secrets` 양쪽에 추가
```makefile
read -sp "Django Superuser Password (default: admin1234): " SU_PASS; \
SU_PASS=$${SU_PASS:-admin1234}; \
echo ""; \
gh secret set DJANGO_SUPERUSER_PASSWORD --body "$$SU_PASS" && \
echo "  ✓ DJANGO_SUPERUSER_PASSWORD set"
```
위치: `DJANGO_SECRET_KEY` auto-generated 직후

---

## 전체 변경 파일 목록

### 신규 (4개)
1. `{{cookiecutter.project_slug}}/backend/apps/files/__init__.py`
2. `{{cookiecutter.project_slug}}/backend/apps/files/apps.py`
3. `{{cookiecutter.project_slug}}/backend/apps/files/views.py`
4. `{{cookiecutter.project_slug}}/backend/apps/files/urls.py`

### 수정 (10개)
5. `{{cookiecutter.project_slug}}/backend/config/settings.py` — INSTALLED_APPS, AWS_MAX_FILE_SIZE, SPECTACULAR_SETTINGS
6. `{{cookiecutter.project_slug}}/backend/config/urls.py` — files URL 추가
7. `{{cookiecutter.project_slug}}/backend/entrypoint.sh` — superuser 자동 생성
8. `{{cookiecutter.project_slug}}/.env.example` — superuser 환경변수
9. `{{cookiecutter.project_slug}}/terraform/variables.tf` — superuser 변수 2개
10. `{{cookiecutter.project_slug}}/terraform/ecs.tf` — superuser 환경변수 3개
11. `{{cookiecutter.project_slug}}/terraform/user-data.sh` — superuser 환경변수
12. `{{cookiecutter.project_slug}}/.github/workflows/create-infra.yml` — `-var` 추가
13. `{{cookiecutter.project_slug}}/.github/workflows/destroy.yml` — `-var` 추가
14. `{{cookiecutter.project_slug}}/Makefile` — superuser secret 설정

### 문서 (1개)
15. `PROGRESS.md` — Phase 9A 완료 기록

---

## 검증 계획

### 1. Cookiecutter 렌더링 테스트
- 4개 케이스 (ECS+풀, ECS+최소, EC2+풀, EC2+최소) 렌더링
- `{{cookiecutter.*}}` / `{% %}` 잔여 확인
- `apps/files/` 디렉토리 존재 확인

### 2. Terraform validate
- 4개 케이스 모두 `terraform init -backend=false && terraform validate` PASS 확인

### 3. Docker Compose 로컬 테스트
- `/api/docs/` 접속 → files 엔드포인트 Swagger에 표시 확인
- `/api/files/upload/` 인증 없이 → 401 확인
- `.env`에 superuser 환경변수 설정 → 컨테이너 재시작 → `/api/admin/` 로그인 확인
- 컨테이너 재시작 → "Superuser already exists, skipping." 멱등성 확인

---

## 구현 시 주의사항

1. **라인 번호 의존 금지**: 코드 변경이 있을 수 있으므로, 수정 위치는 코드 패턴(예: `INSTALLED_APPS`, `environment = [`)으로 찾을 것
2. **files 앱은 모델 없음**: migration 불필요
3. **botocore import**: `from botocore.config import Config as BotoConfig` 필요 (boto3에 이미 포함)
4. **`DEFAULT_PERMISSION_CLASSES`가 `IsAuthenticated`**: files 뷰에 별도 permission 지정 불필요
5. **cookiecutter 템플릿 변수**: files 앱은 순수 Python이라 `{{cookiecutter.*}}` 사용 없음. Terraform/workflow 수정 시만 주의
