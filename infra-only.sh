#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# infra-only.sh — 기존 프로젝트에 AWS 인프라만 생성하는 스크립트
#
# cookiecutter 렌더링 없이, 이미 렌더링/개발된 프로젝트 디렉토리에서
# Terraform state 버킷 생성 → create-infra.yml 트리거 → (선택) 앱 배포를 수행.
#
# Usage:
#   cd /path/to/my_rendered_project
#   /path/to/cookiecutter-django-aws/infra-only.sh
#   /path/to/cookiecutter-django-aws/infra-only.sh --skip-deploy
#   /path/to/cookiecutter-django-aws/infra-only.sh --no-input
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"
NO_INPUT=false
SKIP_DEPLOY=false

# Parse arguments
for arg in "$@"; do
  case $arg in
    --no-input) NO_INPUT=true ;;
    --skip-deploy) SKIP_DEPLOY=true ;;
    --help|-h)
      echo "Usage: infra-only.sh [OPTIONS]"
      echo ""
      echo "Run from inside a rendered cookiecutter-django-aws project directory."
      echo ""
      echo "Options:"
      echo "  --skip-deploy   Create infrastructure only (skip app deployment)"
      echo "  --no-input      Non-interactive mode (no prompts)"
      echo "  --help, -h      Show this help"
      echo ""
      echo "Example:"
      echo "  cd /path/to/my_project"
      echo "  /path/to/cookiecutter-django-aws/infra-only.sh"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Run 'infra-only.sh --help' for usage"
      exit 1
      ;;
  esac
done

# 공통 함수 로드
source "$SCRIPT_DIR/lib/common.sh"

# ==============================================================================
# Step 0: Prerequisites Check
# ==============================================================================
check_prerequisites() {
  log_step "0" "Checking Prerequisites"

  local missing=()

  # infra-only에서는 cookiecutter/docker가 불필요
  command -v aws >/dev/null 2>&1  || missing+=("aws CLI (https://aws.amazon.com/cli/)")
  command -v gh >/dev/null 2>&1   || missing+=("gh CLI (https://cli.github.com/)")
  command -v git >/dev/null 2>&1  || missing+=("git")

  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Missing required tools:"
    for tool in "${missing[@]}"; do
      echo "  - $tool"
    done
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
# Step 1: Detect Project Config (Makefile 파싱)
# ==============================================================================
detect_project_config() {
  log_step "1" "Detecting Project Configuration"

  # Makefile 존재 여부 확인
  if [ ! -f "$PROJECT_DIR/Makefile" ]; then
    log_error "Makefile not found in $PROJECT_DIR"
    log_error "This script must be run from a rendered cookiecutter-django-aws project directory."
    exit 1
  fi

  # Makefile에서 변수 파싱 (렌더링 시 하드코딩된 값)
  PROJECT_SLUG=$(grep -E '^PROJECT_NAME\s*=' "$PROJECT_DIR/Makefile" | head -1 | sed 's/^PROJECT_NAME\s*=\s*//' | tr -d ' ')
  AWS_REGION=$(grep -E '^AWS_REGION\s*=' "$PROJECT_DIR/Makefile" | head -1 | sed 's/^AWS_REGION\s*=\s*//' | tr -d ' ')
  local tf_bucket
  tf_bucket=$(grep -E '^TF_STATE_BUCKET\s*=' "$PROJECT_DIR/Makefile" | head -1 | sed 's/^TF_STATE_BUCKET\s*=\s*//' | tr -d ' ')

  # 필수 값 검증
  if [ -z "$PROJECT_SLUG" ]; then
    log_error "Could not parse PROJECT_NAME from Makefile."
    exit 1
  fi
  # 허용 문자 검증: cookiecutter가 생성하는 slug는 영소문자, 숫자, 언더스코어만 포함
  if ! [[ "$PROJECT_SLUG" =~ ^[a-z0-9_]+$ ]]; then
    log_error "Invalid PROJECT_NAME in Makefile: $PROJECT_SLUG"
    log_error "Expected only lowercase letters, numbers, and underscores."
    exit 1
  fi
  if [ -z "$AWS_REGION" ]; then
    log_error "Could not parse AWS_REGION from Makefile."
    exit 1
  fi
  if ! [[ "$AWS_REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]; then
    log_error "Invalid AWS_REGION in Makefile: $AWS_REGION"
    exit 1
  fi

  # TF_STATE_BUCKET: Makefile에 있으면 사용, 없으면 기본값 생성
  if [ -n "$tf_bucket" ]; then
    TF_STATE_BUCKET="$tf_bucket"
  fi

  # 배포 모드 감지: terraform/ 내 파일 기준
  if [ -f "$PROJECT_DIR/terraform/ecs.tf" ]; then
    DEPLOY_MODE="ecs-fargate"
  elif [ -f "$PROJECT_DIR/terraform/ec2.tf" ]; then
    DEPLOY_MODE="ec2-all-in-one"
  else
    log_error "Cannot detect deployment mode. Neither terraform/ecs.tf nor terraform/ec2.tf found."
    exit 1
  fi

  log_success "Project detected"
  log_info "Project:    $PROJECT_SLUG"
  log_info "Region:     $AWS_REGION"
  log_info "Deploy:     $DEPLOY_MODE"
  log_info "Directory:  $PROJECT_DIR"
}

# ==============================================================================
# Step 2: Validate (GitHub repo, Secrets, terraform/, push 상태)
# ==============================================================================
validate_project() {
  log_step "2" "Validating Project State"

  local errors=0

  # Git repo 확인
  if [ ! -d "$PROJECT_DIR/.git" ]; then
    log_error "Not a git repository. Run 'git init' first."
    errors=$((errors + 1))
  fi

  # GitHub remote 확인 — PROJECT_DIR 기준으로 조회
  REPO_FULL_NAME=""
  if git -C "$PROJECT_DIR" remote get-url origin >/dev/null 2>&1; then
    local remote_url
    remote_url=$(git -C "$PROJECT_DIR" remote get-url origin)
    REPO_FULL_NAME=$(gh repo view "$remote_url" --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")
  fi

  if [ -z "$REPO_FULL_NAME" ]; then
    log_error "No GitHub remote found. Run 'make init' or set up a GitHub remote first."
    errors=$((errors + 1))
  else
    log_success "GitHub repo: $REPO_FULL_NAME"
  fi

  # terraform/ 디렉토리 확인
  if [ ! -d "$PROJECT_DIR/terraform" ]; then
    log_error "terraform/ directory not found."
    errors=$((errors + 1))
  else
    log_success "terraform/ directory exists"
  fi

  # GitHub Secrets 확인
  if [ -n "$REPO_FULL_NAME" ]; then
    validate_secrets
  fi

  # 로컬 terraform 변경이 push되지 않은 경우 경고
  # create-infra.yml은 remote의 코드를 checkout하므로, 로컬 변경은 반영되지 않음
  if [ -d "$PROJECT_DIR/.git" ] && [ -d "$PROJECT_DIR/terraform" ]; then
    local unpushed
    unpushed=$(git -C "$PROJECT_DIR" diff --name-only HEAD @{upstream} -- terraform/ 2>/dev/null || echo "")
    local unstaged
    unstaged=$(git -C "$PROJECT_DIR" diff --name-only -- terraform/ 2>/dev/null || echo "")
    local untracked
    untracked=$(git -C "$PROJECT_DIR" ls-files --others --exclude-standard terraform/ 2>/dev/null || echo "")

    if [ -n "$unstaged" ] || [ -n "$untracked" ]; then
      log_warn "terraform/ has uncommitted changes. These will NOT be used by GitHub Actions."
      log_warn "Commit and push before running this script."
      if [ "$NO_INPUT" = false ]; then
        read -rp "Continue anyway? (Y/n): " CONTINUE
        if [[ "${CONTINUE:-Y}" =~ ^[Nn] ]]; then
          log_info "Cancelled."
          exit 0
        fi
      fi
    elif [ -n "$unpushed" ]; then
      log_warn "terraform/ has unpushed commits. Run 'git push' first."
      if [ "$NO_INPUT" = false ]; then
        read -rp "Continue anyway? (Y/n): " CONTINUE
        if [[ "${CONTINUE:-Y}" =~ ^[Nn] ]]; then
          log_info "Cancelled."
          exit 0
        fi
      fi
    fi
  fi

  if [ $errors -gt 0 ]; then
    log_error "$errors validation error(s). Fix them and retry."
    exit 1
  fi

  log_success "All validations passed"
}

# ==============================================================================
# Secrets 검증 헬퍼
# ==============================================================================
validate_secrets() {
  log_info "Checking GitHub Secrets..."

  local secret_list
  secret_list=$(gh secret list --repo "$REPO_FULL_NAME" --json name --jq '.[].name' 2>/dev/null || echo "")

  # 공통 필수 Secrets
  local required_secrets=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_ACCOUNT_ID" "DB_PASSWORD" "DJANGO_SECRET_KEY")

  # EC2 모드 추가 Secrets
  if [ "$DEPLOY_MODE" = "ec2-all-in-one" ]; then
    required_secrets+=("EC2_SSH_PRIVATE_KEY" "EC2_SSH_PUBLIC_KEY")
  fi

  local missing_secrets=()
  for secret in "${required_secrets[@]}"; do
    if ! echo "$secret_list" | grep -q "^${secret}$"; then
      missing_secrets+=("$secret")
    fi
  done

  if [ ${#missing_secrets[@]} -gt 0 ]; then
    log_error "Missing GitHub Secrets:"
    for s in "${missing_secrets[@]}"; do
      echo "  - $s"
    done
    echo ""
    log_info "Run 'make setup-secrets' in the project directory to configure them."
    exit 1
  fi

  log_success "All required GitHub Secrets are set"
}

# ==============================================================================
# Step 3: Ensure Terraform State Bucket
# ==============================================================================
do_ensure_state_bucket() {
  log_step "3" "Ensuring Terraform State Bucket"

  ensure_state_bucket
}

# ==============================================================================
# Step 4: Create Infrastructure
# ==============================================================================
create_infrastructure() {
  log_step "4" "Creating AWS Infrastructure"

  if [ "$NO_INPUT" = false ]; then
    echo ""
    log_info "This will trigger the 'Create AWS Infrastructure' workflow on GitHub Actions."
    log_info "It typically takes 5-10 minutes (RDS, ElastiCache creation)."
    echo ""
    read -rp "Proceed? (Y/n): " CONFIRM
    if [[ "${CONFIRM:-Y}" =~ ^[Nn] ]]; then
      log_info "Cancelled."
      exit 0
    fi
  fi

  if ! trigger_and_wait_workflow "Create AWS Infrastructure" 900 "$REPO_FULL_NAME"; then
    log_error "Infrastructure creation failed."
    log_info "You can retry manually:"
    log_info "  gh workflow run 'Create AWS Infrastructure' --repo $REPO_FULL_NAME"
    exit 1
  fi
}

# ==============================================================================
# Step 5: Deploy Application (선택)
# ==============================================================================
deploy_application() {
  if [ "$SKIP_DEPLOY" = true ]; then
    log_step "5" "Deploy Application (SKIPPED)"
    log_info "Use --skip-deploy was specified. Skipping app deployment."
    log_info "To deploy later, push to main branch or trigger the workflow manually."
    return
  fi

  log_step "5" "Deploying Application"

  if [ "$NO_INPUT" = false ]; then
    read -rp "Deploy application now? (Y/n): " DEPLOY_CONFIRM
    if [[ "${DEPLOY_CONFIRM:-Y}" =~ ^[Nn] ]]; then
      log_info "Skipping deployment. Push to main to trigger later."
      return
    fi
  fi

  # 배포 모드에 따라 워크플로우 선택
  local workflow_name
  if [ "$DEPLOY_MODE" = "ecs-fargate" ]; then
    workflow_name="Deploy Application"
  else
    workflow_name="Deploy to EC2"
  fi

  if ! trigger_and_wait_workflow "$workflow_name" 600 "$REPO_FULL_NAME"; then
    log_warn "Deployment workflow failed."
    log_info "Try pushing to main branch to trigger auto-deployment:"
    log_info "  cd $PROJECT_DIR && git push origin main"
  fi
}

# ==============================================================================
# Step 6: Verify Endpoint
# ==============================================================================
do_verify_endpoint() {
  log_step "6" "Verifying Deployment"

  if [ "$SKIP_DEPLOY" = true ]; then
    log_info "Deployment was skipped. Skipping endpoint verification."
    return
  fi

  cd "$PROJECT_DIR"

  # Get app URL from Terraform
  local app_url=""

  if [ -d terraform ]; then
    cd terraform
    if terraform init -backend=false >/dev/null 2>&1; then
      app_url=$(terraform output -raw app_url 2>/dev/null || echo "")
    fi
    cd "$PROJECT_DIR"
  fi

  if [ -z "$app_url" ]; then
    log_warn "Could not auto-detect app URL from Terraform outputs."
    log_info "Check GitHub Actions workflow logs for the deployment URL."
    return
  fi

  verify_endpoint "$app_url"
}

# ==============================================================================
# Step 7: Summary
# ==============================================================================
show_summary() {
  log_step "7" "Summary"

  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}${BOLD}  Infrastructure Ready!${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "  Project:     $PROJECT_SLUG"
  echo "  Deploy Mode: $DEPLOY_MODE"
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
  if [ "$DEPLOY_MODE" = "ecs-fargate" ]; then
    echo "  ~\$60/month (ECS Fargate + RDS + ElastiCache + ALB)"
  else
    echo "  ~\$15/month (EC2 t3.small + S3)"
  fi

  echo ""
  echo -e "${BOLD}To destroy infrastructure:${NC}"
  echo "  Go to GitHub Actions > 'Destroy AWS Infrastructure' > Run workflow"
  echo "  Or: cd $PROJECT_DIR && make destroy-aws-manual"
  echo ""
}

# ==============================================================================
# Main
# ==============================================================================
main() {
  echo ""
  echo -e "${BOLD}${CYAN}cookiecutter-django-aws${NC} — Infrastructure Only Script"
  echo ""

  check_prerequisites
  detect_project_config
  validate_project
  do_ensure_state_bucket
  create_infrastructure
  deploy_application
  do_verify_endpoint
  show_summary
}

main
