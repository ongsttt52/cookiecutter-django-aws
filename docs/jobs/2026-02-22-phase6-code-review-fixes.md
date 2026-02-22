# Phase 6: 코드 리뷰 지적사항 수정

> **작업일**: 2026-02-22
> **브랜치**: `dev`
> **관련 리뷰**:
> - [PR#1 코드 리뷰](../reviews/2026-02-21-pr1-backend-config.md)
> - [PR#2 코드 리뷰](../reviews/2026-02-21-pr2-frontend-template.md)

---

## 배경

PR#1(backend-config), PR#2(frontend-template) 코드 리뷰에서 보안/아키텍처/코드 품질 이슈가 발견됨. SECRET_KEY/ALLOWED_HOSTS ECS 주입은 별도 작업으로 선행 완료(`b991c4f`, `42f38f6`). 이 작업에서 나머지 심각도 높음 3건 + 중간 7건을 수정함.

---

## 커밋 내역

| 커밋 | ID | 내용 |
|------|-----|------|
| `c41a427` | H1 | `_copy_without_render`에서 `frontend/src/**` 제거 |
| `7dbb1d5` | H2 | Health check 에러 응답에서 인프라 정보 노출 차단 |
| `df1b830` | H3 | `NEXT_PUBLIC_API_URL` 빌드타임/런타임 문제 해결 |
| `24c6380` | M7 | ECS Backend에 `CORS_ALLOWED_ORIGINS` 환경변수 추가 |
| `49ee99d` | M1, M2 | Dockerfile `--platform` 추가 + 중복 COPY 제거 |
| `c2cd318` | M6 | `settings.py` import 위치 PEP 8 준수 |
| `9b2d1f8` | M3 | `project_name` 18자 이하 validation 추가 |
| `900262e` | M5 | Terraform 인라인 `replace()` → `local.project_name_normalized` 통일 |
| `ef1fc63` | M4 | `post_gen_project.py`에 `npm install --package-lock-only` 추가 |
| `3585f55` | — | PROGRESS.md 업데이트 |

---

## 심각도 높음 (HIGH)

### H1: `_copy_without_render`로 cookiecutter 변수 미렌더링

**문제**: `cookiecutter.json`의 `_copy_without_render`에 `"frontend/src/**"`가 포함되어 있어 `layout.tsx`, `page.tsx` 등의 `{{cookiecutter.project_name}}`이 렌더링되지 않음.

**원인 분석**: TSX의 `{children}`, `{props}` 같은 단일 중괄호는 Jinja2의 `{{ }}` 이중 중괄호와 충돌하지 않음. 초기에 불필요하게 예외 처리를 적용한 것.

**수정**: `_copy_without_render` 배열에서 `"frontend/src/**"` 제거.

### H2: Health check `str(e)`로 인프라 정보 노출

**문제**: `/api/health/` 엔드포인트 에러 시 `str(e)`로 DB 연결 정보(호스트, 포트, 에러 상세)가 HTTP 응답에 노출됨.

**수정**:
```python
# Before
return Response({"status": "unhealthy", "database": str(e)}, status=503)

# After
logger.error("Health check failed: %s", e)
return Response({"status": "unhealthy", "database": "disconnected"}, status=503)
```

- 실제 에러는 `logger.error()`로 서버 로그(CloudWatch)에 기록
- 클라이언트에는 `"disconnected"` 제네릭 메시지만 반환

### H3: `NEXT_PUBLIC_API_URL` 빌드타임 vs 런타임 문제

**문제**: Next.js의 `NEXT_PUBLIC_` 접두사 환경변수는 빌드 타임에 인라인됨. ECS에서 런타임에 주입해도 효과 없음.

**분석**: 프로덕션에서는 ALB가 경로 기반 라우팅(`/api/*` → Backend, `/*` → Frontend)을 처리하므로, Next.js의 rewrites가 불필요함. 로컬 개발에서만 docker-compose 환경에서 rewrites 필요.

**수정**:
1. `next.config.ts`: `NODE_ENV === "production"`일 때 빈 배열 반환
2. `terraform/ecs.tf`: Frontend 환경변수에서 `NEXT_PUBLIC_API_URL` 제거

```typescript
async rewrites() {
  if (process.env.NODE_ENV === "production") {
    return [];
  }
  return [{ source: "/api/:path*", destination: `${...}/api/:path*` }];
}
```

---

## 심각도 중간 (MEDIUM)

### M1: Backend Dockerfile `--platform` 누락

**문제**: ARM64 Mac(M1/M2)에서 빌드한 이미지가 ECS Fargate(x86_64)에서 `exec format error` 발생 가능.

**수정**: `FROM --platform=linux/amd64 python:{{cookiecutter.python_version}}-slim`

### M2: Dockerfile COPY 중복

**문제**: `COPY . .` 이후에 `COPY entrypoint.sh /app/entrypoint.sh`가 중복됨.

**수정**: 중복 COPY 제거. `COPY . .`에 이미 포함되므로 `chmod`만 유지.

### M3: ALB/TG 이름 32자 제한 위반 가능

**문제**: AWS ALB 이름은 32자 제한. `{project}-frontend-service-{env}` 패턴에서 접미사가 ~20자이므로 project_name이 길면 초과.

**수정**: `variables.tf`에 validation 블록 추가:
```hcl
validation {
  condition     = length(var.project_name) <= 18
  error_message = "project_name must be 18 characters or less to avoid AWS resource name limits."
}
```

### M4: package-lock.json 미존재

**문제**: Frontend Dockerfile에서 `npm ci`를 사용하는데 `package-lock.json`이 없으면 실패.

**수정**: `hooks/post_gen_project.py`에서 `use_frontend=yes`일 때 `npm install --package-lock-only` 실행. npm 미설치 시 경고 메시지 출력.

### M5: Terraform `replace()` vs `local.project_name_normalized` 혼용

**문제**: `variables.tf`에 `local.project_name_normalized`이 정의되어 있지만, 대부분의 파일에서 인라인 `replace(var.project_name, "_", "-")`를 직접 사용.

**수정**: 9개 Terraform 파일(vpc, security, ecr, iam, ecs, alb, rds, elasticache, s3)에서 모든 인라인 `replace()` 호출을 `local.project_name_normalized`으로 통일.

### M6: PEP 8 import 위치 위반

**문제**: `from datetime import timedelta`가 파일 중간(179줄)에 위치. PEP 8 E402 위반.

**수정**: 파일 상단 import 블록으로 이동.

### M7: CORS_ALLOWED_ORIGINS ECS 미설정

**문제**: Django settings에서 `CORS_ALLOWED_ORIGINS = env.list('CORS_ALLOWED_ORIGINS', default=[])`로 설정하지만 ECS 환경변수에 누락. Frontend에서 Backend API 호출 시 CORS 차단됨.

**수정**: ECS Backend 환경변수에 추가:
```hcl
{ name = "CORS_ALLOWED_ORIGINS", value = "http://${aws_lb.main.dns_name}" }
```

---

## 변경 파일 목록

| 파일 | ID | 변경 유형 |
|------|-----|-----------|
| `cookiecutter.json` | H1 | 배열 항목 제거 |
| `backend/apps/core/views.py` | H2 | 에러 응답 수정 + 로깅 추가 |
| `frontend/next.config.ts` | H3 | 프로덕션 rewrites 비활성화 |
| `terraform/ecs.tf` | H3, M5, M7 | 환경변수 추가/제거 + 네이밍 통일 |
| `backend/Dockerfile` | M1, M2 | 플랫폼 추가 + 중복 제거 |
| `terraform/variables.tf` | M3 | validation 블록 추가 |
| `hooks/post_gen_project.py` | M4 | npm install 로직 추가 |
| `terraform/vpc.tf` | M5 | 네이밍 통일 |
| `terraform/security.tf` | M5 | 네이밍 통일 |
| `terraform/ecr.tf` | M5 | 네이밍 통일 |
| `terraform/iam.tf` | M5 | 네이밍 통일 |
| `terraform/alb.tf` | M5 | 네이밍 통일 |
| `terraform/rds.tf` | M5 | 네이밍 통일 |
| `terraform/elasticache.tf` | M5 | 네이밍 통일 |
| `terraform/s3.tf` | M5 | 네이밍 통일 |
| `backend/config/settings.py` | M6 | import 위치 이동 |

---

## 남은 사항

- `DATABASE_URL`이 ECS 환경변수에 평문으로 노출 중 — AWS Secrets Manager 적용 시 `SECRET_KEY`와 함께 마이그레이션 권장
- End-to-End 배포 테스트 (cookiecutter 실행 → docker-compose → terraform validate → AWS 배포) 필요
