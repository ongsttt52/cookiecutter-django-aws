# Phase 12: infra-only.sh — 비-cookiecutter 프로젝트 지원 확장

> **작업일**: 2026-03-07
> **브랜치**: `feat/infra-only-script`

---

## 배경

기존 `infra-only.sh`는 cookiecutter로 렌더링된 프로젝트만 지원 (Makefile 파싱으로 `PROJECT_SLUG`, `AWS_REGION` 등을 감지). 사용자가 Java, Go 등 비-cookiecutter 프로젝트에서도 AWS 인프라를 생성하고 싶은 요구가 있었음.

Makefile이 없는 프로젝트에서 실행하면 에러로 종료되는 제한을 해소하기 위해, cookiecutter 템플릿을 렌더링하여 인프라 파일만 추출·복사하는 방식으로 재설계.

---

## 수행한 작업

### 작업 1: infra-only.sh 전면 수정

#### 기존 흐름 (7단계)
```
Step 0: Prerequisites (aws, gh, git)
Step 1: Detect Config (Makefile 파싱)
Step 2: Validate (repo, secrets, terraform/)
Step 3: Ensure State Bucket
Step 4: Create Infrastructure
Step 5: Deploy Application
Step 6: Verify Endpoint
Step 7: Summary
```

#### 신규 흐름 (10단계)
```
Step 0: Prerequisites (aws, gh, git, cookiecutter)
Step 1: Collect Config (프롬프트 / --no-input 기본값)
Step 2: Render & Extract (렌더링 → 백업 → 복사)
Step 3: Setup Git & GitHub (init, remote, secrets)
Step 4: Commit & Push (인프라 파일)
Step 5: Ensure State Bucket
Step 6: Create Infrastructure
Step 7: Deploy Application
Step 8: Verify Endpoint
Step 9: Summary
```

#### 삭제된 함수
- `detect_project_config()` — Makefile 파싱 의존
- `validate_project()` — 사전 상태 검증 (렌더링 방식에서는 불필요)
- `validate_secrets()` — `setup_git_and_github()`에 통합

#### 신규 함수

| 함수 | 용도 |
|------|------|
| `collect_infra_inputs()` | 프롬프트로 설정 수집 (PROJECT_NAME, AWS_DEPLOYMENT, REGION 등) |
| `render_and_extract()` | cookiecutter 렌더링 → 기존 파일 백업 → 인프라 파일 복사 |
| `setup_git_and_github()` | git init, GitHub repo 생성, Secrets 설정 (멱등) |
| `commit_and_push_infra()` | 인프라 파일 stage, 커밋, 푸시 |

### 작업 2: 코드 리뷰 지적사항 수정

| 심각도 | ID | 내용 |
|--------|----|------|
| C | C1 | AWS 자격 증명을 `--body` 대신 stdin 파이프로 전달 (프로세스 목록 노출 방지) |
| C | C2 | `collect_infra_inputs()` 재귀 호출을 while 루프로 변경 (무한 재귀 방지) |
| H | H2 | Makefile/workflow 백업을 타임스탬프 기반으로 통일 (재실행 시 덮어쓰기 방지) |
| H | H4 | cookiecutter 렌더링을 백업보다 먼저 수행 (실패 시 프로젝트 디렉토리 무변경 보장) |
| M | M5 | `.env.example` git add 로직 단순화 (불필요한 분기 제거) |
| M | M6 | cookiecutter 잔여 변수 검증 범위를 terraform/ + workflows/ + Makefile로 확대 |

### 작업 3: PROGRESS.md 업데이트

Phase 12 작업 내용을 PROGRESS.md에 반영.

---

## 주요 설계 결정

| 결정 | 근거 |
|------|------|
| cookiecutter 렌더링 후 복사 | `post_gen_project.py`가 ECS/EC2 파일 정리를 자동 수행. sed 치환 중복 구현 불필요 |
| 항상 재생성 (모드 분기 없음) | 기존 파일은 백업 후 덮어쓰기. 설정 변경(ECS↔EC2) 시 재실행으로 해결 |
| Makefile 파싱 없음 | 프롬프트 입력 또는 기본값만 사용. 비-cookiecutter 프로젝트에서도 동작 |
| 렌더링 먼저, 백업 후 | cookiecutter 렌더링 실패 시 프로젝트 디렉토리를 손상시키지 않음 |
| `trap EXIT` 임시 디렉토리 | 정상/비정상 종료 모두에서 cleanup 보장 |
| stdin 파이프 secret 전달 | `gh secret set --body`는 ps aux에 노출 가능. 파이프는 프로세스 목록에 안 보임 |

---

## 수정/생성 파일

| 유형 | 파일 |
|------|------|
| 수정 | `infra-only.sh` (전면 수정, 439줄 → 665줄) |
| 수정 | `PROGRESS.md` |
| 신규 | `docs/jobs/2026-03-07-phase12-infra-only-extension.md` |
| 신규 | `docs/reviews/2026-03-07-phase12-code-review.md` |

---

## 검증 결과

| 항목 | 결과 |
|------|------|
| `bash -n infra-only.sh` | Syntax OK |
| `infra-only.sh --help` | 새 모드 설명 + 3개 예시 포함 |
| 코드 리뷰 | C 2건, H 2건, M 2건 수정 완료 |
