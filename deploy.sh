#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# deploy.sh — cookiecutter-django-aws Full Deployment Script
#
# Renders a project from the template, configures it, creates GitHub repo,
# provisions AWS infrastructure, and deploys the application.
#
# Usage:
#   ./deploy.sh                     # Interactive mode
#   ./deploy.sh --no-input          # Use defaults for all prompts
#   ./deploy.sh --skip-local-test   # Skip Docker Compose local test
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NO_INPUT=false
SKIP_LOCAL_TEST=false

# Parse arguments
for arg in "$@"; do
  case $arg in
    --no-input) NO_INPUT=true ;;
    --skip-local-test) SKIP_LOCAL_TEST=true ;;
    --help|-h)
      echo "Usage: ./deploy.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --no-input          Use default values (no interactive prompts)"
      echo "  --skip-local-test   Skip Docker Compose local verification"
      echo "  --help, -h          Show this help"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Run './deploy.sh --help' for usage"
      exit 1
      ;;
  esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Logging
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "\n${BOLD}${CYAN}=== Step $1: $2 ===${NC}\n"; }

# ==============================================================================
# Step 0: Prerequisites Check
# ==============================================================================
check_prerequisites() {
  log_step "0" "Checking Prerequisites"

  local missing=()

  # Required tools
  command -v cookiecutter >/dev/null 2>&1 || missing+=("cookiecutter (pip install cookiecutter)")
  command -v aws >/dev/null 2>&1          || missing+=("aws CLI (https://aws.amazon.com/cli/)")
  command -v gh >/dev/null 2>&1           || missing+=("gh CLI (https://cli.github.com/)")
  command -v docker >/dev/null 2>&1       || missing+=("docker (https://docker.com/)")
  command -v git >/dev/null 2>&1          || missing+=("git")
  command -v terraform >/dev/null 2>&1    || missing+=("terraform (https://terraform.io/)")

  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Missing required tools:"
    for tool in "${missing[@]}"; do
      echo "  - $tool"
    done
    exit 1
  fi

  # Check Docker is running
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker is not running. Please start Docker."
    exit 1
  fi

  # Check GitHub CLI auth
  if ! gh auth status >/dev/null 2>&1; then
    log_error "GitHub CLI not authenticated. Run: gh auth login"
    exit 1
  fi

  # Check AWS credentials
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log_error "AWS credentials not configured. Run: aws configure"
    exit 1
  fi

  local aws_account_id
  aws_account_id=$(aws sts get-caller-identity --query Account --output text)
  log_success "All prerequisites met"
  log_info "AWS Account: $aws_account_id"
  log_info "GitHub User: $(gh api user --jq .login)"
}

# ==============================================================================
# Step 1: Collect Inputs
# ==============================================================================
collect_inputs() {
  log_step "1" "Collecting Project Configuration"

  if [ "$NO_INPUT" = true ]; then
    PROJECT_NAME="my_django_project"
    USE_CELERY="no"
    USE_WEBSOCKET="no"
    USE_FRONTEND="no"
    AWS_DEPLOYMENT="ecs-fargate"
    AWS_REGION="ap-northeast-2"
    GITHUB_RUNNER="ubuntu-latest"
    log_info "Using default values (--no-input)"
  else
    read -rp "Project name [my_django_project]: " PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-my_django_project}

    read -rp "Use Celery? (yes/no) [no]: " USE_CELERY
    USE_CELERY=${USE_CELERY:-no}

    read -rp "Use WebSocket? (yes/no) [no]: " USE_WEBSOCKET
    USE_WEBSOCKET=${USE_WEBSOCKET:-no}

    read -rp "Use Frontend (Next.js)? (yes/no) [no]: " USE_FRONTEND
    USE_FRONTEND=${USE_FRONTEND:-no}

    echo ""
    echo "Deployment options:"
    echo "  1) ecs-fargate   — Production-grade, ~\$60/month"
    echo "  2) ec2-all-in-one — Cost-effective demo, ~\$15/month"
    read -rp "Deployment mode [1]: " DEPLOY_CHOICE
    case "${DEPLOY_CHOICE:-1}" in
      1) AWS_DEPLOYMENT="ecs-fargate" ;;
      2) AWS_DEPLOYMENT="ec2-all-in-one" ;;
      *) AWS_DEPLOYMENT="ecs-fargate" ;;
    esac

    read -rp "AWS Region [ap-northeast-2]: " AWS_REGION
    AWS_REGION=${AWS_REGION:-ap-northeast-2}

    read -rp "GitHub Runner [ubuntu-latest]: " GITHUB_RUNNER
    GITHUB_RUNNER=${GITHUB_RUNNER:-ubuntu-latest}
  fi

  # Derive project slug
  PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr '-' '_')

  # Terraform variables.tf에서 project_name <= 18자 제한 (ALB/TG 32-char limit)
  local max_len=18
  if [ ${#PROJECT_SLUG} -gt $max_len ]; then
    log_error "Project slug '$PROJECT_SLUG' is ${#PROJECT_SLUG} characters (max $max_len)."
    log_error "AWS resource names (ALB, Target Group) have a 32-char limit."
    log_error "Please choose a shorter project name."
    if [ "$NO_INPUT" = true ]; then
      exit 1
    fi
    echo ""
    collect_inputs  # 재입력
    return
  fi

  echo ""
  log_info "Configuration summary:"
  echo "  Project:    $PROJECT_NAME ($PROJECT_SLUG)"
  echo "  Celery:     $USE_CELERY"
  echo "  WebSocket:  $USE_WEBSOCKET"
  echo "  Frontend:   $USE_FRONTEND"
  echo "  Deployment: $AWS_DEPLOYMENT"
  echo "  Region:     $AWS_REGION"
  echo "  Runner:     $GITHUB_RUNNER"

  if [ "$NO_INPUT" = false ]; then
    echo ""
    read -rp "Proceed? (Y/n): " CONFIRM
    if [[ "${CONFIRM:-Y}" =~ ^[Nn] ]]; then
      log_info "Cancelled."
      exit 0
    fi
  fi
}

# ==============================================================================
# Step 2: Render Template
# ==============================================================================
render_template() {
  log_step "2" "Rendering Cookiecutter Template"

  OUTPUT_DIR="$(pwd)"

  cookiecutter "$SCRIPT_DIR" \
    --no-input \
    --output-dir "$OUTPUT_DIR" \
    project_name="$PROJECT_NAME" \
    use_celery="$USE_CELERY" \
    use_websocket="$USE_WEBSOCKET" \
    use_frontend="$USE_FRONTEND" \
    aws_deployment="$AWS_DEPLOYMENT" \
    aws_region="$AWS_REGION" \
    github_runner="$GITHUB_RUNNER"

  PROJECT_DIR="$OUTPUT_DIR/$PROJECT_SLUG"

  if [ ! -d "$PROJECT_DIR" ]; then
    log_error "Template rendering failed. Directory not found: $PROJECT_DIR"
    exit 1
  fi

  log_success "Template rendered at: $PROJECT_DIR"
}

# ==============================================================================
# Step 3: Setup .env
# ==============================================================================
setup_env() {
  log_step "3" "Configuring Environment Variables"

  cd "$PROJECT_DIR"

  cp .env.example .env

  # Auto-detect AWS credentials
  local aws_key aws_secret
  aws_key=$(aws configure get aws_access_key_id 2>/dev/null || echo "")
  aws_secret=$(aws configure get aws_secret_access_key 2>/dev/null || echo "")

  if [ -n "$aws_key" ] && [ -n "$aws_secret" ]; then
    # python3로 치환 (AWS Secret Key에 &, \, | 등 sed 특수문자가 포함될 수 있음)
    python3 -c "
import sys
content = open('.env').read()
content = content.replace('your-aws-access-key-id', sys.argv[1])
content = content.replace('your-aws-secret-access-key', sys.argv[2])
open('.env', 'w').write(content)
" "$aws_key" "$aws_secret"
    log_success "AWS credentials auto-configured from AWS CLI profile"
  else
    log_warn "Could not auto-detect AWS credentials."
    log_warn "Please edit .env and add AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"

    if [ "$NO_INPUT" = false ]; then
      read -rp "Press Enter after editing .env, or Ctrl+C to cancel..."
    fi
  fi

  # Check for placeholder values
  if grep -q "your-aws-access-key-id" .env; then
    log_error ".env still contains placeholder AWS credentials!"
    log_error "Please edit $PROJECT_DIR/.env before continuing."
    exit 1
  fi

  log_success ".env configured"
}

# ==============================================================================
# Step 4: Local Verification (optional)
# ==============================================================================
local_test() {
  if [ "$SKIP_LOCAL_TEST" = true ]; then
    log_step "4" "Local Verification (SKIPPED)"
    return
  fi

  log_step "4" "Local Verification (Docker Compose)"

  cd "$PROJECT_DIR"

  log_info "Starting Docker Compose..."
  docker compose up -d --build 2>&1

  # Retry health check with timeout (ARM64 emulation can be slow)
  local http_code="000"
  local max_wait=90
  local elapsed=0
  log_info "Waiting for services to be healthy (up to ${max_wait}s)..."
  while [ $elapsed -lt $max_wait ]; do
    sleep 10
    elapsed=$((elapsed + 10))
    http_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/api/health/ 2>/dev/null || echo "000")
    if [ "$http_code" = "200" ]; then
      break
    fi
    log_info "  ...${elapsed}s elapsed (HTTP $http_code)"
  done

  docker compose down 2>&1

  if [ "$http_code" = "200" ]; then
    log_success "Local health check passed (HTTP $http_code)"
  else
    log_warn "Local health check returned HTTP $http_code"
    if [ "$NO_INPUT" = false ]; then
      read -rp "Continue anyway? (Y/n): " CONTINUE
      if [[ "${CONTINUE:-Y}" =~ ^[Nn] ]]; then
        log_info "Cancelled."
        exit 0
      fi
    fi
  fi
}

# ==============================================================================
# Step 5: GitHub Init (make init)
# ==============================================================================
github_init() {
  log_step "5" "GitHub Repository Setup"

  cd "$PROJECT_DIR"

  # Initialize git
  if [ ! -d .git ]; then
    git init
    git add .
    git commit -m "Initial commit: Django AWS project ($AWS_DEPLOYMENT)"
  fi

  # Create GitHub repo
  local repo_name="$PROJECT_SLUG"
  if [ "$NO_INPUT" = false ]; then
    read -rp "GitHub repo name [$repo_name]: " input_name
    repo_name=${input_name:-$repo_name}
  fi

  # EC2 All-in-One은 EC2에서 직접 git clone하므로 public 필요
  local visibility="--private"
  if [ "$AWS_DEPLOYMENT" = "ec2-all-in-one" ]; then
    visibility="--public"
  fi

  log_info "Creating GitHub repository: $repo_name ($visibility)"
  gh repo create "$repo_name" $visibility --source=. --remote=origin 2>&1

  # Set secrets
  log_info "Setting GitHub Secrets..."
  local aws_key aws_secret aws_account_id db_pass django_key

  aws_key=$(aws configure get aws_access_key_id)
  aws_secret=$(aws configure get aws_secret_access_key)
  aws_account_id=$(aws sts get-caller-identity --query Account --output text)
  db_pass=$(python3 -c "import secrets; print(secrets.token_urlsafe(16))")
  django_key=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")

  gh secret set AWS_ACCESS_KEY_ID --body "$aws_key"
  gh secret set AWS_SECRET_ACCESS_KEY --body "$aws_secret"
  gh secret set AWS_ACCOUNT_ID --body "$aws_account_id"
  gh secret set DB_PASSWORD --body "$db_pass"
  gh secret set DJANGO_SECRET_KEY --body "$django_key"

  # EC2 SSH key
  if [ "$AWS_DEPLOYMENT" = "ec2-all-in-one" ]; then
    local key_path="$HOME/.ssh/${PROJECT_SLUG//_/-}-ec2-key"
    if [ ! -f "$key_path" ]; then
      ssh-keygen -t ed25519 -f "$key_path" -N "" -C "$PROJECT_SLUG-ec2"
      log_info "SSH key generated: $key_path"
    fi
    gh secret set EC2_SSH_PRIVATE_KEY < "$key_path"
    gh secret set EC2_SSH_PUBLIC_KEY --body "$(cat "${key_path}.pub")"
    log_success "EC2 SSH keys saved to GitHub Secrets"
  fi

  # Push
  git push origin main
  log_success "Repository created and pushed"

  REPO_FULL_NAME=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
}

# ==============================================================================
# Step 5.5: Ensure Terraform State Bucket Exists
# ==============================================================================
ensure_state_bucket() {
  # 프로젝트명에서 언더스코어를 하이픈으로 변환하여 S3 호환 버킷명 생성
  # 예: my_django_project → my-django-project-state-bucket
  local bucket_name
  bucket_name="$(echo "$PROJECT_SLUG" | tr '_' '-')-state-bucket"

  log_info "Checking Terraform state bucket: $bucket_name"

  # (1) head-bucket: 버킷 존재 여부를 HEAD 요청으로 확인
  #     버킷 목록을 가져오지 않으므로 가볍고 빠름
  if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
    TF_STATE_BUCKET="$bucket_name"
    log_success "State bucket already exists"
    return
  fi

  # 버킷이 없으면 생성 시도. 이름 충돌 시 재입력 루프.
  while true; do
    log_info "Creating state bucket: $bucket_name"

    # (2) create-bucket: S3 버킷 생성
    #     S3 버킷명은 전 세계 AWS 계정 통틀어 고유해야 함
    #     us-east-1은 S3 기본 리전이라 LocationConstraint를 넣으면 에러 → 생략
    #     `|| true`로 set -e에 의한 즉시 종료를 방지하고, 에러를 직접 핸들링
    local create_err=""
    if [ "$AWS_REGION" = "us-east-1" ]; then
      create_err=$(aws s3api create-bucket \
        --bucket "$bucket_name" 2>&1) || true
    else
      create_err=$(aws s3api create-bucket \
        --bucket "$bucket_name" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION" 2>&1) || true
    fi

    # 생성 성공 여부 판단: 정상이면 Location 헤더가 반환됨
    if echo "$create_err" | grep -q '"Location"'; then
      break  # 생성 성공 → 루프 탈출
    fi

    # 생성 실패: 이름 충돌 또는 기타 에러
    log_error "Bucket creation failed: $create_err"

    if [ "$NO_INPUT" = true ]; then
      log_error "Cannot prompt for new name in --no-input mode."
      log_error "Re-run cookiecutter with a custom terraform_state_bucket value:"
      log_error "  cookiecutter ... terraform_state_bucket=\"my-unique-name-state-bucket\""
      exit 1
    fi

    echo ""
    log_warn "Bucket name '$bucket_name' is not available (already taken by another AWS account)."
    read -rp "Enter a different bucket name (or Ctrl+C to cancel): " bucket_name

    # 빈 입력 방지
    if [ -z "$bucket_name" ]; then
      log_error "Bucket name cannot be empty."
      continue
    fi
  done

  TF_STATE_BUCKET="$bucket_name"

  # 버킷명이 변경된 경우, 렌더링된 backend.tf도 함께 업데이트
  # backend.tf에 하드코딩된 버킷명이 실제 생성된 버킷과 일치해야 terraform init이 성공함
  local backend_file="$PROJECT_DIR/terraform/backend.tf"
  if [ -f "$backend_file" ]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s|bucket = \".*\"|bucket = \"$bucket_name\"|" "$backend_file"
    else
      sed -i "s|bucket = \".*\"|bucket = \"$bucket_name\"|" "$backend_file"
    fi
    log_info "Updated backend.tf with bucket: $bucket_name"
  fi

  # (3) versioning: 파일 덮어쓰기 시에도 이전 버전을 모두 보관
  #     terraform state가 꼬였을 때 S3 콘솔에서 이전 버전으로 복원 가능
  aws s3api put-bucket-versioning \
    --bucket "$bucket_name" \
    --versioning-configuration Status=Enabled

  # (4) public-access-block: 퍼블릭 접근 4중 차단
  #     terraform state에는 DB 비밀번호 등 민감 정보가 평문으로 저장됨
  #     IAM 인증된 같은 AWS 계정 사용자는 정상 접근 가능 (개발에 영향 없음)
  aws s3api put-public-access-block \
    --bucket "$bucket_name" \
    --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

  # (5) encryption: AES-256 서버 사이드 자동 암호화 (SSE-S3)
  #     업로드 시 자동 암호화, 다운로드 시 자동 복호화 → 개발자가 처리할 것 없음
  aws s3api put-bucket-encryption \
    --bucket "$bucket_name" \
    --server-side-encryption-configuration \
      '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

  log_success "State bucket created with versioning, encryption, and public access block"
}

# ==============================================================================
# Step 6: Trigger Infrastructure Creation
# ==============================================================================
trigger_and_wait_workflow() {
  local workflow_name="$1"
  local max_wait="$2"  # seconds
  local repo="$3"

  log_info "Triggering workflow: $workflow_name"
  gh workflow run "$workflow_name" --repo "$repo"

  # Wait for workflow to start
  sleep 10

  local run_id
  run_id=$(gh run list --repo "$repo" --workflow "$workflow_name" --limit 1 --json databaseId --jq '.[0].databaseId')

  if [ -z "$run_id" ]; then
    log_error "Could not find workflow run"
    return 1
  fi

  log_info "Workflow run ID: $run_id (waiting up to ${max_wait}s...)"

  local elapsed=0
  local interval=15

  while [ $elapsed -lt "$max_wait" ]; do
    local status conclusion
    status=$(gh run view "$run_id" --repo "$repo" --json status --jq .status)
    conclusion=$(gh run view "$run_id" --repo "$repo" --json conclusion --jq .conclusion)

    if [ "$status" = "completed" ]; then
      if [ "$conclusion" = "success" ]; then
        log_success "Workflow '$workflow_name' completed successfully"
        return 0
      else
        log_error "Workflow '$workflow_name' failed (conclusion: $conclusion)"
        echo "  View logs: gh run view $run_id --repo $repo --log"
        return 1
      fi
    fi

    echo -ne "\r  Elapsed: ${elapsed}s / ${max_wait}s (status: $status)   "
    sleep $interval
    elapsed=$((elapsed + interval))
  done

  echo ""
  log_error "Workflow '$workflow_name' timed out after ${max_wait}s"
  echo "  Check status: gh run view $run_id --repo $repo"
  return 1
}

create_infrastructure() {
  log_step "6" "Creating AWS Infrastructure"

  ensure_state_bucket

  if ! trigger_and_wait_workflow "Create AWS Infrastructure" 900 "$REPO_FULL_NAME"; then
    log_error "Infrastructure creation failed."
    log_info "You can retry manually:"
    log_info "  gh workflow run 'Create AWS Infrastructure' --repo $REPO_FULL_NAME"
    exit 1
  fi
}

# ==============================================================================
# Step 7: Deploy Application
# ==============================================================================
deploy_application() {
  log_step "7" "Deploying Application"

  if ! trigger_and_wait_workflow "Deploy Application" 600 "$REPO_FULL_NAME"; then
    if ! trigger_and_wait_workflow "Deploy to EC2" 600 "$REPO_FULL_NAME"; then
      log_warn "Deployment workflow failed or not found."
      log_info "Try pushing to main branch to trigger auto-deployment:"
      log_info "  cd $PROJECT_DIR && git push origin main"
    fi
  fi
}

# ==============================================================================
# Step 8: Verify Endpoint
# ==============================================================================
verify_endpoint() {
  log_step "8" "Verifying Deployment"

  cd "$PROJECT_DIR"

  # Get app URL from Terraform
  local app_url=""

  if [ -d terraform ]; then
    cd terraform
    if terraform init -backend=false >/dev/null 2>&1; then
      # Try to get output (may fail if state is remote-only)
      app_url=$(terraform output -raw app_url 2>/dev/null || echo "")
    fi
    cd ..
  fi

  if [ -z "$app_url" ]; then
    log_warn "Could not auto-detect app URL from Terraform outputs."
    log_info "Check GitHub Actions workflow logs for the deployment URL."
    return
  fi

  log_info "Checking endpoint: $app_url/api/health/"

  local max_attempts=10
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$app_url/api/health/" 2>/dev/null || echo "000")

    if [ "$http_code" = "200" ]; then
      log_success "Endpoint verification passed (HTTP $http_code)"
      APP_URL="$app_url"
      return
    fi

    echo "  Attempt $attempt/$max_attempts: HTTP $http_code"
    sleep 15
    attempt=$((attempt + 1))
  done

  log_warn "Endpoint verification failed. The app may still be starting."
  APP_URL="$app_url"
}

# ==============================================================================
# Step 9: Result Summary
# ==============================================================================
show_summary() {
  log_step "9" "Deployment Summary"

  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}${BOLD}  Deployment Complete!${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "  Project:     $PROJECT_NAME"
  echo "  Deployment:  $AWS_DEPLOYMENT"
  echo "  Region:      $AWS_REGION"
  echo "  Repository:  https://github.com/$REPO_FULL_NAME"
  echo "  Actions:     https://github.com/$REPO_FULL_NAME/actions"

  if [ -n "${APP_URL:-}" ]; then
    echo ""
    echo "  App URL:     $APP_URL"
    echo "  API Health:  $APP_URL/api/health/"
    echo "  API Admin:   $APP_URL/api/admin/"
  fi

  if [ -n "${TF_STATE_BUCKET:-}" ]; then
    echo ""
    echo "  TF State:    s3://$TF_STATE_BUCKET"
  fi


  echo ""
  echo -e "${BOLD}Cost estimate:${NC}"
  if [ "$AWS_DEPLOYMENT" = "ecs-fargate" ]; then
    echo "  ~\$60/month (ECS Fargate + RDS + ElastiCache + ALB)"
  else
    echo "  ~\$15/month (EC2 t3.small + S3)"
  fi

  echo ""
  echo -e "${BOLD}To destroy infrastructure:${NC}"
  echo "  Go to GitHub Actions > 'Destroy AWS Infrastructure' > Run workflow"
  echo "  Or: cd $PROJECT_DIR && make destroy-aws-manual"

  echo ""
  echo -e "${BOLD}Local development:${NC}"
  echo "  cd $PROJECT_DIR"
  echo "  make dev"
  echo ""
}

# ==============================================================================
# Main
# ==============================================================================
main() {
  echo ""
  echo -e "${BOLD}${CYAN}cookiecutter-django-aws${NC} — Full Deployment Script"
  echo ""

  check_prerequisites
  collect_inputs
  render_template
  setup_env
  local_test
  github_init
  create_infrastructure
  deploy_application
  verify_endpoint
  show_summary
}

main
