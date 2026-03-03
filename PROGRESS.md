# Django AWS Cookiecutter Template - 진행상황

**마지막 업데이트:** 2026-03-03

---

## 프로젝트 개요

Django 5.2.7 + AWS ECS 배포를 위한 **프로덕션급 Cookiecutter 템플릿**

**핵심 목표:** 외주 계약자가 클라이언트 데모를 빠르게 AWS에 배포할 수 있는 템플릿

**기술 스택:**
- Django 5.2.7 + Django REST Framework + JWT 인증
- **Next.js 15** (프론트엔드 - TypeScript + Tailwind CSS 4) [선택 옵션]
- AWS S3 Presigned URL (파일 업로드/다운로드)
- Docker Compose (로컬 개발)
- PostgreSQL 16, Redis 7, Celery, WebSocket (Channels)
- uv 패키지 매니저
- **ECS Fargate** (프로덕션 배포)
- **Terraform** (인프라 관리)
- **Terraform S3 Backend** (State 관리)
- **GitHub Actions** (CI/CD)
- **ALB 경로 기반 라우팅** (/ → Frontend, /api → Backend)

---

## 완료된 작업 ✅

### Phase 1: 로컬 개발 환경 (완료)
- ✅ Cookiecutter 템플릿 기본 구조
- ✅ Docker Compose 6개 서비스 설정
  - PostgreSQL 16
  - Redis 7
  - Django Backend (DRF + JWT)
  - WebSocket (Daphne)
  - Celery Worker
  - Celery Beat
- ✅ S3 Presigned URL 전략 설정
- ✅ Celery 설정 파일 추가
- ✅ .env 파일 위치 변경 (프로젝트 루트)
- ✅ README.md 문서화
- ✅ macOS + Windows WSL 테스트 완료

### Phase 2: Terraform 인프라 코드 (완료)
- ✅ **13개 Terraform 파일 작성 완료**
  - `main.tf` - Provider 설정
  - `variables.tf` - 입력 변수 정의 + 이름 정규화 로직
  - `vpc.tf` - VPC, 서브넷, 인터넷 게이트웨이
  - `security.tf` - 보안 그룹 4개 (ALB, ECS, RDS, Redis)
  - `s3.tf` - S3 버킷 + CORS + Lifecycle
  - `rds.tf` - PostgreSQL 16 (db.t3.micro/small)
  - `elasticache.tf` - Redis 7.0 (cache.t3.micro/small)
  - `ecr.tf` - Docker 이미지 저장소
  - `iam.tf` - ECS Task 권한 설정
  - `alb.tf` - Application Load Balancer
  - `ecs.tf` - ECS Fargate Task Definition + Service
  - `outputs.tf` - URL 등 출력값
  - `backend.tf` - S3 Backend 설정 (NEW!)
  - `README.md` - Terraform 사용 가이드

- ✅ **Terraform S3 Backend 구현 완료**
  - S3 bucket: `demodev-lab-terraform-states` 생성
  - Versioning 활성화 (State 복구 가능)
  - 암호화 활성화 (AES256)
  - State 경로: `{project_name}/demo/terraform.tfstate`
  - GitHub Actions 간 state 공유 가능
  - **terraform destroy가 제대로 작동** ✅

- ✅ **실제 AWS 배포 테스트 성공**
  - terraform init ✅
  - terraform validate ✅
  - terraform plan ✅ (34개 리소스)
  - terraform apply ✅ (34개 리소스 생성 성공)
  - terraform destroy ✅ (완전 삭제 확인)
  - **S3 backend state 저장 확인** ✅

### Phase 3: GitHub Actions CI/CD (완료)

- ✅ **3개 워크플로우 파일 작성**
  - `create-infra.yml` - Terraform 인프라 생성 (수동 트리거)
  - `deploy.yml` - 앱 배포 (main push 시 자동, 수동도 가능)
  - `destroy.yml` - 인프라 삭제 (수동 트리거, 확인 필요)

- ✅ **Makefile 자동화**
  - `make init` - GitHub 레포 생성 + Secrets 설정 + 브랜치 구조
  - `make setup-secrets` - GitHub Secrets 설정
  - `make dev` - 로컬 개발 환경 실행
  - `make destroy-aws-manual` - 긴급 수동 삭제 (Terraform state 문제 시)

- ✅ **브랜치 전략**
  - `main` 브랜치: AWS demo 환경 자동 배포
  - `dev` 브랜치: 로컬 개발만 (docker-compose)

- ✅ **인프라 체크 로직**
  - deploy.yml에 `check-infrastructure` job 추가
  - ECR 존재 여부 확인 후 배포 진행
  - 인프라 없으면 배포 스킬 + 안내 메시지

- ✅ **환경 네이밍 전략 (demo/prod)**
  - `demo` (기본값): 클라이언트 데모용, 작은 인스턴스, 빠른 생성/삭제
  - `prod`: 프로덕션 환경, 큰 인스턴스, 백업/보호 활성화
  - 모든 Terraform 파일에 반영 완료

- ✅ **리소스 네이밍 규칙**
  - 프로젝트 이름 정규화: `_` → `-` 자동 변환
  - ECS Cluster: `{project}-cluster-{env}`
  - ECS Service: `{project}-service-{env}`
  - IAM Execution Role: `{project}-ecs-execution-role-{env}`
  - IAM Task Role: `{project}-ecs-task-role-{env}`
  - Makefile과 Terraform 네이밍 일치

- ✅ **조직 레포지토리 지원**
  - demodev-lab 조직으로 레포 생성
  - Private repo (self-hosted runner 접근)
  - make init에서 조직 선택 가능

**생성된 AWS 리소스 (34개):**
1. VPC + Public/Private 서브넷 (6개)
2. 인터넷 게이트웨이 + 라우트 테이블 (3개)
3. 보안 그룹 4개 (ALB, ECS, RDS, Redis)
4. S3 버킷 + 설정 (4개)
5. RDS PostgreSQL + 서브넷 그룹 (2개)
6. ElastiCache Redis + 서브넷 그룹 (2개)
7. ECR + Lifecycle Policy (2개)
8. IAM 역할 2개 + 정책 2개 (4개)
9. ALB + Target Group + Listener (3개)
10. ECS Cluster + Task Definition + Service (3개)
11. CloudWatch 로그 그룹 (1개)

**커밋 내역:**
- `e468e7f` - Add Terraform infrastructure code with AWS deployment support
- `91e766a` - Update PROGRESS.md with Terraform and AWS deployment plan
- `4191508` - Add Celery configuration files
- `fb24848` - Initial cookiecutter Django AWS template

---

### Phase 4: Django 백엔드 설정 완성 (완료)

**PR**: [#1 feat/backend-config → dev](https://github.com/ongsttt52/cookiecutter-django-aws/pull/1)
**작업일**: 2026-02-21

- ✅ ALB health check용 `/health/` 엔드포인트 (core app) 추가
- ✅ `entrypoint.sh` — 컨테이너 시작 시 migrate + collectstatic 자동 실행
- ✅ Dockerfile을 빌드 타임 collectstatic에서 entrypoint 방식으로 전환
- ✅ drf-spectacular Swagger UI (`/api/docs/`) 연동
- ✅ Worker 컨테이너(celery)에서 entrypoint 실행 방지 (migration race condition 해결)
- ✅ `.env.example` S3 버킷명 demo 환경에 맞게 수정

**코드 리뷰**: [`docs/reviews/2026-02-21-pr1-backend-config.md`](docs/reviews/2026-02-21-pr1-backend-config.md)

<details>
<summary>Phase 4 이전 디버깅 기록 (2025-10-23, test_workflow_v4)</summary>

#### 해결한 주요 이슈들:

1. **Docker 플랫폼 호환성 문제** — `exec format error` → Docker Buildx + `--platform linux/amd64`
2. **UV 패키지 매니저 설치 방식** — `COPY --from` 플랫폼 불일치 → `pip install uv`
3. **AWS 자격증명 처리** — ECS에서 필수 요구 → `env('AWS_ACCESS_KEY_ID', default=None)` + IAM Task Role
4. **리소스 네이밍 불일치** — `test_workflow_v4` vs `test-workflow-v4` → deploy.yml에서 정규화
5. **HTTPS 강제 리다이렉트** — demo 환경 SSL 없음 → `ENVIRONMENT` 변수로 prod만 HTTPS 강제
6. **Django Admin Static 파일** — CSS/JS 미로드 → WhiteNoise + `collectstatic`
7. **S3 버킷 이름 일관성** — `*-media-prod` 기본값 → `*-media-demo` 정규화
8. **ALB URL 동적 조회** — 하드코딩 → AWS CLI 동적 조회 (`PROJECT_NAME` 기반)
9. **Health Check Job AWS Credentials** — credentials 없음 → `configure-aws-credentials` 추가

#### 최종 테스트 결과:
- ✅ Terraform 인프라 생성 성공 (34개 리소스)
- ✅ Docker 이미지 빌드 + ECR 푸시 + ECS Fargate 배포 성공
- ✅ Django Admin 페이지 정상 표시 (CSS/JS 로드됨)
- ✅ IAM Task Role 기반 S3 접근 가능

</details>

### Phase 5: Next.js 프론트엔드 템플릿 통합 (완료)

**PR**: [#2 feat/frontend-template-new → dev](https://github.com/ongsttt52/cookiecutter-django-aws/pull/2)
**작업일**: 2026-02-21

- ✅ `cookiecutter.json`에 `use_frontend` 선택 옵션 추가 (yes/no)
- ✅ Django URL에 `/api` prefix 추가 (ALB 경로 기반 라우팅 준비)
- ✅ Next.js 15 + React 19 + TypeScript + Tailwind CSS 4 프론트엔드 템플릿
- ✅ `hooks/post_gen_project.py` — `use_frontend=no`일 때 frontend/ 자동 삭제
- ✅ Terraform: ECR/ECS/ALB 리소스 리네이밍 (app → backend) + frontend 리소스 조건부 추가
- ✅ ALB 경로 기반 라우팅: `/api/*` → Backend TG, `/*` → Frontend TG
- ✅ GitHub Actions: backend/frontend 분리 빌드/배포 파이프라인
- ✅ Docker Compose: frontend 서비스 조건부 추가
- ✅ Makefile, .env.example, .gitignore, README 업데이트

**아키텍처:**
```
ALB (port 80)
├── Rule: /api/* → Backend TG (Django, port 8000)  [priority 1]
└── Default: /*  → Frontend TG (Next.js, port 3000)
```

**코드 리뷰**: [`docs/reviews/2026-02-21-pr2-frontend-template.md`](docs/reviews/2026-02-21-pr2-frontend-template.md)

---

### Phase 6: 코드 리뷰 지적사항 수정 (완료)

**작업일**: 2026-02-22

#### 심각도 높음

- [x] H1: `_copy_without_render`에서 `frontend/src/**` 제거 — TSX의 `{children}`은 Jinja2 `{{ }}`와 충돌하지 않음
- [x] H2: Health check `str(e)` → `logger.error()` + `"disconnected"` 제네릭 메시지로 인프라 정보 노출 차단
- [x] H3: `NEXT_PUBLIC_API_URL` 빌드타임 문제 — 프로덕션에서 rewrites 비활성화 (ALB가 라우팅), ECS에서 `NEXT_PUBLIC_API_URL` 제거
- [x] (이전 완료) ECS 태스크에 `SECRET_KEY`, `ALLOWED_HOSTS` 환경변수 추가 (`b991c4f`, `42f38f6`)

#### 심각도 중간

- [x] M1: Backend Dockerfile에 `--platform=linux/amd64` 추가
- [x] M2: Dockerfile 중복 `COPY entrypoint.sh` 제거 (이미 `COPY . .`에 포함)
- [x] M3: `project_name` 18자 이하 validation 추가 (ALB/TG 32자 제한 대응)
- [x] M4: `post_gen_project.py`에 `npm install --package-lock-only` 추가 (package-lock.json 자동 생성)
- [x] M5: Terraform 9개 파일에서 인라인 `replace()` → `local.project_name_normalized` 통일
- [x] M6: `settings.py`의 `from datetime import timedelta`를 파일 상단으로 이동 (PEP 8)
- [x] M7: ECS Backend 환경변수에 `CORS_ALLOWED_ORIGINS` 추가

---

### Phase 6.5: post_gen_project.py 개선 (완료)

**작업일**: 2026-02-22

- [x] `use_celery=no`일 때 `backend/config/celery.py` 자동 삭제 로직 추가
  - 기존에는 docstring만 있는 빈 파일이 남아있었음
  - `remove_file()` 헬퍼 함수 추가

### Phase 7: E2E 배포 테스트 (완료)

**작업일**: 2026-02-22 ~ 2026-02-27

#### 1단계: Cookiecutter 렌더링 테스트 ✅

- [x] 케이스 A (풀옵션: celery + websocket + frontend) 렌더링 성공
- [x] 케이스 B (최소: backend only) 렌더링 성공
- [x] `{{cookiecutter.*}}` 잔여 변수 없음 확인
- [x] `{% %}` 잔여 조건문 없음 확인
- [x] `use_frontend=no` → `frontend/` 삭제 확인
- [x] `use_celery=no` → `celery.py` 삭제 확인
- [x] `package-lock.json` 자동 생성 확인 (use_frontend=yes)
- [x] docker-compose.yml 조건부 서비스 정상 렌더링
- [x] Terraform 파일 조건부 리소스 정상 렌더링
- [x] deploy.yml 조건부 job 정상 렌더링
- [x] 프로젝트명 정규화 (`test_full` → `test-full`) 확인
- [x] `local.project_name_normalized` 통일 확인 (인라인 replace 잔재 없음)

#### 2단계: Docker Compose 로컬 테스트 ✅

- [x] 케이스 A: 7개 컨테이너 전부 정상 구동 (db, redis, backend, celery_worker, celery_beat, websocket, frontend)
- [x] 케이스 B: 2개 컨테이너 정상 구동 (db, backend)
- [x] DB 마이그레이션 자동 실행 확인
- [x] `/api/health/` → `{"status":"healthy","database":"connected"}`
- [x] `/api/admin/login/` → HTTP 200
- [x] `/api/docs/` (Swagger UI) → HTTP 200
- [x] `localhost:3000` (Frontend) → HTTP 200 (케이스 A)
- [x] Celery Worker ready 확인
- [x] Celery Beat started 확인
- [x] WebSocket (Daphne) listening on 8001 확인

**참고**: 첫 실행 시 `uv sync` 패키지 설치로 Backend 시작에 30~40초 소요

#### 3단계: Terraform 검증 ✅

- [x] 케이스 A: `terraform init -backend=false` 성공
- [x] 케이스 A: `terraform validate` — Success
- [x] 케이스 B: `terraform init -backend=false` 성공
- [x] 케이스 B: `terraform validate` — Success
- [x] 조건부 렌더링 검증: 케이스 B에서 frontend 리소스 제거 확인 (ecs.tf 232→137줄, alb.tf 103→61줄, ecr.tf 80→43줄)
- [x] `terraform apply` 리소스 생성 확인 (4단계에서 검증)

#### 4단계: AWS 실제 배포 테스트 ✅

- [x] `make init` → GitHub 레포 생성 (ongsttt52/test-e2e) + Secrets 설정
- [x] `create-infra.yml` → Terraform apply 성공 (10분 소요)
- [x] `deploy.yml` → Docker 빌드 + ECR push + ECS 배포 성공 (6분 소요)
- [x] ALB 라우팅 확인:
  - `/api/health/` → `{"status":"healthy","database":"connected"}`
  - `/api/admin/` → HTTP 200
  - `/api/docs/` → Swagger UI 정상 반환
  - `/` → HTTP 200 (Next.js, X-Powered-By: Next.js)
- [ ] `destroy.yml` → Terraform destroy (사용자 실행 예정)

**발견된 이슈 (배포 과정):**
1. `.env`에 AWS credentials 플레이스홀더 → `make setup-secrets`가 가짜 값 등록 → Secrets 재설정으로 해결
2. Terraform S3 Backend 버킷 (`demodev-lab-terraform-states`) 접근 불가 → 개인 버킷 생성으로 해결

---

## 현재 작업 중 🚧

Phase 10 완료.

### Phase 8: EC2 All-in-One 배포 옵션 + deploy.sh (완료)

**Phase A: EC2 All-in-One 배포 옵션**
- [x] `cookiecutter.json`에 `aws_deployment` 배열 추가 (`["ecs-fargate", "ec2-all-in-one"]`)
- [x] Terraform EC2 파일 3개 생성 (`ec2.tf`, `ec2_iam.tf`, `ec2_security.tf`)
- [x] 기존 Terraform 7개 파일 `ecs-fargate` 조건부 래핑
- [x] `variables.tf` EC2 변수 추가, `outputs.tf` 배포 모드별 분기
- [x] `docker-compose.prod.yml` EC2 프로덕션용 생성
- [x] `deploy-ec2.yml` GitHub Actions 워크플로우 생성
- [x] `create-infra.yml`, `destroy.yml` 배포 모드별 분기 수정
- [x] `post_gen_project.py` 배포 모드별 파일 정리 로직 추가
- [x] `Makefile` EC2 모드 지원 (SSH 키 생성, destroy 분기)
- [x] `.env.example`, `README.md` EC2 설명 추가
- [x] E2E 테스트 4개 케이스 (ECS+풀, ECS+최소, EC2+풀, EC2+최소) 모두 PASS

**Phase B: deploy.sh 전체 워크플로우 스크립트**
- [x] `deploy.sh` 작성 (Step 0~9: 사전조건, 입력, 렌더링, .env, 로컬테스트, GitHub init, 인프라생성, 배포, 검증, 결과)
- [x] `--no-input`, `--skip-local-test` 옵션 지원
- [x] AWS credentials 자동 감지, EC2 SSH 키 자동 생성

**EC2 All-in-One 아키텍처:**
```
EC2 Instance (t3.small, ~$15/month)
├── Docker Compose
│   ├── PostgreSQL (container)
│   ├── Redis (container)
│   ├── Django + Gunicorn (port 80)
│   ├── Celery Worker (optional)
│   └── Next.js Frontend (optional)
└── S3 (external, for media files)
```

**비용 비교:**
| 모드 | 월 비용 | 적합한 용도 |
|------|---------|-------------|
| EC2 All-in-One | ~$15 | 클라이언트 데모, 프로토타입 |
| ECS Fargate | ~$60 | 프로덕션, 확장성 |

### Phase 9A: S3 Presigned URL API + Superuser 자동 생성 (완료)

**작업일**: 2026-02-28

#### 작업 1: S3 Presigned URL API
- [x] `backend/apps/files/` 앱 생성 (4개 파일)
- [x] `POST /api/files/upload/` — S3 put_object presigned URL 생성
- [x] `POST /api/files/download/` — S3 get_object presigned URL 생성
- [x] JWT 인증 필수 (DEFAULT_PERMISSION_CLASSES 상속)
- [x] 파일 확장자 화이트리스트 (이미지, 문서, 미디어, 압축 등 30종)
- [x] 다운로드 소유권 검증 (`uploads/{user_id}/` prefix 체크)
- [x] Swagger 문서화 (`@extend_schema`, tags=["files"])
- [x] S3 클라이언트 전략: ECS(IAM Role) / Local·EC2(명시적 credentials)
- [x] `settings.py` — INSTALLED_APPS, AWS_MAX_FILE_SIZE, SPECTACULAR_SETTINGS
- [x] `urls.py` — `/api/files/` 라우팅 등록

#### 작업 2: Superuser 자동 생성
- [x] `entrypoint.sh` — DJANGO_SUPERUSER_EMAIL/PASSWORD 환경변수 기반 자동 생성
- [x] Django 3.0+ `--noinput` + `DJANGO_SUPERUSER_PASSWORD` 공식 기능 활용
- [x] 멱등성: 이미 존재하면 스킵 (`2>/dev/null || echo "...skipping"`)
- [x] `.env.example` — superuser 변수 추가 (주석 상태)
- [x] `variables.tf` — django_superuser_email/password 변수 추가
- [x] `ecs.tf` — Backend container environment에 3개 변수 추가
- [x] `ec2.tf` + `user-data.sh` — templatefile 변수 전달 + .env 추가
- [x] `create-infra.yml` / `destroy.yml` — terraform `-var` 추가
- [x] `Makefile` — init/setup-secrets에 DJANGO_SUPERUSER_PASSWORD 프롬프트

### Phase 9B: dev HEAD 코드 리뷰 수정 (완료)

**작업일**: 2026-03-01
**코드 리뷰**: [`docs/reviews/2026-03-01-dev-head-code-review.md`](docs/reviews/2026-03-01-dev-head-code-review.md)

dev HEAD (`1f51c4d`) 기준으로 소규모 스타트업 관점의 코드 리뷰를 수행하고, FIX 4건 + WARN 3건을 수정.

#### FIX (배포 실패 또는 기능 깨짐)
- [x] F1: `post_gen_project.py` — ECS/EC2 모드 전환 시 빈 Terraform 파일 잔류 → 사용하지 않는 .tf 파일 삭제 로직 추가
- [x] F2: `user-data.sh` — EC2 재부팅 시 서비스 자동 시작 안 됨 → systemd 서비스 등록
- [x] F3: `deploy.sh` — sed 치환이 AWS Secret Key의 특수문자(`&`, `\`)에서 실패 → python3 replace로 교체
- [x] F4: `ec2_security.tf` — SSH 0.0.0.0/0 전역 개방 → `ssh_allowed_cidrs` 변수화 + `create-infra.yml`에서 현재 IP 자동 감지

#### WARN (특정 조건에서 깨질 수 있음)
- [x] W1: `files/views.py` — filename에 경로 구분자 포함 시 S3 키 오염 → `os.path.basename()` 추가
- [x] W2: `entrypoint.sh` — superuser 생성 에러가 `2>/dev/null`로 무시됨 → `2>&1`로 변경
- [x] W3: `deploy-ec2.yml` — 동시 실행 제어 없음 → `concurrency` 블록 추가

**수정된 파일 (10개):**
- `hooks/post_gen_project.py`
- `deploy.sh`
- `{{cookiecutter.project_slug}}/terraform/user-data.sh`
- `{{cookiecutter.project_slug}}/terraform/variables.tf`
- `{{cookiecutter.project_slug}}/terraform/ec2_security.tf`
- `{{cookiecutter.project_slug}}/.github/workflows/create-infra.yml`
- `{{cookiecutter.project_slug}}/.github/workflows/destroy.yml`
- `{{cookiecutter.project_slug}}/.github/workflows/deploy-ec2.yml`
- `{{cookiecutter.project_slug}}/backend/apps/files/views.py`
- `{{cookiecutter.project_slug}}/backend/entrypoint.sh`

### Phase 10: CI 코드 품질 + 테스트 인프라 (완료)

**작업일**: 2026-03-03

pyproject.toml에 선언된 pytest, ruff, black 등 도구를 실제로 활용하여 테스트 코드를 작성하고, 배포 전 자동 품질 게이트를 추가.

#### 작업 1: pytest 공통 fixture (conftest.py)
- [x] `backend/conftest.py` 생성
- [x] `user` fixture — `get_user_model()` 테스트 유저 생성
- [x] `api_client` fixture — DRF APIClient 인스턴스
- [x] `authenticated_client` fixture — `force_authenticate` 적용 클라이언트

#### 작업 2: Health Check 테스트 (3건)
- [x] `apps/core/tests/test_views.py` 생성
- [x] 정상 DB 연결 → 200 + healthy 응답
- [x] DB 연결 실패 (mock) → 503 + unhealthy 응답
- [x] AllowAny 퍼미션으로 인증 없이 접근 가능

#### 작업 3: Files API 테스트 (16건)
- [x] `apps/files/tests/test_views.py` 생성
- [x] Upload Presigned URL 테스트 7건 (정상, 누락, 확장자, path traversal, 미인증, S3 에러)
- [x] Download Presigned URL 테스트 5건 (정상, 누락, 권한, 미인증, S3 에러)
- [x] `_get_extension` 헬퍼 테스트 4건 (일반, 이중, 없음, 대소문자)
- [x] Mock 전략: `_get_s3_client` patch로 실제 AWS 호출 없음

#### 작업 4: deploy.yml quality job
- [x] `quality` job 추가 (check-infrastructure와 병렬)
- [x] PostgreSQL 16 서비스 컨테이너
- [x] ruff check → black --check → pytest 순서 실행
- [x] `build-backend`, `build-frontend`의 needs에 quality 추가
- [x] quality 실패 시 빌드/배포 중단

#### 작업 5: deploy-ec2.yml quality job
- [x] deploy.yml과 동일한 quality job 추가
- [x] deploy job의 needs에 quality 추가

**수정/생성 파일 (7개):**
- `backend/conftest.py` (신규)
- `backend/apps/core/tests/__init__.py` (신규)
- `backend/apps/core/tests/test_views.py` (신규)
- `backend/apps/files/tests/__init__.py` (신규)
- `backend/apps/files/tests/test_views.py` (신규)
- `.github/workflows/deploy.yml` (수정)
- `.github/workflows/deploy-ec2.yml` (수정)

**CI 파이프라인 구조:**
```
# ECS Fargate (deploy.yml)
quality ──────────────┐
                      ├──→ build-backend ──┐
check-infrastructure ─┤                    ├──→ deploy ──→ health-check
                      ├──→ build-frontend ─┘
                      │    (use_frontend=yes)
                      └────────────────────────

# EC2 (deploy-ec2.yml)
quality ──→ deploy ──→ health-check
```

---

## 다음 단계

**우선순위 4: 템플릿 DX 개선**
- [ ] `.env.example`에 AWS credentials 플레이스홀더 경고 문구 추가
- [ ] `make init` 실행 전 `.env` 유효성 검사 강화 (플레이스홀더 감지)
- [ ] `terraform_state_bucket` 값을 cookiecutter.json 변수로 분리

**우선순위 5: 추가 기능 (선택)**
- [x] EC2 All-in-One 배포 옵션 추가 (Phase 8에서 완료)
- [ ] CloudWatch 로그 필터 설정
- [ ] 최소 케이스(backend only) AWS E2E 배포 테스트

---

## 다음 작업 계획 📋

### 작업 1: EC2 배포 옵션 추가 (선택 사항)

**배경:**
- ECS Fargate: 24/7 운영 시 비용이 높음 (~$9/task/월)
- EC2 All-in-One: 모든 컨테이너를 하나의 EC2에서 실행 (~$7/월 전체)
- 데모 환경에서 극한의 비용 절감 가능

**계획:**
```json
// cookiecutter.json
{
  "aws_deployment": ["ecs-fargate", "ec2-all-in-one"]
}
```

**필요한 작업:**
- [ ] ec2-all-in-one Terraform 템플릿 작성
- [ ] docker-compose를 EC2에서 실행하는 user-data 스크립트
- [ ] GitHub Actions 워크플로우 수정

**주의사항:**
- Django 코드는 동일하게 유지
- 인프라 설정만 변경
- 프로덕션 전환 시 ECS로 쉽게 전환 가능

---

## 사용 방법

### 1. 프로젝트 생성
```bash
cookiecutter cookiecutter-django-aws/
# project_name 입력 (예: my_django_project)
```

### 2. GitHub 레포 생성 및 초기 배포
```bash
cd my_django_project/
cp .env.example .env
# .env 파일 수정 (AWS 키 입력)

make init
# 1. GitHub 레포 생성
# 2. Secrets 설정
# 3. main/dev 브랜치 생성
# 4. Push
```

### 3. AWS 인프라 생성
GitHub Actions에서:
1. "Create AWS Infrastructure" 워크플로우 실행 (수동)
2. 5-10분 대기 (RDS, Redis 생성 시간)
3. 완료 확인

### 4. 앱 자동 배포
```bash
# 코드 수정 후
git add .
git commit -m "Update feature"
git push origin main
# → GitHub Actions가 자동으로 Docker 빌드 + ECR push + ECS 배포
```

### 5. 로컬 개발
```bash
git checkout dev
make dev
# → docker-compose up -d
# → http://localhost:8000
```

### 6. 인프라 삭제
GitHub Actions에서:
1. "Destroy AWS Infrastructure" 워크플로우 실행
2. 확인 입력: "destroy"
3. 완료 대기

**긴급 수동 삭제:**
```bash
make destroy-aws-manual
# "destroy demo" 타이핑하여 확인
```

---

## 비용 정보

### demo 환경 (월 예상)
- RDS db.t3.micro: ~$15
- ElastiCache cache.t3.micro: ~$12
- ECS Fargate (0.25vCPU, 512MB, 1개): ~$9
- ALB: ~$20
- S3, VPC, CloudWatch: ~$3
- **총 ~$60/월**

### prod 환경 (월 예상)
- RDS db.t3.small: ~$30
- ElastiCache cache.t3.small: ~$24
- ECS Fargate (0.5vCPU, 1GB, 2개): ~$18
- ALB: ~$20
- S3, VPC, CloudWatch: ~$6
- **총 ~$100/월**

### EC2 All-in-One (구현 완료)
- EC2 t3.small: ~$15/월
- **모든 컨테이너 포함 (Django, Celery, Redis, PostgreSQL)**
- 데모용으로 충분한 성능, ECS 대비 75% 비용 절감

**개발/테스트:**
- 10분 테스트: ~$0.01 (10원)
- 1시간: ~$0.06 (60원)
- terraform destroy로 즉시 삭제 가능

---

## Terraform State 관리

### S3 Backend 설정

**State 저장소:**
- Bucket: `demodev-lab-terraform-states` (회사 공용)
- 경로: `{project_name}/{environment}/terraform.tfstate`
- 암호화: AES256
- Versioning: 활성화

**장점:**
- GitHub Actions 간 state 공유
- 팀원들과 협업 가능
- terraform destroy 정상 작동
- State 손실 시 복구 가능

**주의사항:**
- State bucket은 `make destroy-aws`로 삭제되지 않음
- 프로젝트 완전 폐기 시 수동 삭제 필요:
  ```bash
  aws s3 rm s3://demodev-lab-terraform-states/{project_name}/ --recursive
  ```

---

## 환경 설정

### 개발 환경
- macOS Sequoia 24.6.0
- Git 레포: github.com/demodev-lab/cookiecutter-django-aws.git
- 브랜치: main

### 필요한 도구
- ✅ Git
- ✅ Docker + Docker Compose
- ✅ cookiecutter
- ✅ Terraform 1.5.7+
- ✅ AWS CLI 2.31.18+
- ✅ GitHub CLI (gh)

---

## Terraform vs GitHub Actions

| 항목 | Terraform | GitHub Actions |
|------|----------|---------------|
| **역할** | 인프라 생성/삭제 | 앱 배포 |
| **실행 위치** | GitHub Actions | GitHub Actions |
| **실행 빈도** | 최초 1회 + 인프라 변경 시 | 코드 푸시할 때마다 |
| **트리거** | 수동 (workflow_dispatch) | main push 시 자동 |
| **생성 대상** | VPC, RDS, ECS 클러스터 등 | Docker 이미지, 배포 |
| **State 관리** | S3 Backend | N/A |
| **비용** | 리소스 생성 시 | 무료 (2000분/월) |

---

## 알려진 이슈 및 해결 방법

### 1. Terraform State 문제 ✅ (해결됨)
**증상:** `terraform destroy`가 "0 destroyed" 출력
**원인:** State가 로컬에만 저장되어 GitHub Actions에서 접근 불가
**해결:** S3 Backend 사용 (현재 구현됨)

### 2. 리소스 네이밍 불일치 ✅ (해결됨)
**증상:** Makefile로 삭제 시 리소스를 못 찾음
**원인:** Terraform이 `_` → `-` 변환, Makefile은 그대로 사용
**해결:** Makefile에 `PROJECT_NAME_NORMALIZED` 추가, deploy.yml에 `PROJECT_NAME` 환경 변수 추가

### 3. Push 시 자동 배포되는 문제 ✅ (해결됨)
**증상:** 코드 push할 때마다 AWS 리소스 생성
**원인:** deploy.yml에 인프라 체크 로직 없음
**해결:** `check-infrastructure` job 추가

### 4. ECS Service 삭제 실패 ✅ (해결됨)
**증상:** terraform destroy 시 ECS Service 삭제 타임아웃
**원인:** ECS Service의 desired_count가 계속 변경됨
**해결:** lifecycle 정책 추가
```hcl
lifecycle {
  ignore_changes = [desired_count]
}
```

### 5. Docker 플랫폼 호환성 ✅ (해결됨 - 2025-10-23)
**증상:** `exec format error` - ECS Task가 계속 실패
**원인:** ARM64 이미지가 ECS Fargate(x86_64)에서 실행 안 됨
**해결:** Docker Buildx 사용 + `--platform linux/amd64`

### 6. HTTPS 리다이렉트 문제 ✅ (해결됨 - 2025-10-23)
**증상:** demo 환경에서 HTTPS로 리다이렉트되어 접속 불가
**원인:** `SECURE_SSL_REDIRECT=True`가 모든 환경에 적용됨
**해결:** `ENVIRONMENT` 변수로 prod 환경에서만 HTTPS 강제

### 7. Django Admin Static 파일 문제 ✅ (해결됨 - 2025-10-23)
**증상:** Admin 페이지가 CSS/JS 없이 깨져서 표시됨
**원인:** Static 파일 서빙 설정 없음
**해결:** WhiteNoise 추가 + Dockerfile에서 `collectstatic` 실행

---

## 참고 자료

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [AWS ECS Fargate](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [GitHub Actions](https://docs.github.com/en/actions)
- [Django 5.2 문서](https://docs.djangoproject.com/en/5.2/)
