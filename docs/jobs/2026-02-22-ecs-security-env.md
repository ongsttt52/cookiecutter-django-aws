# ECS Task Definition 보안 환경변수 추가

> **작업일**: 2026-02-22
> **브랜치**: `dev`
> **커밋**: `8ec27af` — fix: Add SECRET_KEY and ALLOWED_HOSTS to ECS Task Definition
> **관련 리뷰**: [PR#2 코드 리뷰](../reviews/2026-02-21-pr2-frontend-template.md) — 심각도 높음 #3

---

## 배경

PR#2 코드 리뷰에서 ECS Task Definition에 `SECRET_KEY`, `ALLOWED_HOSTS` 환경변수가 누락되어 프로덕션에서 insecure 기본값으로 동작하는 문제가 지적됨.

- `SECRET_KEY`: `django-insecure-change-this-in-production` 기본값 그대로 사용 → 세션/CSRF 토큰 위조 가능
- `ALLOWED_HOSTS`: `['*']` 기본값 그대로 사용 → Host Header Injection 가능

## 변경 내용

### 1. `terraform/variables.tf` — django_secret_key 변수 추가

```hcl
variable "django_secret_key" {
  description = "Django SECRET_KEY"
  type        = string
  sensitive   = true
  default     = "django-insecure-change-this-in-production"
}
```

- `sensitive = true`로 설정하여 `terraform plan/apply` 출력에서 마스킹

### 2. `terraform/ecs.tf` — Backend 환경변수 2개 추가

```hcl
{ name = "ALLOWED_HOSTS", value = aws_lb.main.dns_name },
{ name = "SECRET_KEY",    value = var.django_secret_key }
```

- `ALLOWED_HOSTS`: ALB DNS 이름을 자동 주입하여 와일드카드 대신 실제 도메인만 허용
- `SECRET_KEY`: Terraform 변수로 받아 ECS에 주입

### 3. `.github/workflows/create-infra.yml` — terraform plan에 변수 전달

```yaml
-var="django_secret_key=${{ secrets.DJANGO_SECRET_KEY }}"
```

### 4. `.github/workflows/destroy.yml` — terraform destroy에 변수 전달

```yaml
-var="django_secret_key=${{ secrets.DJANGO_SECRET_KEY }}"
```

### 5. `Makefile` — DJANGO_SECRET_KEY 자동 생성

`make init`과 `make setup-secrets` 모두에 추가:

```makefile
DJANGO_SECRET_KEY=$$(python3 -c "import secrets; print(secrets.token_urlsafe(50))") && \
gh secret set DJANGO_SECRET_KEY --body "$$DJANGO_SECRET_KEY" && \
echo "  ✓ DJANGO_SECRET_KEY auto-generated"
```

- 사용자가 직접 키를 생성할 필요 없이 자동으로 랜덤 키 생성 후 GitHub Secrets에 등록

## 변경 파일 목록

| 파일 | 변경 유형 |
|------|-----------|
| `terraform/variables.tf` | 변수 추가 |
| `terraform/ecs.tf` | 환경변수 추가 |
| `.github/workflows/create-infra.yml` | `-var` 인자 추가 |
| `.github/workflows/destroy.yml` | `-var` 인자 추가 |
| `Makefile` | 시크릿 자동 생성 로직 추가 |

## 흐름

```
make init (또는 make setup-secrets)
  └── python3으로 랜덤 SECRET_KEY 생성
  └── gh secret set DJANGO_SECRET_KEY 등록

GitHub Actions: Create AWS Infrastructure
  └── secrets.DJANGO_SECRET_KEY → terraform -var
  └── Terraform → ECS Task Definition environment
  └── Django가 SECRET_KEY 환경변수 읽음
```

## 남은 사항

- `DATABASE_URL`도 평문 환경변수로 노출 중 (리뷰 심각도 높음 #2). Secrets Manager 적용 시 `SECRET_KEY`도 함께 마이그레이션하는 것이 이상적
