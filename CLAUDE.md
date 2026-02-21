# CLAUDE.md

> **이 문서는 Claude Code가 cookiecutter-django-aws 프로젝트를 이해하고 개발을 진행하기 위한 가이드입니다.**

---

# 📌 프로젝트 개요

**프로젝트명:** cookiecutter-django-aws
**유형:** Django REST API 프로덕션급 Cookiecutter 템플릿
**목적:** 외주 개발자가 클라이언트 데모를 빠르게 AWS에 배포할 수 있는 완전 자동화 템플릿

## 핵심 가치

1. **빠른 배포**: `make init` + GitHub Actions로 5분 내 배포 완료
2. **저비용**: demo 환경 월 ~$60, 테스트 10분 ~$0.01
3. **자동화**: Terraform, GitHub Actions로 모든 과정 자동화
4. **선택 가능**: Celery, WebSocket, 리전, runner 등 커스터마이징
5. **프로덕션 준비**: S3 Presigned URL, IAM Role, VPC, RDS, Redis, ALB 포함

---

# 🚨 개발 시 지켜야 할 원칙

## 필수 준수 사항

1. **Cookiecutter 템플릿 변수 사용**
   - 모든 동적 값은 `{{cookiecutter.variable}}` 형태로 사용
   - 프로젝트명: `{{cookiecutter.project_slug}}`
   - Python 버전: `{{cookiecutter.python_version}}`
   - Django 버전: `{{cookiecutter.django_version}}`

2. **조건부 템플릿 처리**
   - Celery 관련 코드: `{% if cookiecutter.use_celery == 'yes' %}`
   - WebSocket 관련 코드: `{% if cookiecutter.use_websocket == 'yes' %}`

3. **이름 정규화 규칙**
   - AWS 리소스명에서 언더스코어(`_`) → 하이픈(`-`) 변환 필수
   - S3 버킷, ALB, Security Group 등 모든 AWS 리소스에 적용
   - 예: `my_project` → `my-project-alb-demo`

4. **플랫폼 호환성**
   - Docker 이미지는 `--platform linux/amd64` 명시 필수 (ARM64 Mac 지원)
   - uv 패키지 매니저는 pip 설치 사용 (바이너리 호환성 문제 방지)

## 코드 작성 규칙

- Python 버전: 3.12
- Django 버전: 5.2.7
- 의존성 관리: uv (pyproject.toml)
- 코드 포맷: Black
- Linting: Ruff
- Type Checking: mypy (strict 모드 권장)

---

# 🗂 프로젝트 구조

```
cookiecutter-django-aws/
├── cookiecutter.json              # Cookiecutter 템플릿 설정
├── PROGRESS.md                    # 프로젝트 진행상황 문서
├── CLAUDE.md                      # Claude Code 가이드 (이 파일)
├── .gitignore
└── {{cookiecutter.project_slug}}/ # 템플릿 실제 파일
    ├── backend/                   # Django REST API 백엔드
    │   ├── config/               # Django 설정
    │   │   ├── settings.py       # 전역 설정
    │   │   ├── urls.py           # URL 라우팅
    │   │   ├── wsgi.py           # WSGI (Gunicorn)
    │   │   ├── asgi.py           # ASGI (Daphne/WebSocket)
    │   │   └── celery.py         # Celery 설정 (조건부)
    │   ├── apps/                 # Django 앱 폴더
    │   ├── Dockerfile            # 프로덕션 Docker 이미지
    │   ├── pyproject.toml        # uv 패키지 설정
    │   └── manage.py
    ├── terraform/                 # Infrastructure as Code
    │   ├── main.tf               # Provider 설정
    │   ├── variables.tf          # 입력 변수
    │   ├── vpc.tf                # VPC, 서브넷
    │   ├── security.tf           # 보안 그룹
    │   ├── rds.tf                # PostgreSQL
    │   ├── elasticache.tf        # Redis
    │   ├── ecr.tf                # Docker 레지스트리
    │   ├── iam.tf                # IAM 역할
    │   ├── alb.tf                # Load Balancer
    │   ├── ecs.tf                # ECS Fargate
    │   ├── s3.tf                 # S3 버킷
    │   ├── outputs.tf            # 출력값
    │   └── backend.tf            # State 관리
    ├── .github/workflows/         # CI/CD 파이프라인
    │   ├── create-infra.yml      # 인프라 생성 (수동)
    │   ├── deploy.yml            # 앱 배포 (자동/수동)
    │   └── destroy.yml           # 인프라 삭제 (수동)
    ├── docker-compose.yml        # 로컬 개발 환경
    ├── Makefile                  # 자동화 명령어
    ├── README.md                 # 프로젝트 문서
    └── .env.example              # 환경 변수 예제
```

---

# 🛠 기술 스택

## 백엔드

| 기술 | 버전 | 용도 |
|------|------|------|
| Django | 5.2.7 | Web Framework |
| Django REST Framework | 3.14+ | RESTful API |
| djangorestframework-simplejwt | 5.3+ | JWT 인증 |
| PostgreSQL | 16 | Database |
| Redis | 7 | Cache, Celery Broker |
| Celery | 5.3+ | 비동기 작업 (선택) |
| Channels + Daphne | 4.0+ | WebSocket (선택) |
| boto3 + django-storages | 1.34+ | AWS S3 연동 |
| WhiteNoise | 6.6+ | Static 파일 서빙 |
| Gunicorn | 21.2+ | WSGI 서버 |
| uv | - | 패키지 매니저 |

## 개발 도구

| 기술 | 버전 | 용도 |
|------|------|------|
| pytest + pytest-django | 7.4+ | 테스트 |
| Black | 23.12+ | 코드 포맷 |
| Ruff | 0.1+ | Linting |
| mypy | 1.8+ | 타입 검증 |
| factory-boy | 3.3+ | 테스트 데이터 |

## AWS 인프라

| 서비스 | 용도 |
|--------|------|
| ECS Fargate | 컨테이너 실행 |
| RDS PostgreSQL 16 | 관리형 DB |
| ElastiCache Redis 7 | 관리형 캐시 |
| ECR | Docker 이미지 저장소 |
| S3 | 파일 저장소 (Presigned URL) |
| ALB | Application Load Balancer |
| VPC | 네트워크 격리 |
| CloudWatch | 로그/모니터링 |
| IAM | 권한 관리 |

## CI/CD

| 기술 | 용도 |
|------|------|
| GitHub Actions | 자동화 파이프라인 |
| Terraform 1.5.7+ | Infrastructure as Code |
| S3 Backend | Terraform State 관리 |

---

# ⚙️ Cookiecutter 설정 (cookiecutter.json)

```json
{
  "project_name": "my_django_project",
  "project_slug": "{{ cookiecutter.project_name.lower().replace(' ', '_').replace('-', '_') }}",
  "python_version": "3.12",
  "django_version": "5.2.7",
  "database": "postgresql",
  "use_celery": ["yes", "no"],
  "use_websocket": ["yes", "no"],
  "aws_region": "ap-northeast-2",
  "aws_deployment": "ecs-fargate",
  "ci_cd_platform": "github-actions",
  "github_runner": ["ubuntu-latest", "self-hosted"],
  "use_terraform": "yes",
  "terraform_state_backend": "s3",
  "terraform_state_bucket": "demodev-lab-terraform-states"
}
```

## 선택 가능한 옵션

| 옵션 | 설명 |
|------|------|
| `use_celery` | Celery 작업 큐 포함 여부 |
| `use_websocket` | WebSocket/Channels 포함 여부 |
| `github_runner` | GitHub Actions 실행 환경 |

---

# 🔐 환경변수 (.env.example)

```bash
# Django Settings
DEBUG=1
SECRET_KEY=your-secret-key-here-change-in-production
ALLOWED_HOSTS=localhost,127.0.0.1

# Database
DATABASE_URL=postgresql://postgres:postgres@db:5432/{{cookiecutter.project_slug}}

# Redis (use_celery 또는 use_websocket 활성화 시)
REDIS_URL=redis://redis:6379/0
CELERY_BROKER_URL=redis://redis:6379/0
CHANNEL_LAYERS_HOST=redis://redis:6379/1

# AWS S3
AWS_ACCESS_KEY_ID=your-aws-access-key-id
AWS_SECRET_ACCESS_KEY=your-aws-secret-access-key
AWS_STORAGE_BUCKET_NAME={{cookiecutter.project_slug}}-media-prod

# CORS
CORS_ALLOWED_ORIGINS=https://example.com

# Environment (demo/prod)
ENVIRONMENT=demo
```

---

# 🚀 배포 플로우

## 1단계: 프로젝트 생성
```bash
cookiecutter cookiecutter-django-aws/
# project_name, use_celery, use_websocket 등 선택
```

## 2단계: 로컬 개발 환경
```bash
cd {{project_slug}}
cp .env.example .env
make dev  # docker-compose up -d
```

## 3단계: GitHub 레포 생성
```bash
make init
# GitHub 레포 생성, Secrets 설정, push
```

## 4단계: AWS 인프라 생성
- GitHub Actions → "Create AWS Infrastructure" 수동 실행
- Terraform으로 34개 AWS 리소스 생성 (5~10분)

## 5단계: 앱 배포
```bash
git push origin main
# 자동으로 Docker 빌드 → ECR 푸시 → ECS 재배포
```

## 6단계: 인프라 삭제 (필요 시)
- GitHub Actions → "Destroy AWS Infrastructure" 수동 실행

---

# 📋 주요 Makefile 명령어

| 명령어 | 설명 |
|--------|------|
| `make help` | 사용 가능한 명령어 목록 |
| `make init` | GitHub 레포 생성 + Secrets 설정 |
| `make setup-secrets` | GitHub Secrets 수정 |
| `make dev` | docker-compose 로컬 개발 시작 |
| `make destroy-aws-manual` | 긴급 수동 AWS 리소스 삭제 |

---

# 🏗 아키텍처

```
                    Internet (HTTP 80)
                           │
                           ▼
               ┌───────────────────────┐
               │   ALB (Public)        │
               │ Health: /health/      │
               └───────────────────────┘
                           │
                           ▼
               ┌───────────────────────┐
               │   ECS Fargate         │
               │   Django + Gunicorn   │
               │ (0.25~0.5vCPU, 512MB~1GB)
               └───────────────────────┘
                    │           │
          ┌─────────┴───────────┴─────────┐
          ▼                               ▼
┌─────────────────┐             ┌─────────────────┐
│ RDS PostgreSQL  │             │ ElastiCache     │
│ (Private)       │             │ Redis (Private) │
└─────────────────┘             └─────────────────┘
                                          │
                                          ▼
                              ┌─────────────────┐
                              │ AWS S3          │
                              │ (Presigned URL) │
                              └─────────────────┘
```

---

# 💰 비용 추정 (월간)

| 환경 | RDS | ElastiCache | ECS | ALB | 기타 | **총합** |
|------|-----|-------------|-----|-----|------|----------|
| **demo** | $15 | $12 | $10 | $20 | $3 | **~$60** |
| **prod** | $30 | $24 | $30 | $20 | $6 | **~$110** |

- 테스트 10분: ~$0.01 (10원)
- 테스트 1시간: ~$0.06 (60원)

---

# 🚨 알려진 이슈 및 해결책

| 이슈 | 원인 | 해결책 |
|------|------|--------|
| `exec format error` | ARM64 이미지 | `--platform linux/amd64` 사용 |
| HTTPS 리다이렉트 루프 (demo) | 모든 환경 HTTPS 강제 | `ENVIRONMENT=demo`일 때 HTTP 허용 |
| Django Admin CSS 깨짐 | Static 파일 없음 | WhiteNoise + collectstatic |
| Health Check 실패 | /health/ 미구현 | Django에 엔드포인트 추가 필요 |
| S3 버킷명 에러 | 언더스코어 포함 | 이름 정규화 (`_` → `-`) |

---

# 📚 참고 문서

| 문서 | 위치 | 내용 |
|------|------|------|
| PROGRESS.md | 프로젝트 루트 | 진행상황, 완료 작업, 계획 |
| README.md | `{{cookiecutter.project_slug}}/` | Quick Start, 기술 스택 |
| terraform/README.md | `terraform/` | Terraform 사용법, 비용 |
| .env.example | `{{cookiecutter.project_slug}}/` | 환경 변수 템플릿 |

## 외부 문서

- [Django 공식 문서](https://docs.djangoproject.com/)
- [Django REST Framework](https://www.django-rest-framework.org/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS ECS 문서](https://docs.aws.amazon.com/ecs/)
- [Cookiecutter 문서](https://cookiecutter.readthedocs.io/)

---

# 🔧 개발 시 주의사항

## 1. Cookiecutter 템플릿 문법

```python
# 조건부 코드 (use_celery=yes일 때만 포함)
{% if cookiecutter.use_celery == 'yes' %}
from celery import shared_task
{% endif %}

# 변수 치환
DATABASE_NAME = '{{cookiecutter.project_slug}}'
```

## 2. Terraform 리소스 네이밍

```hcl
# 정규화된 이름 사용
locals {
  project_name_normalized = replace(var.project_name, "_", "-")
}

resource "aws_lb" "main" {
  name = "${local.project_name_normalized}-alb-${var.environment}"
}
```

## 3. Docker 빌드

```dockerfile
# ARM64 Mac에서 x86_64 이미지 빌드
FROM --platform=linux/amd64 python:3.12-slim
```

## 4. 환경별 설정 차이

| 설정 | demo | prod |
|------|------|------|
| HTTPS 강제 | X | O |
| S3 Lifecycle | 30일 삭제 | 수동 |
| RDS 백업 | 1일 | 7일 |
| ECS 인스턴스 | 1개 | 2개 |
| Deletion Protection | X | O |

---

# 🔮 향후 계획

## Phase 5: Next.js 프론트엔드 통합 (진행 중)
- Next.js 16 + TypeScript + Tailwind CSS
- ALB 경로 기반 라우팅: `/` → Frontend, `/api/*` → Backend

## Phase 6: 완전 자동화
- Migration 자동 실행
- Superuser 자동 생성

## Phase 7: 배포 옵션 추가
- EC2 All-in-One (저비용)
- Multi-region 배포
- Blue-Green 배포
