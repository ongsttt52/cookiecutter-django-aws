# Phase A 코드 리뷰 — 인프라/배포 레이어를 언어에서 분리

> **리뷰 일시**: 2026-03-14
> **리뷰 대상**: feat/infra-only-script — 8개 커밋, 16개 파일
> **브랜치**: feat/infra-only-script
> **리뷰어**: Claude Opus 4.6

---

## 커밋 요약

| # | 커밋 | 설명 | 주요 파일 |
|---|------|------|-----------|
| 1 | `b2ff73a` | cookiecutter.json에 backend_stack, container_port, health_check_path 추가 | 2 |
| 2 | `bf87064` | Terraform variables.tf에서 Django 전용 변수 분리 | 1 |
| 3 | `d8abf14` | ecs.tf 환경변수 동적 조합 + alb.tf 헬스체크 변수화 | 2 |
| 4 | `fb9344f` | ec2.tf + user-data.sh에서 Django 전용 변수 분리 | 2 |
| 5 | `643af3a` | GitHub Actions 워크플로우에서 Django 전용 코드 분리 | 4 |
| 6 | `8243a64` | 스크립트에서 Django 전용 코드 분리 및 변수화 | 4 |
| 7 | `0e3d874` | deploy.yml/deploy-ec2.yml Jinja2 raw/endraw 블록 균형 수정 | 2 |
| 8 | `99cc89c` | 코드 리뷰 지적사항 수정 (C1, H1, H3, M1, M5, L2) | 5 |

---

## 이슈 목록

### C (Critical) — 수정 완료

| ID | 파일 | 내용 | 상태 |
|----|------|------|------|
| C-1 | `deploy.yml` | `build-frontend`의 `needs`에 `quality`가 조건부 래핑 없이 하드코딩 → `backend_stack != "django"` AND `use_frontend == "yes"` 시 워크플로우 실패 | **수정됨** |

### H (High) — 수정 완료

| ID | 파일 | 내용 | 상태 |
|----|------|------|------|
| H-1 | `infra-only.sh` | `DJANGO_SUPERUSER_PASSWORD`가 `required_secrets`에 누락 → `backend_stack == "django"`일 때 시크릿 미설정으로 ECS 컨테이너 기동 실패 가능 | **수정됨** |
| H-2 | `deploy.yml`, `deploy-ec2.yml` | Jinja2 `{% raw %}`/`{% endraw %}` 블록 불균형으로 cookiecutter 렌더링 시 `TemplateSyntaxError` 발생 | **수정됨** (커밋 7) |
| H-3 | `infra-only.sh` | `CONTAINER_PORT` 입력에 숫자 및 범위(1-65535) 유효성 검사 누락 → 잘못된 포트로 Terraform apply 실패 가능 | **수정됨** |

### M (Medium) — 수정 완료

| ID | 파일 | 내용 | 상태 |
|----|------|------|------|
| M-1 | `Makefile` | `dev` 타겟의 docker-compose 포트가 `8000:8000` 하드코딩 → `container_port` 변수 사용해야 함 | **수정됨** |
| M-2 | `ecs.tf` | `locals` 블록의 `stack_env`에서 Django superuser 환경변수가 `use_celery`/`use_websocket` 조건과 무관하게 항상 포함됨 | 미수정 — Django superuser는 Celery/WebSocket과 무관한 기능이므로 현재 동작이 올바름 |
| M-3 | `variables.tf` | `app_env_vars` 변수의 `type = list(object({name = string, value = string}))` — sensitive 값에 대한 고려 없음 | 미수정 — Phase B에서 `sensitive_env_vars` 별도 변수 추가 예정. 현재는 Terraform 상태에만 저장됨 |
| M-4 | `deploy.sh` | 새 변수(`backend_stack`, `container_port`, `health_check_path`)의 cookiecutter 전달에서 따옴표 처리가 다른 기존 변수와 불일치 | 미수정 — 기존 패턴과 동일하게 작성됨. 향후 일괄 정리 시 통일 |
| M-5 | `infra-only.sh` | `HEALTH_CHECK_PATH` 입력에 "/" 시작 검증 누락 → `/`로 시작하지 않는 경로 입력 시 URL 조합 오류 | **수정됨** |

### L (Low) — 미수정

| ID | 파일 | 내용 |
|----|------|------|
| L-1 | `ecs.tf` | `awslogs-stream-prefix`가 `"{{cookiecutter.backend_stack}}"` — Phase B에서 멀티 스택 시 로그 그룹 분리 필요 |
| L-2 | `infra-only.sh` | 요약 출력에서 `ADMIN_URL` 미표시 → Django일 때 `/admin/` URL 안내 누락 | **수정됨** |
| L-3 | `common.sh` | `verify_endpoint()`의 `health_path` 기본값이 함수 시그니처와 호출부 모두에 존재 — 중복 기본값 |
| L-4 | `variables.tf` | `app_secret_key`의 description이 "Application secret key" — 어떤 용도(JWT signing, session 등)인지 불명확 |

---

## 아키텍처 평가

### locals 기반 환경변수 동적 조합

`ecs.tf`에서 `common_env` + `stack_env` + `var.app_env_vars`를 `concat()`으로 조합하는 방식은 확장성이 좋습니다. Phase B에서 FastAPI 등 새 스택 추가 시 `stack_env` 블록만 분기하면 되며, `common_env`와 `app_env_vars`는 공유됩니다. `DATABASE_URL` 등 Terraform 리소스 참조가 필요한 값은 tfvars로 분리할 수 없으므로 locals가 올바른 선택입니다.

### cookiecutter 조건부 분기 전략

`{% if cookiecutter.backend_stack == "django" %}` 조건부로 Django 전용 코드를 격리하되, 기본값이 `"django"`이므로 렌더링 결과는 기존과 동일합니다. Phase A 전/후 diff 검증에서 기능적 차이가 없음을 확인했습니다. 다만, 조건부 코드가 16개 파일에 분산되어 있어 Phase B에서 새 스택 추가 시 누락 위험이 있으므로, 체크리스트 문서화가 필요합니다.

### raw/endraw 블록 관리

GitHub Actions 워크플로우에서 `${{ }}` 구문과 cookiecutter `{% %}` 구문이 공존하여 `{% raw %}`/`{% endraw %}` 블록 관리가 복잡합니다. 커밋 7에서 수정한 것처럼, cookiecutter 조건부 삽입 시 raw/endraw 블록의 균형을 반드시 검증해야 합니다. 향후 CI에 렌더링 테스트를 추가하면 이런 문제를 조기에 감지할 수 있습니다.

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

## 총평

Django 전용 하드코딩을 cookiecutter 조건부로 격리하여 멀티 스택 확장의 기반을 마련. Critical 1건(build-frontend needs 누락), High 3건(시크릿 누락, raw/endraw 불균형, 포트 검증 누락)을 포함한 주요 이슈를 모두 수정 완료. 특히 H-2(raw/endraw 불균형)는 Jinja2 + GitHub Actions `${{ }}` 혼합 사용의 복잡성에서 기인하며, 향후 CI 렌더링 테스트 자동화로 예방 가능. 16개 파일 변경에도 불구하고 기존 Django 기본값 사용 시 렌더링 결과가 동일함을 검증으로 확인하여 하위 호환성을 보장.
