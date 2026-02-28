# Phase 7: E2E 배포 테스트

> **작업일**: 2026-02-22
> **브랜치**: `dev`
> **선행 작업**: Phase 6 코드 리뷰 수정 완료 (PR #3 머지)

---

## 배경

Phase 4~6에서 Backend 설정, Frontend 템플릿 통합, 코드 리뷰 수정까지 많은 코드가 변경됨. 실제로 cookiecutter 렌더링 → Docker Compose → Terraform → AWS 배포까지 전 과정이 정상 동작하는지 검증 필요.

특히 M5(Terraform 네이밍 통일), H3(프론트엔드 환경변수 변경) 같은 수정은 배포 환경에서 예기치 못한 문제를 일으킬 수 있어 E2E 검증이 필수.

---

## 테스트 계획 (4단계)

| 단계 | 내용 | 비용 | 소요시간 |
|------|------|------|---------|
| 1단계 | Cookiecutter 렌더링 테스트 | 무료 | 5분 |
| 2단계 | Docker Compose 로컬 테스트 | 무료 | 15분 |
| 3단계 | Terraform validate | 무료 | 5분 |
| 4단계 | AWS 실제 배포 테스트 | ~$0.06 | 30분 |

**테스트 케이스:**
- 케이스 A (풀옵션): `use_celery=yes`, `use_websocket=yes`, `use_frontend=yes`
- 케이스 B (최소): `use_celery=no`, `use_websocket=no`, `use_frontend=no`

---

## 1단계: Cookiecutter 렌더링 테스트 ✅

### 실행 내용

```bash
# 케이스 A: 풀옵션
cookiecutter cookiecutter-django-aws/ --no-input --output-dir /tmp \
  project_name=test_full use_celery=yes use_websocket=yes use_frontend=yes

# 케이스 B: 최소
cookiecutter cookiecutter-django-aws/ --no-input --output-dir /tmp \
  project_name=test_minimal use_celery=no use_websocket=no use_frontend=no
```

### 검증 결과

| 검증 항목 | 케이스 A | 케이스 B | 결과 |
|----------|---------|---------|------|
| `{{cookiecutter.*}}` 잔여물 | 없음 | 없음 | PASS |
| `{% %}` 잔여 조건문 | 없음 | 없음 | PASS |
| frontend/ 디렉토리 | 존재 | 삭제됨 | PASS |
| package-lock.json | 생성됨 | N/A | PASS |
| celery.py | 존재 | 삭제됨 | PASS |
| docker-compose 서비스 수 | 7개 | 2개 | PASS |
| Terraform frontend 리소스 | 있음 | 없음 | PASS |
| deploy.yml frontend job | 있음 | 없음 | PASS |
| urls.py `/api` prefix | 적용됨 | 적용됨 | PASS |
| .env.example 조건부 변수 | 포함 | 없음 | PASS |
| 프로젝트명 정규화 | `test_full` → `test-full` | `test_minimal` → `test-minimal` | PASS |
| Terraform `local.project_name_normalized` 통일 | 인라인 replace 없음 | 인라인 replace 없음 | PASS |

### 발견 및 수정한 이슈

**`use_celery=no`일 때 `celery.py` 미삭제 (Phase 6.5)**

- **증상**: `use_celery=no`인데 `backend/config/celery.py`가 남아있음 (docstring만 있는 빈 파일)
- **영향**: 동작에는 영향 없음 (어디서도 import 하지 않음). 파일 정리 차원의 문제
- **수정**: `hooks/post_gen_project.py`에 `remove_file()` 헬퍼 함수 + celery.py 삭제 로직 추가

```python
def remove_file(path: str) -> None:
    """Remove a file if it exists."""
    if os.path.exists(path):
        os.remove(path)
        print(f"  Removed: {path}")

# main()에 추가
if use_celery != "yes":
    print("use_celery=no: Removing celery config...")
    remove_file(os.path.join("backend", "config", "celery.py"))
```

---

## 2단계: Docker Compose 로컬 테스트 ✅

### 케이스 A: 풀옵션

**컨테이너 상태:**

| 서비스 | 상태 | 포트 |
|--------|------|------|
| db (PostgreSQL 16) | Up (healthy) | 5432 |
| redis (Redis 7) | Up (healthy) | 6379 |
| backend (Django) | Up | 8000 |
| celery_worker | Up | — |
| celery_beat | Up | — |
| websocket (Daphne) | Up | 8001 |
| frontend (Next.js) | Up | 3000 |

**엔드포인트 검증:**

| URL | 응답 | 결과 |
|-----|------|------|
| `http://localhost:8000/api/health/` | `{"status":"healthy","database":"connected"}` | PASS |
| `http://localhost:8000/api/admin/login/` | HTTP 200 | PASS |
| `http://localhost:8000/api/docs/` | HTTP 200 (Swagger UI) | PASS |
| `http://localhost:3000/` | HTTP 200 | PASS |

**서비스 로그 확인:**
- Celery Worker: `celery@... ready.` — 정상
- Celery Beat: `beat: Starting...` — 정상
- WebSocket: `Listening on TCP address 0.0.0.0:8001` — 정상

### 케이스 B: 최소

**컨테이너 상태:**

| 서비스 | 상태 | 포트 |
|--------|------|------|
| db (PostgreSQL 16) | Up (healthy) | 5432 |
| backend (Django) | Up | 8000 |

**엔드포인트 검증:**

| URL | 응답 | 결과 |
|-----|------|------|
| `http://localhost:8000/api/health/` | `{"status":"healthy","database":"connected"}` | PASS |
| `http://localhost:8000/api/admin/login/` | HTTP 200 | PASS |
| `http://localhost:8000/api/docs/` | HTTP 200 (Swagger UI) | PASS |

### 참고사항

- 첫 실행 시 `uv sync`로 패키지 설치 발생 → Backend 시작까지 30~40초 소요 (이후 캐시됨)
- Dockerfile `--platform=linux/amd64` 경고 — ARM Mac에서의 경고로, ECS(x86)에서는 정상

---

## 3단계: Terraform 검증 ✅

**실행일**: 2026-02-27

### 실행 내용

```bash
# 케이스 A: 풀옵션
cookiecutter cookiecutter-django-aws/ --no-input --output-dir /tmp \
  project_name=test_tf_full use_celery=yes use_websocket=yes use_frontend=yes

# 케이스 B: 최소
cookiecutter cookiecutter-django-aws/ --no-input --output-dir /tmp \
  project_name=test_tf_min use_celery=no use_websocket=no use_frontend=no

# 양쪽 모두
cd /tmp/test_tf_{full,min}/terraform
terraform init -backend=false
terraform validate
```

### 검증 결과

| 검증 항목 | 케이스 A (풀옵션) | 케이스 B (최소) | 결과 |
|----------|-----------------|----------------|------|
| `terraform init -backend=false` | Successfully initialized | Successfully initialized | PASS |
| `terraform validate` | Success! The configuration is valid. | Success! The configuration is valid. | PASS |
| Terraform Provider | hashicorp/aws v5.100.0 | hashicorp/aws v5.100.0 | PASS |

### 조건부 렌더링 검증 (tf 파일 라인 수 비교)

| 파일 | 케이스 A | 케이스 B | 차이 원인 |
|------|---------|---------|----------|
| ecs.tf | 232줄 | 137줄 | frontend 서비스/태스크 제거 |
| alb.tf | 103줄 | 61줄 | frontend 리스너/타겟그룹 제거 |
| ecr.tf | 80줄 | 43줄 | frontend ECR 리포지토리 제거 |
| outputs.tf | 69줄 | 57줄 | frontend 출력 제거 |
| security.tf | 113줄 | 105줄 | frontend 보안 그룹 규칙 제거 |
| 기타 (7개 파일) | 동일 | 동일 | 변경 없음 |
| **합계** | **1010줄** | **816줄** | **-194줄 (frontend 관련)** |

### terraform plan (미진행)

- AWS credentials 없이 로컬에서 `terraform plan` 실행 불가
- 4단계(AWS 실제 배포 테스트)에서 `terraform apply` 시 리소스 수 확인 예정

### 발견된 이슈

**없음** — Phase 6에서 수정한 M5(네이밍 통일), H3(환경변수 수정) 등이 정상 반영됨

---

## 4단계: AWS 실제 배포 테스트 ✅

**실행일**: 2026-02-27

### 실행 내용

```bash
# 1. 렌더링 (풀옵션)
cookiecutter . --no-input --output-dir /tmp \
  project_name=test_e2e use_celery=yes use_websocket=yes use_frontend=yes

# 2. GitHub 레포 생성 + Secrets 설정
cd /tmp/test_e2e
cp .env.example .env  # AWS credentials 입력
make init             # → ongsttt52/test-e2e 레포 생성

# 3. 인프라 생성
gh workflow run create-infra.yml --repo ongsttt52/test-e2e

# 4. 앱 배포
gh workflow run deploy.yml --repo ongsttt52/test-e2e

# 5. 검증
curl http://<ALB_URL>/api/health/
curl http://<ALB_URL>/api/admin/
curl http://<ALB_URL>/api/docs/
curl -I http://<ALB_URL>/
```

### 검증 결과

| 엔드포인트 | 응답 | 결과 |
|-----------|------|------|
| `/api/health/` | `{"status":"healthy","database":"connected"}` | PASS |
| `/api/admin/` | HTTP 200 | PASS |
| `/api/docs/` | Swagger UI HTML 정상 반환 | PASS |
| `/` | HTTP 200 (Next.js, X-Powered-By: Next.js) | PASS |

### GitHub Actions 실행 기록

| 워크플로우 | 소요시간 | 결과 |
|-----------|----------|------|
| `create-infra.yml` | 10분 5초 | ✓ (4번째 시도) |
| `deploy.yml` | 6분 16초 | ✓ (수동 재실행) |

### 발견된 이슈 및 해결

**이슈 1: AWS credentials 플레이스홀더**
- **증상**: `create-infra.yml` 실행 시 `The security token included in the request is invalid`
- **원인**: `.env`에 `AWS_ACCESS_KEY_ID=your-aws-access-key-id` 플레이스홀더가 그대로 있었고, `make setup-secrets`가 이 값을 GitHub Secrets에 등록
- **해결**: `.env`에 실제 AWS credentials 입력 후 `make setup-secrets` 재실행
- **개선 제안**: `make init`/`make setup-secrets` 실행 시 플레이스홀더 값 감지하여 경고

**이슈 2: Terraform S3 Backend 버킷 접근 불가**
- **증상**: `terraform init` 시 `AccessDenied: Access Denied (403)`
- **원인**: `backend.tf`에 설정된 `demodev-lab-terraform-states` 버킷이 다른 AWS 계정 소유
- **해결**: 개인 버킷 `ongsttt52-terraform-states` 생성 후 `backend.tf` 수정
- **개선 제안**: `terraform_state_bucket`을 cookiecutter.json 변수로 분리하여 프로젝트 생성 시 입력 가능하게 변경

**이슈 3: deploy.yml 자동 트리거 스킵**
- **증상**: `make init` push 시 `deploy.yml`이 자동 트리거되었으나 10초 만에 완료 (실제 배포 안 됨)
- **원인**: push 시점에 인프라가 아직 생성되지 않아 `check-infrastructure` 단계에서 ECR 미발견 → 스킵
- **해결**: 인프라 생성 완료 후 `deploy.yml` 수동 재실행
- **참고**: 이건 의도된 동작 (인프라 없을 때 배포 방지)

---

## 전체 요약

| 단계 | 결과 | 소요시간 |
|------|------|---------|
| 1단계: Cookiecutter 렌더링 | ✅ PASS | 5분 |
| 2단계: Docker Compose 로컬 | ✅ PASS | 15분 |
| 3단계: Terraform 검증 | ✅ PASS | 5분 |
| 4단계: AWS 실제 배포 | ✅ PASS | 30분 |

**Phase 7 E2E 테스트 완료. 템플릿은 프로덕션 사용 가능 상태.**

---

## 변경 파일 목록

| 파일 | 변경 유형 |
|------|-----------|
| `hooks/post_gen_project.py` | `remove_file()` 함수 추가, celery.py 삭제 로직 추가 |
