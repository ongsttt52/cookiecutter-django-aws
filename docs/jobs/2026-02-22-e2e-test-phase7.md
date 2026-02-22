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

## 3단계: Terraform 검증 (미진행)

- [ ] 케이스 A: `terraform init -backend=false` + `terraform validate`
- [ ] 케이스 B: `terraform init -backend=false` + `terraform validate`
- [ ] `terraform plan` 리소스 수 확인
- [ ] `use_frontend=no`일 때 frontend 리소스 plan에 없는지 확인

---

## 4단계: AWS 실제 배포 테스트 (미진행)

- [ ] `make init` → GitHub 레포 생성 + Secrets 설정
- [ ] `create-infra.yml` → Terraform apply 성공 (34개+ 리소스)
- [ ] `deploy.yml` → Docker 빌드 + ECR push + ECS 배포 성공
- [ ] ALB 라우팅: `/api/health/`, `/api/admin/`, `/api/docs/`, `/`
- [ ] `destroy.yml` → Terraform destroy 성공 + 리소스 전체 삭제 확인

---

## 변경 파일 목록

| 파일 | 변경 유형 |
|------|-----------|
| `hooks/post_gen_project.py` | `remove_file()` 함수 추가, celery.py 삭제 로직 추가 |
