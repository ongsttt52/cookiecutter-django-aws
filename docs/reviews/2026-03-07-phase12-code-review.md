# Phase 12 코드 리뷰 — infra-only.sh 비-cookiecutter 프로젝트 지원 확장

> **리뷰 일시**: 2026-03-07
> **리뷰 대상**: feat/infra-only-script — 2개 커밋, 2개 파일
> **브랜치**: feat/infra-only-script
> **리뷰어**: Claude Opus 4.6

---

## 커밋 요약

| # | 커밋 | 설명 | 파일 | 줄 |
|---|------|------|------|----|
| 1 | `7b399d6` | infra-only.sh 비-cookiecutter 프로젝트 지원 확장 | 2 | +417, -151 |
| 2 | `bf840ed` | 코드 리뷰 지적사항 수정 (C1, C2, H2, H4, M5, M6) | 1 | +109, -102 |

---

## 이슈 목록

### C (Critical) — 수정 완료

| ID | 파일 | 내용 | 상태 |
|----|------|------|------|
| C-1 | `infra-only.sh` | AWS 자격 증명이 `--body`로 전달 시 `ps aux` 프로세스 목록에 노출됨 → stdin 파이프로 전환 | **수정됨** |
| C-2 | `infra-only.sh` | `collect_infra_inputs()` 재귀 호출 시 무한 재귀 위험 → while 루프로 변경 | **수정됨** |

### H (High) — 수정 완료

| ID | 파일 | 내용 | 상태 |
|----|------|------|------|
| H-1 | `infra-only.sh` | `RENDER_TMPDIR` 퍼미션 미설정 → `chmod 700` 추가 | **수정됨** (H4와 함께) |
| H-2 | `infra-only.sh` | `Makefile.bak`, workflow `.bak` 재실행 시 원본 백업 덮어쓰기 → 타임스탬프 기반으로 통일 | **수정됨** |
| H-3 | `infra-only.sh` | `deploy.sh`와 slug 검증 로직 불일치 (infra-only에만 검증 존재) | 미수정 — `infra-only.sh`의 개선이므로 `deploy.sh` 동기화는 별도 작업 |
| H-4 | `infra-only.sh` | 렌더링 실패 시 terraform/ 이미 mv된 상태로 프로젝트 손상 → 렌더링을 백업보다 먼저 수행 | **수정됨** |

### M (Medium) — 일부 수정

| ID | 파일 | 내용 | 상태 |
|----|------|------|------|
| M-1 | `infra-only.sh` | `git push` 실패 시 의미 있는 에러 메시지 없음 | 미수정 — `set -e`가 잡으며, push 실패는 드문 케이스 |
| M-2 | `infra-only.sh` | `gh repo create`에서 `$visibility` 따옴표 미처리 (SC2086) | 미수정 — `deploy.sh`와 동일한 패턴 유지 |
| M-3 | `infra-only.sh` | `DEPLOY_MODE`가 `AWS_DEPLOYMENT`의 단순 복사본 — 변수 이중화 | 미수정 — `deploy.sh`의 `AWS_DEPLOYMENT` vs `infra-only.sh`의 `DEPLOY_MODE` 네이밍 차이. 향후 통일 권장 |
| M-4 | `infra-only.sh` | `terraform init -backend=false` + `terraform output`은 로컬 state 없으면 항상 빈 값 반환 | 미수정 — `deploy.sh`에서 이관한 기존 코드. GitHub Actions 로그에서 URL 가져오는 방식으로 개선 가능 |
| M-5 | `infra-only.sh` | `.env.example` git add 로직의 불필요한 분기 처리 → 단순화 | **수정됨** |
| M-6 | `infra-only.sh` | cookiecutter 잔여 변수 검증이 `terraform/`만 대상 → workflows/ + Makefile로 확대 | **수정됨** |

### L (Low) — 미수정

| ID | 파일 | 내용 |
|----|------|------|
| L-1 | `infra-only.sh` | `check_prerequisites()`에서 `terraform` 검증 누락 — `do_verify_endpoint()`에서 terraform 사용 |
| L-2 | `infra-only.sh` | `log_warn` 사용 기준이 `deploy.sh`와 다름 (infra-only만 적극 활용) |
| L-3 | `infra-only.sh` | `--help`에 `--no-input`의 구체적 기본값 미명시 |
| L-4 | `infra-only.sh` | `main()` 진입 전 `echo -e "${BOLD}"` — `common.sh` source 실패 시 깨진 출력 |
| L-5 | `infra-only.sh` | 자동 커밋 메시지에 body 없음 (어떤 파일이 추가되었는지 불명확) |

---

## 아키텍처 평가

### 렌더링 → 추출 방식

cookiecutter 렌더링 후 인프라 파일만 복사하는 방식은 `post_gen_project.py`의 ECS/EC2 파일 정리 로직을 재사용할 수 있어 유지보수 부담이 적습니다. sed 치환으로 직접 구현할 경우 `post_gen_project.py`와 동기화해야 하는 부담이 생기므로 올바른 결정입니다.

### 렌더링 먼저, 백업 후

H-4 수정으로 렌더링을 백업보다 먼저 수행하게 변경. 렌더링 실패 시 프로젝트 디렉토리가 손상되지 않아 안전합니다. 기존 순서(백업 → 렌더링)는 `set -e`에 의해 스크립트가 종료되면 terraform/이 없는 상태가 되는 문제가 있었습니다.

### Secret 전달 방식

C-1 수정으로 `gh secret set --body "$value"` 대신 `echo "$value" | gh secret set`을 사용. `--body`는 프로세스 인자로 전달되어 `/proc/*/cmdline`이나 `ps aux`에 노출되지만, 파이프는 프로세스 목록에 표시되지 않습니다.

---

## 총평

기존 `infra-only.sh`의 Makefile 의존성을 완전히 제거하여 비-cookiecutter 프로젝트에서도 사용 가능하게 확장. Critical 2건, High 2건을 포함한 주요 보안/안정성 이슈를 수정 완료. Medium 이슈 중 M-3(변수 이중화), M-4(terraform output 무의미)는 `deploy.sh`와의 통합적인 리팩토링 시 해결 권장.
