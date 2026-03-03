# Phase 11 코드 리뷰 — infra-only.sh + 공통 함수 추출

> **리뷰 일시**: 2026-03-03
> **리뷰 대상**: PR #10 (feat/infra-only-script) — 5개 커밋, 3개 파일
> **브랜치**: feat/infra-only-script → dev
> **리뷰어**: Claude Opus 4.6

---

## 커밋 요약

| # | 커밋 | 설명 | 파일 | 줄 |
|---|------|------|------|----|
| 1 | `54c032b` | lib/common.sh 생성 — 공통 함수 추출 | 1 | +222 |
| 2 | `ff9865f` | deploy.sh 리팩토링 — source로 대체 | 1 | +6, -192 |
| 3 | `678830d` | infra-only.sh 작성 | 1 | +426 |
| 4 | `96f1faf` | PROGRESS.md Phase 11 추가 | 1 | +46, -1 |
| 5 | `b807f8a` | 코드 리뷰 지적사항 수정 (C1, H1~H3) | 3 | +20, -4 |

---

## 이슈 목록

### C (Critical) — 수정 완료

| ID | 파일 | 내용 | 상태 |
|----|------|------|------|
| C-1 | `lib/common.sh` | sed 치환에 사용되는 사용자 입력 버킷명 미검증 → S3 명명 규칙 검증 추가 | **수정됨** |

### H (High) — 수정 완료

| ID | 파일 | 내용 | 상태 |
|----|------|------|------|
| H-1 | `infra-only.sh` | Makefile 파싱 값 미검증 → PROJECT_SLUG, AWS_REGION 허용 문자 검증 추가 | **수정됨** |
| H-2 | `infra-only.sh` | `gh repo view` 디렉토리 불일치 → remote URL 기준 조회로 수정 | **수정됨** |
| H-3 | `deploy.sh` | do_verify_endpoint에서 `cd ..` 사용 → `cd "$PROJECT_DIR"` 절대 경로로 수정 | **수정됨** |

### M (Medium) — 미수정 (기존 이슈 또는 낮은 위험도)

| ID | 파일 | 내용 | 비고 |
|----|------|------|------|
| M-1 | `lib/common.sh` | `create-bucket` 성공 판단에 `"Location"` 문자열 grep 사용 — AWS CLI 버전 의존 | deploy.sh에서 이관한 기존 코드, 종료 코드 기반으로 전환 권장 |
| M-2 | `lib/common.sh` | `trigger_and_wait_workflow` race condition — 동시 실행 시 잘못된 run_id 추적 가능 | gh CLI 한계, 시간 필터링으로 개선 가능하나 현재 사용 패턴에서는 저위험 |
| M-3 | `infra-only.sh` | `validate_secrets`가 즉시 exit — `validate_project`의 에러 카운터 패턴과 불일치 | 실용적으로는 secrets 누락 시 즉시 중단이 합리적 |
| M-4 | `infra-only.sh` | `do_verify_endpoint`의 cd 복원이 서브셸 미사용 | infra-only.sh에서는 `cd "$PROJECT_DIR"`로 복원하므로 저위험 |

### L (Low) — 미수정

| ID | 파일 | 내용 |
|----|------|------|
| L-1 | `lib/common.sh` | `log_*` 함수에서 `$*` 미인용 — 글로빙 패턴 포함 시 예상치 못한 확장 가능 |
| L-2 | `lib/common.sh` | ANSI 색상이 비터미널 환경에서 그대로 출력 — `[ -t 1 ]` 체크 권장 |

---

## 아키텍처 평가

### 공통 함수 추출 전략

`lib/common.sh`로 추출한 함수 선정은 적절합니다:
- **로그 유틸리티**: 모든 스크립트에서 공통으로 사용
- **ensure_state_bucket**: deploy.sh, infra-only.sh 모두에서 필요
- **trigger_and_wait_workflow**: 워크플로우 트리거 패턴 동일
- **verify_endpoint**: 헬스체크 로직 동일

URL 탐색 로직(Terraform output 조회)은 deploy.sh 전용이므로 `do_verify_endpoint` 래퍼로 분리한 것이 올바른 판단입니다.

### infra-only.sh 설계

Makefile 파싱으로 프로젝트 설정을 감지하는 방식은 cookiecutter 렌더링 시 하드코딩되는 값을 활용하므로 안정적입니다. 배포 모드 감지(`ecs.tf` / `ec2.tf`)도 파일 존재 여부 기반이라 간단하고 명확합니다.

---

## 총평

기존 `deploy.sh`의 리팩토링과 `infra-only.sh` 추가가 깔끔하게 수행됨. Critical/High 이슈는 모두 수정 완료. Medium 이슈는 기존 코드에서 이관된 것이거나 현재 사용 패턴에서 저위험이므로 향후 개선 대상.
