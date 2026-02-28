# Phase 8 코드 리뷰 — EC2 All-in-One + deploy.sh

> **리뷰 일시**: 2026-02-28
> **리뷰 대상**: HEAD~6 (fd66b08..21865a8) — 6개 커밋, 25개 파일, +1,770줄
> **브랜치**: feat/phase8-ec2-and-deploy-script
> **리뷰어**: Claude Opus 4.6

---

## 목차

1. [커밋 요약](#1-커밋-요약)
2. [아키텍처 평가](#2-아키텍처-평가)
3. [deploy.sh 리뷰](#3-deploysh-리뷰)
4. [Terraform 리뷰](#4-terraform-리뷰)
5. [CI/CD 워크플로우 리뷰](#5-cicd-워크플로우-리뷰)
6. [Docker Compose Production 리뷰](#6-docker-compose-production-리뷰)
7. [Makefile 리뷰](#7-makefile-리뷰)
8. [post_gen_project.py 리뷰](#8-post_gen_projectpy-리뷰)
9. [ECS ↔ EC2 모드 일관성 분석](#9-ecs--ec2-모드-일관성-분석)
10. [종합 이슈 목록](#10-종합-이슈-목록)
11. [프로젝트 상태 점검](#11-프로젝트-상태-점검)
12. [권장 조치 사항](#12-권장-조치-사항)

---

## 1. 커밋 요약

| # | 커밋 | 설명 | 파일 | 줄 |
|---|------|------|------|----|
| 1 | `fd66b08` | fix: use_celery=no일 때 celery.py 삭제 | 3 | +250 |
| 2 | `2837222` | feat(A1,A3): aws_deployment 옵션 + ECS 조건부 래핑 | 8 | +15 |
| 3 | `5b8cef9` | feat(A2,A4): EC2 Terraform 인프라 | 6 | +321 |
| 4 | `641b80e` | feat(A5,A6,A7): EC2 배포 파이프라인 + post-gen 정리 | 5 | +334 |
| 5 | `8e535d6` | feat(A8): Makefile, .env.example, README EC2 지원 | 3 | +135 |
| 6 | `21865a8` | feat(B): deploy.sh 자동화 + Phase 8 문서 | 3 | +744 |

**총계**: 25개 파일, +1,770줄, -59줄

---

## 2. 아키텍처 평가

### 잘된 점

- **배포 모드 분리가 깔끔함**: `cookiecutter.json`의 `aws_deployment` 옵션 하나로 ECS/EC2 전환
- **Jinja2 조건부 래핑**: 기존 7개 ECS 파일을 수정 없이 조건문으로 감싸는 최소 침습적 접근
- **관심사 분리**: EC2 전용 파일(ec2.tf, ec2_iam.tf, ec2_security.tf)을 별도 파일로 분리
- **deploy.sh 원스텝 자동화**: 렌더링 → 배포까지 9단계 자동화는 DX 관점에서 매우 좋음

### 아쉬운 점

- **빈 .tf 파일 잔류**: post_gen_project.py에서 Terraform 파일 정리가 빠져 있어 렌더링 후 빈 파일이 남음
- **ECS/EC2 간 배포 전략 차이가 큼**: ECS는 ECR 기반 이미지 배포, EC2는 SSH+git pull — 일관성 부족
- **리버스 프록시 부재**: EC2 모드에서 Django가 포트 80에 직접 노출

---

## 3. deploy.sh 리뷰

**파일**: `deploy.sh` (541줄)
**구조**: 9단계(Step 0~9) 순차 실행

### 3.1 점수표

| 항목 | 점수 | 비고 |
|------|------|------|
| 기능 완성도 | 8/10 | 핵심 워크플로우 잘 구현 |
| 보안 | 5/10 | 자격 증명 처리 미흡 |
| 에러 핸들링 | 6/10 | 선행 조건 검사는 좋으나 중간 실패 시 복구 없음 |
| 유지보수성 | 7/10 | 함수 분리 양호, 하드코딩 다수 |
| 이식성 | 7/10 | macOS/Linux sed 분기 처리 |
| UX | 8/10 | 컬러 출력, 진행 표시, --no-input 모드 |

### 3.2 CRITICAL 이슈

#### [C1] AWS 자격 증명 sed 치환 시 특수문자 미이스케이프 (Line 223-228)

```bash
sed -i '' "s/your-aws-access-key-id/$aws_key/" .env
sed -i '' "s/your-aws-secret-access-key/$aws_secret/" .env
```

**문제**: AWS Secret Access Key에 `/`, `&`, `\` 등이 포함되면 sed가 오동작하거나 실패합니다.
**영향**: 자격 증명 설정 실패 → 이후 모든 AWS 작업 실패
**수정안**:
```bash
# sed 대신 python으로 안전하게 치환
python3 -c "
import os
with open('.env', 'r') as f:
    content = f.read()
content = content.replace('your-aws-access-key-id', os.environ['AWS_KEY'])
content = content.replace('your-aws-secret-access-key', os.environ['AWS_SECRET'])
with open('.env', 'w') as f:
    f.write(content)
os.chmod('.env', 0o600)
"
```

#### [C2] SSH 키 생성 후 권한 미설정 (Line 332-333)

```bash
ssh-keygen -t ed25519 -f "$key_path" -N "" -C "$PROJECT_SLUG-ec2"
```

**문제**: `ssh-keygen`이 생성하는 파일의 기본 권한은 umask에 의존합니다. 대부분 0600이지만 보장되지 않습니다.
**수정안**:
```bash
ssh-keygen -t ed25519 -f "$key_path" -N "" -C "$PROJECT_SLUG-ec2"
chmod 600 "$key_path"
chmod 644 "${key_path}.pub"
```

#### [C3] GitHub Secret 설정 시 CLI 인자로 비밀 전달 (Line 323-327)

```bash
gh secret set AWS_ACCESS_KEY_ID --body "$aws_key"
gh secret set AWS_SECRET_ACCESS_KEY --body "$aws_secret"
```

**문제**: `--body` 인자로 전달된 값은 프로세스 목록(`ps aux`)에 일시적으로 노출됩니다.
**수정안**:
```bash
echo "$aws_key" | gh secret set AWS_ACCESS_KEY_ID
echo "$aws_secret" | gh secret set AWS_SECRET_ACCESS_KEY
```

### 3.3 HIGH 이슈

#### [H1] EXIT 트랩 미설정 — 중간 실패 시 정리 불가 (전체)

`set -euo pipefail`로 에러 시 즉시 종료하지만, GitHub 레포 생성 후 Terraform 실패 시 생성된 레포가 고아 상태로 남습니다.

**수정안**:
```bash
cleanup() {
    if [[ "${CLEANUP_NEEDED:-false}" == "true" ]]; then
        log_warn "중간 실패 감지. 정리 방법:"
        log_warn "  gh repo delete $REPO_FULL_NAME --yes"
        log_warn "  rm -rf $PROJECT_DIR"
    fi
}
trap cleanup EXIT
```

#### [H2] Terraform output 로컬 조회 실패 (Line 441-443)

```bash
if terraform init -backend=false >/dev/null 2>&1; then
    app_url=$(terraform output -raw app_url 2>/dev/null || echo "")
fi
```

**문제**: State가 원격 S3에만 있어 `-backend=false`로 init하면 output이 비어 있습니다. 즉, `APP_URL`이 항상 빈 문자열입니다.

**수정안**: GitHub Actions 워크플로우 로그에서 파싱하거나, Terraform output을 GitHub Actions 아티팩트로 저장
```bash
# 워크플로우 로그에서 app_url 추출
APP_URL=$(gh run view "$LAST_RUN_ID" --repo "$REPO_FULL_NAME" --log 2>/dev/null \
    | grep -oP 'app_url = \K.*' || echo "")
```

#### [H3] 프로젝트명 유효성 검증 없음 (Line 154)

```bash
PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr '-' '_')
```

**문제**: `my_project@2024` 같은 입력은 AWS 리소스명, Terraform 변수명, Git 레포명 등에서 오류를 일으킵니다.

**수정안**:
```bash
validate_project_name() {
    local name="$1"
    if ! [[ "$name" =~ ^[a-z][a-z0-9_]*$ ]]; then
        log_error "유효하지 않은 프로젝트명: $name"
        log_error "소문자로 시작하고, [a-z0-9_]만 포함해야 합니다"
        exit 1
    fi
}
```

### 3.4 MEDIUM 이슈

| # | 라인 | 이슈 | 설명 |
|---|------|------|------|
| M1 | 266 | 하드코딩된 sleep 30 | 로컬 테스트 Docker 대기 시간 고정 |
| M2 | 362-378 | workflow run_id 경쟁 조건 | 워크플로우 시작 전 조회 시 빈 값 가능 |
| M3 | 405, 419 | 타임아웃 값 하드코딩 | 15분(인프라), 10분(배포) 고정 |
| M4 | 419-425 | 이중 워크플로우 시도 로직 | "Deploy Application" 실패 시 "Deploy to EC2" 시도 — 의도가 불명확 |
| M5 | 391 | `\r` 기반 진행 표시 | 일부 터미널에서 깨질 수 있음 |

### 3.5 잘한 점

- `set -euo pipefail` 사용 (Line 2)
- 선행 조건 검사 함수 `check_prerequisites()` (Line 56-91)
- `--no-input` 모드 지원으로 CI 환경 호환
- 컬러 출력 함수 체계화 (log_info, log_success, log_warn, log_error)
- Docker/GitHub/AWS 인증 상태 사전 검증

---

## 4. Terraform 리뷰

### 4.1 EC2 Terraform 파일 (신규)

#### ec2.tf (84줄)
| 항목 | 평가 |
|------|------|
| AMI 선택 | ✅ Amazon Linux 2023 최신 AMI 자동 선택 |
| 인스턴스 타입 | ✅ t3.small (demo용 적절) |
| EBS 볼륨 | ⚠️ 30GB — Docker 이미지/로그 누적 시 부족할 수 있음 (50GB 권장) |
| Elastic IP | ✅ 인스턴스 재시작 시 IP 유지 |
| CloudWatch | ⚠️ Log Group만 생성, CloudWatch Agent 미설치 |

#### ec2_iam.tf (83줄)
| 항목 | 평가 |
|------|------|
| IAM Role | ✅ EC2 Instance Profile 올바르게 구성 |
| S3 정책 | ⚠️ `s3:DeleteObject` 포함 — 침해 시 파일 삭제 가능, 최소 권한 원칙 위반 |
| CloudWatch 정책 | ✅ Logs/Metrics 쓰기 권한만 부여 |
| SSM 정책 | ✅ SSM 기본 정책 첨부 |

**수정 권장** (ec2_iam.tf, Line 38-42):
```hcl
Action = [
    "s3:PutObject",
    "s3:GetObject",
    "s3:ListBucket"
    # "s3:DeleteObject" ← 제거 권장
]
```

#### ec2_security.tf (50줄)

**CRITICAL**: SSH 전역 개방

```hcl
# Line 12-18
ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # ← 전 세계에서 SSH 접근 가능
}
```

**문제**: 브루트포스 공격, 무단 접근 위험
**수정안**: 변수로 분리하여 특정 IP만 허용
```hcl
variable "ssh_allowed_cidrs" {
    type    = list(string)
    default = ["0.0.0.0/0"]  # 배포 시 반드시 변경
}

ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
}
```

또한 **Egress 무제한** (Line 38-44):
```hcl
egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # 모든 아웃바운드 허용
}
```
demo 템플릿이므로 수용 가능하나, prod에서는 필요한 포트만 허용해야 합니다.

#### user-data.sh (60줄)

| # | 라인 | 이슈 | 심각도 |
|---|------|------|--------|
| 1 | 21 | Docker Compose 버전 `v2.27.1` 하드코딩 | MEDIUM |
| 2 | 34-54 | .env 파일 평문 저장, chmod 600 미설정 | HIGH |
| 3 | 56-60 | git clone 대기만 하고 Docker Compose 자동 시작 없음 | MEDIUM |
| 4 | — | 인스턴스 재부팅 시 Docker Compose 자동 시작 systemd 서비스 미등록 | MEDIUM |
| 5 | — | CloudWatch Agent 미설치 | LOW |

**수정안 — .env 권한**:
```bash
cat > "$APP_DIR/.env" <<'ENVEOF'
...
ENVEOF
chmod 600 "$APP_DIR/.env"
```

**수정안 — Docker Compose 자동 시작**:
```bash
cat > /etc/systemd/system/docker-compose.service <<'EOF'
[Unit]
Description=Docker Compose Application
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
WorkingDirectory=/opt/app
ExecStart=/usr/bin/docker compose -f docker-compose.prod.yml up -d
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable docker-compose.service
```

### 4.2 ECS 조건부 래핑 (기존 파일)

7개 파일 모두 `{% if cookiecutter.aws_deployment == "ecs-fargate" %}...{% endif %}`로 정상 래핑 확인:

| 파일 | 상태 |
|------|------|
| ecs.tf | ✅ |
| ecr.tf | ✅ |
| alb.tf | ✅ |
| rds.tf | ✅ |
| elasticache.tf | ✅ |
| iam.tf | ✅ |
| security.tf | ✅ |

### 4.3 outputs.tf / variables.tf

- outputs.tf: ECS/EC2 조건부 분기 ✅ 올바름
- variables.tf: `ec2_public_key` 변수 EC2 조건부 추가 ✅
- **개선 필요**: `ec2_public_key` 입력 검증 (SSH 공개 키 형식)

---

## 5. CI/CD 워크플로우 리뷰

### 5.1 deploy-ec2.yml (신규, 123줄)

| # | 라인 | 이슈 | 심각도 |
|---|------|------|--------|
| 1 | 63 | `main` 브랜치 하드코딩 — 다른 브랜치 배포 불가 | MEDIUM |
| 2 | 77 | `docker build --no-cache` — 매번 전체 빌드, 2~3분 소요 | LOW |
| 3 | 83 | `migrate --no-input` — **에러 검증 없음** | **CRITICAL** |
| 4 | 86 | `collectstatic --no-input` — **에러 검증 없음** | **CRITICAL** |
| 5 | 82 | `sleep 10` 고정 대기 — 컨테이너 건강 체크 미사용 | MEDIUM |
| 6 | 4-7 | 동시 실행 제어 없음 — 여러 push 시 경합 | MEDIUM |
| 7 | 32-37 | EC2 인스턴스 조회 시 첫 번째만 반환 | LOW |

**CRITICAL 수정 필요** (Line 83, 86):
```yaml
# 현재 (에러 무시)
sudo docker compose ... exec -T backend uv run python manage.py migrate --no-input
sudo docker compose ... exec -T backend uv run python manage.py collectstatic --no-input

# 수정안 (에러 시 배포 실패)
sudo docker compose ... exec -T backend uv run python manage.py migrate --no-input || exit 1
sudo docker compose ... exec -T backend uv run python manage.py collectstatic --no-input || exit 1
```

**동시 실행 제어 추가 권장**:
```yaml
concurrency:
  group: deploy-ec2
  cancel-in-progress: true
```

### 5.2 create-infra.yml (수정)

- EC2 모드 `ec2_public_key` 변수 전달 ✅
- 모드별 output 추출 분기 ✅
- 모드별 요약 메시지 ✅

### 5.3 destroy.yml (수정)

- EC2 모드 `ec2_public_key` 변수 전달 ✅
- 모드별 삭제 메시지 ✅
- "destroy" 확인 입력 ✅

---

## 6. Docker Compose Production 리뷰

**파일**: `docker-compose.prod.yml` (142줄, 신규)

### 6.1 CRITICAL 이슈

#### [C4] DB 비밀번호 하드코딩 (Line 15)
```yaml
environment:
    POSTGRES_PASSWORD: postgres  # ← .env에서만 관리해야 함
```
**수정안**: `POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}` 또는 `env_file: .env`로 통일

#### [C5] 리소스 제한 미설정 (전체)
단일 EC2 인스턴스에서 모든 서비스가 실행되므로, 하나의 컨테이너가 리소스를 독점할 수 있습니다.

```yaml
# 각 서비스에 추가 권장
deploy:
    resources:
        limits:
            cpus: '0.5'
            memory: 512M
```

### 6.2 MEDIUM 이슈

| # | 라인 | 이슈 |
|---|------|------|
| 1 | 43 | 포트 80 직접 바인딩 — nginx 리버스 프록시 없음 |
| 2 | 22-32 | Redis 영속성 설정 없음 — 재시작 시 데이터 손실 |
| 3 | 86 | Celery Beat 동시 실행 방지 미설정 |

### 6.3 잘한 점

- ✅ 모든 서비스에 `restart: always` 설정
- ✅ `platform: linux/amd64` 명시 (ARM Mac 호환)
- ✅ DB/Redis healthcheck + `depends_on` condition 사용
- ✅ Celery/WebSocket 조건부 포함 (Jinja2)
- ✅ Named volume으로 데이터 영속성 보장

---

## 7. Makefile 리뷰

**파일**: `Makefile` (변경: +125, -24줄)

### 7.1 잘한 점

- EC2 모드 SSH 키 자동 생성 (`make init`)
- 모드별 `destroy-aws-manual` 분기
- 시크릿 설정 함수 재사용

### 7.2 이슈

| # | 라인 | 이슈 | 심각도 |
|---|------|------|--------|
| 1 | 96-98 | 비밀번호 입력 UX — `-sp` 플래그로 프롬프트가 안 보임 | LOW |
| 2 | 108-121 | Make 내 복잡한 셸 로직 — 테스트 어려움 | MEDIUM |
| 3 | 268-325 | `destroy-aws-manual` 58줄짜리 인라인 셸 — 외부 스크립트 분리 권장 | MEDIUM |
| 4 | 111 | SSH 키 경로 `~/.ssh/...` 하드코딩 — Windows/WSL 미호환 | LOW |
| 5 | 69, 73 | 변수 미따옴표 — 공백 포함 시 오류 | LOW |

---

## 8. post_gen_project.py 리뷰

**파일**: `hooks/post_gen_project.py` (87줄)

### 8.1 CRITICAL 이슈

#### [C6] ECS 모드에서 EC2 Terraform 파일 미삭제 (Line 68-72)

현재 코드:
```python
if aws_deployment == "ecs-fargate":
    remove_file("docker-compose.prod.yml")
    remove_file(os.path.join(workflows_dir, "deploy-ec2.yml"))
    remove_file(os.path.join("terraform", "user-data.sh"))
    # ❌ MISSING: ec2.tf, ec2_iam.tf, ec2_security.tf 삭제 누락
```

**결과**: ECS 모드로 렌더링 시 빈 ec2.tf(84줄), ec2_iam.tf(83줄), ec2_security.tf(50줄) 파일이 남음
**총 오염**: 3개 파일, 217줄 분량의 빈 파일

#### [C7] EC2 모드에서 ECS Terraform 파일 미삭제 (Line 74-80)

현재 코드:
```python
elif aws_deployment == "ec2-all-in-one":
    remove_file(os.path.join(workflows_dir, "deploy.yml"))
    rename_file(
        os.path.join(workflows_dir, "deploy-ec2.yml"),
        os.path.join(workflows_dir, "deploy.yml"),
    )
    # ❌ MISSING: ecs.tf, ecr.tf, alb.tf, security.tf, elasticache.tf, rds.tf, iam.tf 삭제 누락
```

**결과**: EC2 모드로 렌더링 시 7개의 빈 ECS .tf 파일이 남음
**총 오염**: 7개 파일, 717줄 분량의 빈 파일

### 8.2 수정안

```python
if aws_deployment == "ecs-fargate":
    print("aws_deployment=ecs-fargate: Removing EC2 files...")
    remove_file("docker-compose.prod.yml")
    remove_file(os.path.join(workflows_dir, "deploy-ec2.yml"))
    remove_file(os.path.join("terraform", "user-data.sh"))
    # EC2 전용 Terraform 파일 삭제
    remove_file(os.path.join("terraform", "ec2.tf"))
    remove_file(os.path.join("terraform", "ec2_iam.tf"))
    remove_file(os.path.join("terraform", "ec2_security.tf"))

elif aws_deployment == "ec2-all-in-one":
    print("aws_deployment=ec2-all-in-one: Removing ECS files...")
    remove_file(os.path.join(workflows_dir, "deploy.yml"))
    rename_file(
        os.path.join(workflows_dir, "deploy-ec2.yml"),
        os.path.join(workflows_dir, "deploy.yml"),
    )
    # ECS 전용 Terraform 파일 삭제
    ecs_tf_files = [
        "ecs.tf", "ecr.tf", "alb.tf", "security.tf",
        "elasticache.tf", "rds.tf", "iam.tf",
    ]
    for tf_file in ecs_tf_files:
        remove_file(os.path.join("terraform", tf_file))
```

### 8.3 나머지 로직 평가

| 기능 | 상태 |
|------|------|
| Helper 함수 (remove_directory, remove_file, rename_file) | ✅ 정상 |
| Frontend 정리 (use_frontend=no) | ✅ 정상 |
| Celery 정리 (use_celery=no) | ✅ 정상 |
| package-lock.json 생성 | ✅ 정상 (npm 미존재 시 graceful 처리) |

---

## 9. ECS ↔ EC2 모드 일관성 분석

### 워크플로우 비교

| 항목 | ECS (deploy.yml) | EC2 (deploy-ec2.yml) | 평가 |
|------|-------------------|----------------------|------|
| 트리거 | push + manual | push + manual | ✅ 동일 |
| 인프라 사전 검사 | ✅ ECR 존재 확인 | ❌ 없음 | 🔴 불일치 |
| 빌드 | Docker buildx → ECR | docker compose build | 🟡 접근 방식 다름 (OK) |
| DB 마이그레이션 | 워크플로우에 없음 | SSH로 실행 (Line 83) | 🔴 불일치 |
| Static 파일 | 워크플로우에 없음 | SSH로 실행 (Line 86) | 🔴 불일치 |
| 헬스체크 URL | /api/health/ | /api/health/ | ✅ 동일 |
| 헬스체크 대기 | 10회 × 10초 | 10회 × 10초 | ✅ 동일 |
| 안정성 대기 | `ecs wait services-stable` | sleep 15 | 🔴 ECS가 더 견고 |
| 에러 처리 | Job dependency 기반 | `set -e` (불완전) | 🟡 다름 |
| 동시 실행 제어 | 없음 | 없음 | 🟡 둘 다 필요 |

### 핵심 불일치

1. **DB 마이그레이션**: ECS 모드는 컨테이너 시작 시 또는 별도 태스크로 실행해야 하는데, 워크플로우에 명시되지 않음. EC2는 명시적으로 실행하지만 에러 체크가 없음.

2. **인프라 사전 검사**: ECS는 ECR 존재를 확인하고 없으면 중단. EC2는 확인 없이 바로 SSH 접속 시도 — 인스턴스가 아직 준비 안 됐으면 실패.

---

## 10. 종합 이슈 목록

### CRITICAL (즉시 수정 필요) — 8건

| # | 파일 | 라인 | 이슈 |
|---|------|------|------|
| C1 | deploy.sh | 223-228 | sed 특수문자 미이스케이프 |
| C2 | deploy.sh | 332-333 | SSH 키 권한 미설정 |
| C3 | deploy.sh | 323-327 | CLI 인자로 비밀 전달 |
| C4 | docker-compose.prod.yml | 15 | DB 비밀번호 하드코딩 |
| C5 | docker-compose.prod.yml | 전체 | 리소스 제한 미설정 |
| C6 | post_gen_project.py | 68-72 | ECS 모드 EC2 파일 미삭제 |
| C7 | post_gen_project.py | 74-80 | EC2 모드 ECS 파일 미삭제 |
| C8 | deploy-ec2.yml | 83, 86 | migrate/collectstatic 에러 무시 |

### HIGH (조속한 수정 필요) — 6건

| # | 파일 | 라인 | 이슈 |
|---|------|------|------|
| H1 | deploy.sh | 전체 | EXIT 트랩 미설정 (부분 실패 시 정리 불가) |
| H2 | deploy.sh | 441-443 | Terraform output 로컬 조회 실패 |
| H3 | deploy.sh | 154 | 프로젝트명 유효성 검증 없음 |
| H4 | ec2_security.tf | 12-18 | SSH 0.0.0.0/0 전역 개방 |
| H5 | user-data.sh | 34-54 | .env 파일 chmod 600 미설정 |
| H6 | ec2_iam.tf | 38-42 | s3:DeleteObject 불필요 권한 |

### MEDIUM (개선 권장) — 14건

| # | 파일 | 이슈 |
|---|------|------|
| M1 | deploy.sh:266 | sleep 30 하드코딩 |
| M2 | deploy.sh:362-378 | workflow run_id 경쟁 조건 |
| M3 | deploy.sh:405,419 | 타임아웃 하드코딩 |
| M4 | deploy.sh:419-425 | 이중 워크플로우 시도 로직 불명확 |
| M5 | deploy-ec2.yml:63 | main 브랜치 하드코딩 |
| M6 | deploy-ec2.yml:82 | sleep 10 고정 대기 |
| M7 | deploy-ec2.yml:4-7 | 동시 실행 제어 없음 |
| M8 | docker-compose.prod.yml:43 | 리버스 프록시 없이 포트 80 직접 노출 |
| M9 | docker-compose.prod.yml:22-32 | Redis 영속성 미설정 |
| M10 | user-data.sh:21 | Docker Compose 버전 하드코딩 |
| M11 | user-data.sh:56-60 | Docker Compose 자동 시작 서비스 미등록 |
| M12 | ec2.tf:41-44 | EBS 30GB — 50GB 권장 |
| M13 | Makefile:268-325 | 58줄 인라인 셸 — 외부 스크립트 분리 권장 |
| M14 | PROGRESS.md:308,311 | 파일 정리 완성도 과대 기재 |

### LOW — 5건

| # | 파일 | 이슈 |
|---|------|------|
| L1 | deploy.sh:391 | `\r` 기반 진행 표시 호환성 |
| L2 | deploy-ec2.yml:77 | --no-cache 매번 전체 빌드 |
| L3 | Makefile:111 | SSH 키 경로 하드코딩 |
| L4 | Makefile:96-98 | 비밀번호 입력 UX |
| L5 | ec2.tf | CloudWatch Agent 미설치 |

---

## 11. 프로젝트 상태 점검

### Phase 완료 현황

| Phase | 내용 | 상태 | 비고 |
|-------|------|------|------|
| Phase 1 | Django 백엔드 기본 구조 | ✅ 완료 | |
| Phase 2 | Terraform 인프라 | ✅ 완료 | |
| Phase 3 | GitHub Actions CI/CD | ✅ 완료 | |
| Phase 4 | Makefile 자동화 | ✅ 완료 | |
| Phase 5 | Next.js 프론트엔드 | ✅ 완료 | |
| Phase 6 | Celery/WebSocket 조건부 | ✅ 완료 | |
| Phase 6.5 | celery.py 삭제 수정 | ✅ 완료 | |
| Phase 7 | E2E 테스트 | ✅ 완료 | |
| Phase 8 | EC2 All-in-One + deploy.sh | ⚠️ 95% | post_gen 정리 누락 |

### E2E 테스트 커버리지

| 케이스 | 렌더링 | Docker | Terraform | 파일 정리 |
|--------|--------|--------|-----------|-----------|
| ECS + 풀옵션 | ✅ | ✅ | ✅ | ❌ 미검증 |
| ECS + 최소 | ✅ | ✅ | ✅ | ❌ 미검증 |
| EC2 + 풀옵션 | ✅ | ✅ | ✅ | ❌ 미검증 |
| EC2 + 최소 | ✅ | ✅ | ✅ | ❌ 미검증 |

> `terraform validate`는 빈 .tf 파일도 통과하므로, 파일 정리 검증이 별도로 필요합니다.

### 기술 부채

| 항목 | 심각도 | 예상 공수 |
|------|--------|-----------|
| post_gen Terraform 파일 정리 | CRITICAL | 10분 |
| deploy.sh 보안 수정 (C1~C3) | CRITICAL | 30분 |
| deploy-ec2.yml 에러 처리 (C8) | CRITICAL | 5분 |
| docker-compose.prod.yml DB 비밀번호 (C4) | CRITICAL | 5분 |
| SSH 보안 그룹 변수화 (H4) | HIGH | 15분 |
| user-data.sh .env 권한 + systemd (H5, M11) | HIGH | 20분 |
| E2E 테스트에 파일 정리 검증 추가 | MEDIUM | 20분 |

---

## 12. 권장 조치 사항

### 즉시 수정 (1시간 이내)

1. **post_gen_project.py** — Terraform 파일 정리 추가 (C6, C7)
2. **deploy-ec2.yml** — migrate/collectstatic에 `|| exit 1` 추가 (C8)
3. **docker-compose.prod.yml** — DB 비밀번호를 .env 참조로 변경 (C4)
4. **deploy.sh** — sed → python 치환, SSH 키 chmod, gh secret stdin (C1~C3)

### 다음 스프린트

5. **ec2_security.tf** — SSH CIDR 변수화 (H4)
6. **user-data.sh** — .env chmod 600, systemd 서비스 등록, CloudWatch Agent (H5, M11, L5)
7. **ec2_iam.tf** — s3:DeleteObject 제거 (H6)
8. **deploy.sh** — EXIT 트랩 + 프로젝트명 검증 + Terraform output 대안 (H1~H3)
9. **docker-compose.prod.yml** — 리소스 제한 추가 (C5)

### 향후 개선

10. E2E 테스트에 파일 정리 검증 스텝 추가
11. deploy-ec2.yml에 동시 실행 제어(concurrency) 추가
12. nginx 리버스 프록시 서비스 추가 검토
13. ECS 워크플로우에도 DB 마이그레이션 명시

---

## 총평

Phase 8은 EC2 All-in-One 배포 모드와 deploy.sh 자동화라는 **야심찬 기능을 성공적으로 구현**했습니다. 특히:

- **전체 구조와 조건부 분기 설계가 깔끔**합니다
- **deploy.sh의 9단계 워크플로우**는 DX 관점에서 훌륭합니다
- **기존 ECS 코드를 건드리지 않는 최소 침습적 접근**이 좋습니다

다만 **보안과 에러 처리 측면에서 개선이 필요**합니다:

- deploy.sh의 자격 증명 처리 방식이 취약합니다
- deploy-ec2.yml의 마이그레이션 에러가 무시됩니다
- post_gen_project.py의 Terraform 파일 정리가 불완전합니다
- SSH 보안 그룹이 전역 개방되어 있습니다

**CRITICAL 8건을 우선 수정하면 프로덕션급 템플릿으로 충분합니다.** 예상 수정 시간은 약 1~2시간입니다.

---

*Reviewed by Claude Opus 4.6 — 2026-02-28*
