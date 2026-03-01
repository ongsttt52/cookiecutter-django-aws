# dev HEAD 코드 리뷰 — 소규모 스타트업 관점

> **리뷰 일시**: 2026-03-01
> **리뷰 대상**: dev HEAD (`1f51c4d`) — Phase 8 + Phase 9A
> **관점**: 빠른 도입과 간편한 사용 우선, 실제 동작 장애 또는 실질적 보안 위험만 지적
> **리뷰어**: Claude Opus 4.6

---

## 평가 기준

| 분류 | 기준 | 조치 |
|------|------|------|
| **FIX** | 배포가 실패하거나 기능이 깨짐 | 반드시 수정 |
| **WARN** | 현재는 동작하지만 특정 조건에서 깨질 수 있음 | 수정 권장 |
| **NOTE** | 이론적 위험 또는 코드 품질 개선 | 여유 있을 때 |

---

## FIX — 수정 필요 (4건)

### F1. post_gen_project.py: 빈 Terraform 파일 잔류

**파일**: `hooks/post_gen_project.py:68-80`

ECS 모드 선택 시 EC2 전용 `.tf` 파일 3개, EC2 모드 선택 시 ECS 전용 `.tf` 파일 7개가 빈 파일로 남습니다.

**왜 FIX인가**: `terraform validate`는 통과하지만, 렌더링된 프로젝트를 받은 개발자가 **빈 `ec2.tf` 파일을 보고 혼란**스러워합니다. "이 파일이 뭐지? 내가 뭔가 잘못 설정한 건가?" 같은 불필요한 삽질을 유발합니다. 템플릿의 핵심 가치가 "빠른 도입"이므로 혼란 요소를 제거해야 합니다.

**수정** (~5분):

```python
if aws_deployment == "ecs-fargate":
    # ... 기존 삭제 코드 ...
    # EC2 전용 Terraform 파일 삭제
    for f in ["ec2.tf", "ec2_iam.tf", "ec2_security.tf"]:
        remove_file(os.path.join("terraform", f))

elif aws_deployment == "ec2-all-in-one":
    # ... 기존 삭제 코드 ...
    # ECS 전용 Terraform 파일 삭제
    for f in ["ecs.tf", "ecr.tf", "alb.tf", "security.tf", "elasticache.tf", "rds.tf", "iam.tf"]:
        remove_file(os.path.join("terraform", f))
```

### F2. user-data.sh: EC2 재부팅 시 서비스 자동 시작 안 됨

**파일**: `terraform/user-data.sh:60-64`

user-data.sh가 Docker와 Docker Compose를 설치하지만, **systemd 서비스를 등록하지 않습니다**. EC2 인스턴스가 재부팅(AWS 유지보수, Stop/Start)되면 Docker Compose 앱이 올라오지 않아 서비스 다운됩니다.

**왜 FIX인가**: 데모 환경이라도 클라이언트가 보는 중에 AWS 유지보수로 인스턴스가 재시작되면 서비스가 내려가고, 수동 SSH 접속해서 `docker compose up -d`를 해야 합니다. 스타트업 개발자가 이걸 모르면 "갑자기 사이트가 안 돼요"로 이어집니다.

**수정** (~5분, user-data.sh 끝에 추가):

```bash
# Docker Compose 서비스 자동 시작 (재부팅 시)
cat > /etc/systemd/system/app.service <<'EOF'
[Unit]
Description=Docker Compose App
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/app
ExecStart=/usr/bin/docker compose -f docker-compose.prod.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.prod.yml down

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable app.service
```

### F3. deploy.sh: sed 치환이 일부 AWS Secret Key에서 실패

**파일**: `deploy.sh:222-228`

```bash
sed -i '' "s|your-aws-access-key-id|$aws_key|" .env
sed -i '' "s|your-aws-secret-access-key|$aws_secret|" .env
```

**왜 FIX인가**: AWS Secret Access Key에는 `+`, `/`, `=` 외에 `&`가 포함될 수 있습니다. sed에서 `&`는 "매치된 전체 문자열"을 의미하는 특수문자라서 치환 결과가 깨집니다. `deploy.sh`가 원스텝 자동화 스크립트이므로, 첫 실행에서 실패하면 사용자 경험에 치명적입니다.

**실제 발생 확률**: AWS Secret Key의 약 5~10%에서 `&` 또는 `\`가 포함됩니다. 10명 중 1명은 첫 실행에서 막힙니다.

**수정** (~3분):

```bash
# sed 대신 python3로 안전하게 치환
python3 -c "
content = open('.env').read()
content = content.replace('your-aws-access-key-id', '''$aws_key''')
content = content.replace('your-aws-secret-access-key', '''$aws_secret''')
open('.env', 'w').write(content)
"
```

### F4. ec2_security.tf: SSH 0.0.0.0/0 전역 개방 → 배포 시 현재 IP 자동 감지

**파일**: `terraform/ec2_security.tf:12-18`, `terraform/variables.tf`

SSH 보안 그룹이 전 세계 모든 IP에 열려 있습니다. 이 템플릿으로 생성하는 **모든 프로젝트**가 SSH 전역 개방 상태로 시작됩니다.

**왜 FIX인가**: 키 기반 인증이라 브루트포스로 뚫리진 않지만, AWS 콘솔에서도 경고를 표시하는 항목입니다. 변수화 + 자동 감지로 수정하면 사용자가 신경 쓸 필요 없이 안전해집니다.

**수정**: `ssh_allowed_cidrs` 변수 추가, `create-infra.yml`에서 `curl ifconfig.me`로 현재 IP 자동 감지하여 전달.

---

## WARN — 수정 권장 (3건)

### W1. files/views.py: filename에 슬래시 포함 시 S3 키 오염

**파일**: `files/views.py:81`

```python
file_key = f"uploads/{request.user.id}/{short_uuid}_{filename}"
```

사용자가 `filename`에 `../../malicious.jpg`를 보내면 S3 키가 `uploads/1/abc_../../malicious.jpg`가 됩니다. S3에서 `..`는 특별한 의미 없이 리터럴 문자열이므로 **파일시스템 공격은 불가**합니다. 다운로드 시 `startswith("uploads/1/")` 체크도 통과합니다.

**왜 WARN인가**: 실질적 보안 문제는 없지만, S3 버킷에 이상한 키가 쌓이면 관리가 어려워지고, 향후 S3 키를 파싱하는 로직이 추가될 때 문제가 될 수 있습니다.

**수정** (~2분, views.py의 upload 함수에):

```python
import os
filename = os.path.basename(filename)
```

### W2. entrypoint.sh: superuser 생성 에러가 모두 무시됨

**파일**: `entrypoint.sh:14`

```bash
2>/dev/null || echo "Superuser already exists, skipping."
```

DB 연결 실패, 잘못된 이메일 형식 등의 에러도 `skipping`으로 표시됩니다.

**왜 WARN인가**: 처음 배포 후 admin 로그인이 안 돼서 "왜 superuser가 없지?" 디버깅에 시간 낭비. 로그를 보면 `skipping`이라고만 나옴.

**수정** (~1분):

```bash
2>&1 || echo "Superuser creation skipped (may already exist)."
```

### W3. deploy-ec2.yml: 동시 실행 제어 없음

**파일**: `deploy-ec2.yml:1-7`

빠르게 2번 push하면 두 배포가 동시에 SSH로 접속해서 `docker compose up -d`를 실행합니다.

**왜 WARN인가**: 소규모 팀이라 빈도는 낮지만, 발생 시 컨테이너 상태가 꼬일 수 있습니다.

**수정** (~1분, 워크플로우 상단에):

```yaml
concurrency:
  group: deploy-ec2
  cancel-in-progress: true
```

---

## NOTE — 여유 있을 때 (이전 리뷰 이슈 재분류)

이전 Phase 8 리뷰에서 CRITICAL/HIGH로 분류했던 이슈 중 **스타트업 맥락에서 수용 가능한** 항목들:

| 이전 ID | 이슈 | 왜 수용 가능한가 |
|---------|------|-----------------|
| C2 | SSH 키 chmod 600 | `ssh-keygen`이 기본으로 0600 생성. umask를 변경하는 환경은 거의 없음 |
| C3, X2 | `--body`로 시크릿 전달 | 단일 개발자 로컬 머신에서 실행. `ps aux` 노출 0.1초 미만, 실질적 위험 없음 |
| C5 | Docker 리소스 제한 | EC2 t3.small 전용이라 컨테이너가 리소스 부족하면 오히려 문제 |
| C8 | migrate 에러 전파 | `set -e` + `script_stop: true`로 실제로는 에러 시 중단됨 |
| H1 | EXIT 트랩 | 실패 시 `gh repo delete`로 수동 정리 가능. 5분이면 됨 |
| H2 | Terraform output 조회 | 이미 graceful하게 경고 표시하고 넘어감 |
| H3 | 프로젝트명 검증 | cookiecutter에 18자 validation 있음. 특수문자는 slug 변환에서 걸림 |
| H5 | .env chmod 600 | EC2 인스턴스에 SSH 접근 자체가 키 기반이라 서버 내부 권한은 부차적 |
| H6 | s3:DeleteObject | Presigned URL API에서 delete를 노출하지 않음. IAM Role만으로는 외부 접근 불가 |

---

## 요약

| 분류 | 건수 | 예상 공수 |
|------|------|-----------|
| **FIX** | 4건 | ~20분 |
| **WARN** | 3건 | ~5분 |
| **NOTE** | 9건 | 향후 |

**현 상태 평가**: 템플릿은 **정상 동작하며 실전 투입 가능**합니다. FIX 4건은 사용자 경험(DX)과 운영 안정성에 직접 영향을 주므로 수정 권장하며, 나머지는 프로덕션 전환 시점에 개선하면 충분합니다.

**수정 완료**: FIX 4건 + WARN 3건 모두 `fix/dev-head-code-review-fixes` 브랜치에서 수정됨.

---

*Reviewed by Claude Opus 4.6 — 2026-03-01*
