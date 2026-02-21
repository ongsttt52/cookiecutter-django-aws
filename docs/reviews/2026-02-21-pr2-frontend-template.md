# Code Review: PR #2 — feat/frontend-template

> **PR**: https://github.com/ongsttt52/cookiecutter-django-aws/pull/2
> **브랜치**: `feat/frontend-template-new` → `dev`
> **리뷰 일시**: 2026-02-21
> **커밋 수**: 6

## 커밋 목록

| 커밋 | 메시지 |
|------|--------|
| `69b2fea` | refactor: Add /api prefix to all Django URL patterns |
| `147439b` | feat: Add use_frontend option to cookiecutter template |
| `9f3c91d` | feat: Add Next.js frontend template files |
| `fbb121f` | feat: Add frontend ECS/ALB infrastructure to Terraform |
| `9428117` | feat: Update GitHub Actions for backend/frontend split deployment |
| `40b38b2` | feat: Update supporting files for frontend integration |

---

## 심각도 높음 (4건)

### 1. [Cookiecutter] `_copy_without_render`로 인해 cookiecutter 변수가 렌더링되지 않음

- **위치**: `cookiecutter.json:28` + `layout.tsx:5`, `page.tsx:6`
- **문제**: `frontend/src/**` 가 `_copy_without_render`에 포함되어 `{{cookiecutter.project_name}}`이 리터럴 문자열로 그대로 남음. 생성된 프로젝트에서 브라우저 제목/페이지에 `{{cookiecutter.project_name}}` 텍스트 노출.
- **수정 방안**:
  - (A) `_copy_without_render`에서 `frontend/src/**` 제거. TSX의 단일 중괄호 `{children}`은 Jinja2와 충돌하지 않음
  - (B) `_copy_without_render` 유지하되, layout.tsx/page.tsx에서 cookiecutter 변수 사용 제거하고 환경변수나 상수로 대체

### 2. [보안] DATABASE_URL이 평문 환경변수로 ECS Task Definition에 포함

- **위치**: `ecs.tf:57-58`
- **문제**: DB 비밀번호가 AWS Console, describe-task-definition API, Terraform state에서 평문 노출
- **수정 방안**: Secrets Manager 또는 SSM Parameter Store 사용. 최소한 README/주석에 경고 추가
  ```hcl
  secrets = [
    {
      name      = "DATABASE_URL"
      valueFrom = aws_secretsmanager_secret.db_url.arn
    }
  ]
  ```

### 3. [보안] ECS 태스크에 SECRET_KEY / ALLOWED_HOSTS 환경변수 누락

- **위치**: `ecs.tf:39-85`
- **문제**: PR#1에서 지적된 이슈가 그대로 잔존. 프로덕션에서 insecure 키 + 와일드카드 호스트로 동작
- **수정 방안**: ECS environment 블록에 추가
  ```hcl
  { name = "SECRET_KEY", value = var.django_secret_key },
  { name = "ALLOWED_HOSTS", value = aws_lb.main.dns_name }
  ```

### 4. [아키텍처] NEXT_PUBLIC_API_URL이 빌드 타임 변수인데 런타임에 주입

- **위치**: `ecs.tf:168-171` + `next.config.ts:9`
- **문제**: `NEXT_PUBLIC_` 접두사 환경변수는 빌드 타임에 인라인됨. ECS 런타임 환경변수로 주입해도 이미 빌드된 이미지에는 미반영. 또한 프로덕션에서는 ALB가 `/api/*` 라우팅을 처리하므로 Next.js rewrites 자체가 불필요.
- **수정 방안**:
  - 환경변수명을 `API_URL`(NEXT_PUBLIC 접두사 제거)로 변경하여 서버 전용임을 명확히
  - 프로덕션에서는 rewrites 비활성화, 로컬 개발에서만 사용하도록 조건 분기
  - `Dockerfile.prod` build stage에서 `ARG`로 받아 빌드 타임에 주입하는 것이 정석

---

## 심각도 중간 (8건)

### 1. ALB/Target Group 이름 32자 제한 위반 가능

- **위치**: `alb.tf:7,20`
- **문제**: project_name이 19자 이상이면 초과
- **수정 방안**: `variables.tf`에 길이 검증 추가 또는 `substr()`로 이름 절삭

### 2. package-lock.json 없이 npm install 실행

- **위치**: `frontend/Dockerfile:6-7`
- **문제**: Cookiecutter 생성 직후 lock 파일 미존재. 매 빌드마다 다른 의존성 버전 가능
- **수정 방안**: post_gen hook에서 `npm install` 실행하여 lock 파일 생성, 또는 README에 안내

### 3. `_copy_without_render`에 `.gitignore` 패턴이 모든 경로에 매칭

- **위치**: `cookiecutter.json:27`
- **문제**: 현재는 문제없으나 향후 .gitignore에 cookiecutter 변수 추가 시 렌더링 안 됨
- **수정 방안**: `frontend/.gitignore`처럼 경로 명시

### 4. Frontend → Backend 통신이 ALB를 거침

- **위치**: `ecs.tf:168-171`
- **문제**: Next.js SSR에서 API 호출 시 ALB 왕복 발생. 불필요한 레이턴시
- **수정 방안**: ECS Service Discovery로 내부 직접 접근 구성 권장

### 5. deploy.yml의 raw/endraw + cookiecutter 변수 혼합이 복잡

- **위치**: `deploy.yml:10-18`
- **문제**: 유지보수 시 raw 블록 경계 실수로 GitHub Actions `${{ }}` 렌더링 에러 위험
- **수정 방안**: 블록을 더 크게 분리하거나 주석으로 경계 표시

### 6. Backend Dockerfile에 `--platform linux/amd64` 누락

- **위치**: `backend/Dockerfile:2`
- **문제**: Frontend Dockerfile.prod에는 있으나 Backend에는 미적용. CLAUDE.md 규칙 위반

### 7. CORS_ALLOWED_ORIGINS 미설정으로 프론트엔드 API 호출 차단

- **위치**: `settings.py:189` + `ecs.tf`
- **문제**: ECS에서 `CORS_ALLOW_ALL_ORIGINS=False` + `CORS_ALLOWED_ORIGINS=[]` → 브라우저 CORS 차단
- **수정 방안**: ECS environment에 `CORS_ALLOWED_ORIGINS=http://${aws_lb.main.dns_name}` 추가

### 8. create-infra.yml에서 Frontend ECR URL 미출력

- **위치**: `create-infra.yml:54`
- **문제**: use_frontend=yes여도 Backend ECR URL만 표시
- **수정 방안**: 조건부로 Frontend ECR URL도 함께 출력

---

## 개선 제안 (7건)

1. **Frontend ECS에 환경별 리소스 분기** — Backend처럼 demo/prod에 따른 cpu/memory 분기 추가
2. **Terraform `replace()` 대신 `local.project_name_normalized` 통일** — 파일마다 혼용 중
3. **ESLint 의존성 누락** — `package.json`에 `eslint`, `eslint-config-next` 미포함으로 `npm run lint` 실패
4. **docker-compose anonymous volume → named volume** — `docker compose down` 시 정리 안 됨
5. **`.gitignore` 중복 항목 정리** — `*.swp`, `.DS_Store`, `*~` 중복 존재
6. **README에서 Redis 무조건 시작 안내** — Jinja2 조건문으로 감싸야 함
7. **post_gen_project.py에 celery/websocket 정리 로직 추가** — 현재 frontend만 처리
