# Phase A: 인프라/배포 레이어를 언어에서 분리

> **작업일**: 2026-03-14
> **브랜치**: `feat/infra-only-script`

---

## 배경

cookiecutter-django-aws 템플릿의 모든 워크플로우와 Terraform 파일에 Django 전용 코드가 하드코딩되어 있어, 다른 백엔드 스택(FastAPI, Spring Boot) 지원이 불가능했음. Phase A는 인프라/배포 레이어에서 Django 의존성을 분리하여, Phase B(멀티 스택 템플릿)의 기반을 마련하는 작업.

**분리 대상:**
- `deploy.yml` quality job: Django 전용 lint/test(ruff, black, pytest) 하드코딩
- `ecs.tf`: Django 환경변수(DATABASE_URL, SECRET_KEY, DJANGO_SUPERUSER_*) 직접 정의
- `alb.tf`: 헬스체크 경로 `/api/health/` 하드코딩
- `create-infra.yml`/`destroy.yml`: `-var="django_secret_key=..."` 하드코딩
- `deploy-ec2.yml`: `python manage.py migrate/collectstatic` 하드코딩
- `lib/common.sh`: `verify_endpoint`에 `/api/health/` 하드코딩

---

## 설계 결정

| 결정 | 선택 | 근거 |
|------|------|------|
| deploy.yml 분리 전략 | 조건부 분기 (3-파일 분리는 Phase B로 미룸) | `needs` 의존성 복잡도 회피. Django만 지원하는 현재 단계에서 최소 변경 |
| Terraform 변수명 | `django_secret_key` → `app_secret_key` | Terraform variable만 rename, GitHub Secret(`DJANGO_SECRET_KEY`)은 유지 |
| ECS 환경변수 | locals 기반 동적 조합 | `DATABASE_URL` 등 Terraform 리소스 참조가 필요하여 tfvars로 분리 불가 |
| `backend_stack` | 고정 문자열 `"django"` | Phase B에서 배열로 확장 예정 |

---

## 수행한 작업

### 커밋 1: cookiecutter.json 확장 + post_gen_project.py 업데이트
- `cookiecutter.json`에 `backend_stack("django")`, `container_port("8000")`, `health_check_path("/api/health/")` 추가
- `post_gen_project.py`에 `backend_stack` 변수 읽기 추가 (Phase B 준비)

### 커밋 2: Terraform variables.tf 리팩토링
- `django_secret_key` → `app_secret_key` rename (description도 스택 중립적으로)
- `django_superuser_email`/`password`를 `{% if cookiecutter.backend_stack == "django" %}` 조건부로 래핑
- `container_port`, `health_check_path`, `app_env_vars` 변수 추가

### 커밋 3: ecs.tf 환경변수 동적 조합 + alb.tf 헬스체크 변수화
- `ecs.tf`에 `locals` 블록으로 `common_env`/`stack_env`/`backend_env` 동적 조합
- container name `"django"` → `"{{cookiecutter.backend_stack}}"`, containerPort를 `var.container_port`로
- `alb.tf` 헬스체크 경로를 `var.health_check_path`, 포트를 `var.container_port`로

### 커밋 4: ec2.tf + user-data.sh 리팩토링
- `django_secret_key` → `app_secret_key`, Django superuser 변수를 조건부로 래핑

### 커밋 5: GitHub Actions 워크플로우 리팩토링
- `create-infra.yml`/`destroy.yml`: `app_secret_key` 매핑, Django superuser 조건부
- `deploy.yml`/`deploy-ec2.yml`: quality job 조건부 래핑, health check URL 변수화, migrate/collectstatic 조건부

### 커밋 6: 스크립트 업데이트
- `lib/common.sh`: `verify_endpoint`에 `health_path` 파라미터 추가
- `infra-only.sh`: `BACKEND_STACK`/`CONTAINER_PORT`/`HEALTH_CHECK_PATH` 수집 및 전달
- `deploy.sh`: cookiecutter 렌더링에 새 변수 전달
- `Makefile`: `DJANGO_SUPERUSER_PASSWORD` 프롬프트 조건부 래핑

### 코드 리뷰 수정
- C1: deploy.yml build-frontend의 needs에 quality 조건부 래핑
- H1: infra-only.sh에 DJANGO_SUPERUSER_PASSWORD 시크릿 설정 로직 추가
- H3: CONTAINER_PORT 입력에 1-65535 범위 유효성 검사
- M1: Makefile dev 타겟의 포트를 `{{cookiecutter.container_port}}`로 변경
- M5: HEALTH_CHECK_PATH 입력에 "/" 시작 검증

---

## 검증 결과

| 테스트 | 결과 |
|--------|------|
| ECS + 풀옵션 (celery + websocket + frontend) 렌더링 | PASS |
| ECS + 최소 (backend only) 렌더링 | PASS |
| EC2 + 풀옵션 렌더링 | PASS |
| EC2 + 최소 렌더링 | PASS |
| Cookiecutter 잔여 변수 확인 (4개 케이스) | 잔여 없음 |
| Terraform validate (ECS) | Success |
| Terraform validate (EC2) | Success |
| YAML syntax (ECS 워크플로우) | PASS |
| YAML syntax (EC2 워크플로우) | PASS |

---

## 수정 파일 (16개)

| 파일 | 변경 유형 |
|------|----------|
| `cookiecutter.json` | 수정 |
| `hooks/post_gen_project.py` | 수정 |
| `{{cc}}/terraform/variables.tf` | 수정 |
| `{{cc}}/terraform/ecs.tf` | 수정 |
| `{{cc}}/terraform/alb.tf` | 수정 |
| `{{cc}}/terraform/ec2.tf` | 수정 |
| `{{cc}}/terraform/user-data.sh` | 수정 |
| `{{cc}}/.github/workflows/create-infra.yml` | 수정 |
| `{{cc}}/.github/workflows/destroy.yml` | 수정 |
| `{{cc}}/.github/workflows/deploy.yml` | 수정 |
| `{{cc}}/.github/workflows/deploy-ec2.yml` | 수정 |
| `lib/common.sh` | 수정 |
| `infra-only.sh` | 수정 |
| `deploy.sh` | 수정 |
| `{{cc}}/Makefile` | 수정 |
| `PROGRESS.md` | 수정 |
