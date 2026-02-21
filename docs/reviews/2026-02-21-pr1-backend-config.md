# Code Review: PR #1 — feat/backend-config

> **PR**: https://github.com/ongsttt52/cookiecutter-django-aws/pull/1
> **브랜치**: `feat/backend-config` → `dev`
> **리뷰 일시**: 2026-02-21
> **커밋 수**: 6

## 커밋 목록

| 커밋 | 메시지 |
|------|--------|
| `be69834` | feat: Add core app with /health/ endpoint for ALB health check |
| `5a194bc` | feat: Add entrypoint.sh for automatic migrate and collectstatic on startup |
| `4f2f407` | refactor: Update Dockerfile to use entrypoint.sh instead of build-time collectstatic |
| `695e998` | feat: Wire up core app, health check URL, and drf-spectacular Swagger UI |
| `53e1b14` | fix: Fix .env.example S3 bucket name to match demo environment |
| `b813c33` | fix: Fix migration race condition by skipping entrypoint for worker containers |

---

## 심각도 높음 (4건)

### 1. [보안] SECRET_KEY에 하드코딩된 기본값 존재

- **위치**: `settings.py:19`
- **현재 코드**: `SECRET_KEY = env('SECRET_KEY', default='django-insecure-change-this-in-production')`
- **문제**: 환경변수 미설정 시 insecure 키로 프로덕션 가동. ECS 태스크에서도 미설정.
- **수정 방안**: `default` 제거하여 미설정 시 즉시 에러 발생하도록 변경
  ```python
  SECRET_KEY = env('SECRET_KEY')  # default 제거
  ```

### 2. [보안] ALLOWED_HOSTS 기본값이 와일드카드

- **위치**: `settings.py:21`
- **현재 코드**: `ALLOWED_HOSTS = env.list('ALLOWED_HOSTS', default=['*'])`
- **문제**: Host Header Injection 공격에 취약. ECS에서 ALLOWED_HOSTS 미설정이므로 실제 와일드카드로 동작.
- **수정 방안**: `default=[]`로 변경, ECS 태스크에 ALB DNS로 명시적 설정 추가

### 3. [보안] Health check 에러 응답에 인프라 정보 노출

- **위치**: `views.py:17`
- **현재 코드**: `{"status": "unhealthy", "database": str(e)}`
- **문제**: `str(e)`가 DB 호스트명, 포트, 인증 오류 세부사항 등 내부 정보 노출
- **수정 방안**: 로깅으로 처리하고 응답은 최소화
  ```python
  logger.error("Health check failed: %s", e)
  return Response({"status": "unhealthy", "database": "disconnected"}, status=503)
  ```

### 4. [인프라] ECS 태스크에 필수 환경변수 누락

- **위치**: `ecs.tf:51-72`
- **누락 항목**: `SECRET_KEY`, `ALLOWED_HOSTS`, `CORS_ALLOWED_ORIGINS`
- **문제**: 위 1,2번과 결합하여 insecure 키 + 와일드카드 호스트 + CORS 차단으로 프로덕션 동작
- **수정 방안**: Terraform environment 블록에 추가. SECRET_KEY는 Secrets Manager 또는 GitHub Secret 사용 권장

---

## 심각도 중간 (6건)

### 1. ECS 멀티 태스크에서 마이그레이션 경합

- **위치**: `entrypoint.sh` + `ecs.tf:97`
- **문제**: prod에서 `desired_count=2`일 때 2개 태스크가 동시에 migrate 실행
- **수정 방안**: 배포 파이프라인에서 별도 migrate 태스크 분리 또는 advisory lock 추가

### 2. Backend Dockerfile에 `--platform linux/amd64` 미적용

- **위치**: `Dockerfile:1`
- **문제**: CLAUDE.md 규칙 위반. ARM Mac에서 `make dev` 시 문제 가능
- **수정 방안**: `FROM --platform=linux/amd64 python:{{cookiecutter.python_version}}-slim AS base`

### 3. Dockerfile에서 COPY 중복

- **위치**: `Dockerfile:32,35`
- **문제**: `COPY . .` 후 `COPY entrypoint.sh` 중복 — 불필요한 레이어
- **수정 방안**: 35번 줄 제거, `chmod`만 유지

### 4. import 위치 PEP 8 위반

- **위치**: `settings.py:179`
- **문제**: `from datetime import timedelta`가 파일 중간에 위치
- **수정 방안**: 파일 상단으로 이동

### 5. AWS 자격증명이 settings에 직접 할당

- **위치**: `settings.py:147-148`
- **문제**: ECS에서는 IAM Task Role 사용인데, 빈 문자열 할당 시 boto3 인증 실패 가능
- **수정 방안**: 환경 분기하여 로컬에서만 설정되도록 변경

### 6. .env.example에 ENVIRONMENT 변수 누락

- **위치**: `.env.example`
- **문제**: settings.py에서 참조하는데 가이드 없음
- **수정 방안**: `ENVIRONMENT=dev` 항목 추가

---

## 개선 제안 (5건)

1. **Dockerfile 멀티스테이지 빌드** — gcc 등 빌드 도구가 최종 이미지에 남음. 이미지 크기 축소 가능
2. **Swagger UI 접근 제한** — `DEBUG=True`일 때만 노출되도록 조건 분기
3. **django-storages 의존성 정리** — pyproject.toml에 포함되어 있으나 실제 미사용
4. **로컬 개발 전용 Dockerfile 분리** — docker-compose에서 프로덕션 Dockerfile 빌드 후 command 덮어쓰는 구조 개선
5. **Health check DB 쿼리** — 현재 규모 OK, 스케일업 시 경량 liveness probe 분리 고려
