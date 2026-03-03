# Phase 11: infra-only.sh + 공통 함수 추출

> **작업일**: 2026-03-03
> **브랜치**: `feat/infra-only-script`
> **PR**: [#10](https://github.com/ongsttt52/cookiecutter-django-aws/pull/10)

---

## 배경

`deploy.sh`는 cookiecutter 렌더링부터 배포까지 전체 플로우(Step 0~9)를 수행하지만, 이미 개발이 진행된 프로젝트에서는 인프라 생성만 필요한 경우가 있음. 기존에는 `make setup-secrets` → GitHub Actions에서 수동으로 `Create AWS Infrastructure` 실행 → 대기 → 확인을 직접 수행해야 했음.

`infra-only.sh`로 이 과정을 하나의 스크립트로 자동화.

---

## 수행한 작업

### 작업 1: lib/common.sh — 공통 함수 추출

deploy.sh에서 4개 함수 그룹을 추출하여 `lib/common.sh` 생성:

| 함수 | 용도 |
|------|------|
| 색상 변수 + `log_info/success/warn/error/step` | 로그 유틸리티 |
| `ensure_state_bucket` | Terraform state S3 버킷 생성/확인 |
| `trigger_and_wait_workflow` | GitHub Actions 워크플로우 트리거 + 완료 대기 |
| `verify_endpoint` | /api/health/ 헬스체크 |

### 작업 2: deploy.sh 리팩토링

- 상단에 `source "$SCRIPT_DIR/lib/common.sh"` 추가
- 추출된 함수 정의 제거 (192줄 삭감)
- `verify_endpoint` → `do_verify_endpoint` 래퍼로 변경 (URL 탐색 로직은 deploy.sh 전용)
- 동작은 완전히 동일하게 유지

### 작업 3: infra-only.sh 작성

7단계 실행 흐름:

```
Step 0: Prerequisites Check (aws, gh, git)
Step 1: Detect Project Config (Makefile 파싱)
Step 2: Validate (GitHub repo, Secrets, terraform/, push 상태)
Step 3: Ensure Terraform State Bucket
Step 4: Create Infrastructure (create-infra.yml 트리거)
Step 5: (선택) Deploy Application
Step 6: Verify Endpoint
Step 7: Summary
```

주요 기능:
- Makefile 파싱으로 `PROJECT_SLUG`, `AWS_REGION`, `TF_STATE_BUCKET` 자동 감지
- `terraform/ecs.tf` / `ec2.tf` 존재 여부로 배포 모드 자동 판별
- GitHub Secrets 검증 (EC2 모드는 SSH 키 추가 확인)
- terraform/ 로컬 변경 미push 시 경고
- `--skip-deploy`, `--no-input` 옵션

### 작업 4: 코드 리뷰 지적사항 수정

| 심각도 | 내용 |
|--------|------|
| C-1 | 버킷명 사용자 입력에 S3 명명 규칙 검증 추가 |
| H-1 | Makefile 파싱 값 허용 문자 검증 추가 |
| H-2 | `gh repo view` 디렉토리 기준 수정 |
| H-3 | `cd ..` → `cd "$PROJECT_DIR"` 절대 경로 복원 |

---

## 수정/생성 파일

| 유형 | 파일 |
|------|------|
| 신규 | `lib/common.sh` (222줄) |
| 신규 | `infra-only.sh` (426줄) |
| 수정 | `deploy.sh` (+6줄, -192줄) |
| 수정 | `PROGRESS.md` |
| 신규 | `docs/reviews/2026-03-03-pr10-infra-only-review.md` |
| 신규 | `docs/jobs/2026-03-03-phase11-infra-only.md` |

---

## 검증 결과

| 항목 | 결과 |
|------|------|
| `deploy.sh --help` | 기존과 동일한 도움말 출력 |
| `infra-only.sh --help` | 도움말 정상 출력 |
| Makefile 없는 디렉토리에서 실행 | 적절한 에러 메시지 출력 |
| 코드 리뷰 | C/H 이슈 4건 수정 완료 |
