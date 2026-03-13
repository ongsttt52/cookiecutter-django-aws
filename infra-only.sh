#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# infra-only.sh — 기존 프로젝트에 AWS 인프라 파일을 생성하고 배포하는 스크립트
#
# cookiecutter 템플릿을 렌더링하여 인프라 파일(terraform/, .github/workflows/,
# Makefile)을 대상 프로젝트에 복사한 뒤, GitHub Actions로 AWS 인프라를 생성.
# Makefile 파싱 없이 프롬프트 입력 또는 기본값을 사용.
#
# Usage:
#   cd /path/to/my_project
#   /path/to/cookiecutter-django-aws/infra-only.sh
#   /path/to/cookiecutter-django-aws/infra-only.sh --skip-deploy
#   /path/to/cookiecutter-django-aws/infra-only.sh --no-input
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"
NO_INPUT=false
SKIP_DEPLOY=false

# 렌더링 임시 디렉토리 (cleanup trap에서 사용)
RENDER_TMPDIR=""

# Parse arguments
for arg in "$@"; do
  case $arg in
    --no-input) NO_INPUT=true ;;
    --skip-deploy) SKIP_DEPLOY=true ;;
    --help|-h)
      echo "Usage: infra-only.sh [OPTIONS]"
      echo ""
      echo "Add AWS infrastructure files to any existing project directory."
      echo "Renders the cookiecutter-django-aws template and copies only the"
      echo "infrastructure files (terraform/, .github/workflows/, Makefile)."
      echo ""
      echo "Options:"
      echo "  --skip-deploy   Create infrastructure only (skip app deployment)"
      echo "  --no-input      Non-interactive mode (use default values)"
      echo "  --help, -h      Show this help"
      echo ""
      echo "Examples:"
      echo "  # Interactive mode — prompts for project name, region, etc."
      echo "  cd /path/to/my_project"
      echo "  /path/to/cookiecutter-django-aws/infra-only.sh"
      echo ""
      echo "  # Non-interactive — uses directory name + defaults"
      echo "  cd /path/to/my_project"
      echo "  /path/to/cookiecutter-django-aws/infra-only.sh --no-input"
      echo ""
      echo "  # Infrastructure only, no app deployment"
      echo "  /path/to/cookiecutter-django-aws/infra-only.sh --skip-deploy"
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
# Cleanup trap — 임시 디렉토리 정리 (정상/비정상 종료 모두)
# ==============================================================================
cleanup() {
  if [ -n "$RENDER_TMPDIR" ] && [ -d "$RENDER_TMPDIR" ]; then
    rm -rf "$RENDER_TMPDIR"
  fi
}
trap cleanup EXIT

# ==============================================================================
# Step 0: Prerequisites Check
# ==============================================================================
check_prerequisites() {
  log_step "0" "Checking Prerequisites"

  local missing=()

  command -v aws >/dev/null 2>&1          || missing+=("aws CLI (https://aws.amazon.com/cli/)")
  command -v gh >/dev/null 2>&1           || missing+=("gh CLI (https://cli.github.com/)")
  command -v git >/dev/null 2>&1          || missing+=("git")
  command -v cookiecutter >/dev/null 2>&1 || missing+=("cookiecutter (pip install cookiecutter)")

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
# Step 1: Collect Infrastructure Inputs
# ==============================================================================
collect_infra_inputs() {
  log_step "1" "Collecting Infrastructure Configuration"

  # 기본값: 현재 디렉토리명을 slug화
  local dir_name
  dir_name=$(basename "$PROJECT_DIR")
  local default_name
  default_name=$(echo "$dir_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr '-' '_')

  while true; do
    if [ "$NO_INPUT" = true ]; then
      PROJECT_NAME="$default_name"
      BACKEND_STACK="django"
      CONTAINER_PORT="8000"
      HEALTH_CHECK_PATH="/api/health/"
      AWS_DEPLOYMENT="ecs-fargate"
      AWS_REGION="ap-northeast-2"
      USE_FRONTEND="no"
      USE_CELERY="no"
      USE_WEBSOCKET="no"
      GITHUB_RUNNER="ubuntu-latest"
      log_info "Using default values (--no-input)"
    else
      read -rp "Project name [$default_name]: " PROJECT_NAME
      PROJECT_NAME=${PROJECT_NAME:-$default_name}

      read -rp "Backend stack [django]: " BACKEND_STACK
      BACKEND_STACK=${BACKEND_STACK:-django}

      read -rp "Container port [8000]: " CONTAINER_PORT
      CONTAINER_PORT=${CONTAINER_PORT:-8000}

      read -rp "Health check path [/api/health/]: " HEALTH_CHECK_PATH
      HEALTH_CHECK_PATH=${HEALTH_CHECK_PATH:-/api/health/}

      echo ""
      echo "Deployment options:"
      echo "  1) ecs-fargate    — Production-grade, ~\$60/month"
      echo "  2) ec2-all-in-one — Cost-effective demo, ~\$15/month"
      read -rp "Deployment mode [1]: " DEPLOY_CHOICE
      case "${DEPLOY_CHOICE:-1}" in
        1) AWS_DEPLOYMENT="ecs-fargate" ;;
        2) AWS_DEPLOYMENT="ec2-all-in-one" ;;
        *) AWS_DEPLOYMENT="ecs-fargate" ;;
      esac

      read -rp "AWS Region [ap-northeast-2]: " AWS_REGION
      AWS_REGION=${AWS_REGION:-ap-northeast-2}

      read -rp "Use Frontend (Next.js)? (yes/no) [no]: " USE_FRONTEND
      USE_FRONTEND=${USE_FRONTEND:-no}

      read -rp "Use Celery? (yes/no) [no]: " USE_CELERY
      USE_CELERY=${USE_CELERY:-no}

      read -rp "Use WebSocket? (yes/no) [no]: " USE_WEBSOCKET
      USE_WEBSOCKET=${USE_WEBSOCKET:-no}

      read -rp "GitHub Runner [ubuntu-latest]: " GITHUB_RUNNER
      GITHUB_RUNNER=${GITHUB_RUNNER:-ubuntu-latest}
    fi

    # slug 생성
    PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr '-' '_')

    # slug 형식 검증
    if ! [[ "$PROJECT_SLUG" =~ ^[a-z0-9_]+$ ]]; then
      log_error "Invalid project name: $PROJECT_SLUG"
      log_error "Only lowercase letters, numbers, and underscores are allowed."
      exit 1
    fi

    # 18자 길이 제한 (ALB/TG 32-char limit 대응)
    local max_len=18
    if [ ${#PROJECT_SLUG} -gt $max_len ]; then
      log_error "Project slug '$PROJECT_SLUG' is ${#PROJECT_SLUG} characters (max $max_len)."
      log_error "AWS resource names (ALB, Target Group) have a 32-char limit."
      log_error "Please choose a shorter project name."
      if [ "$NO_INPUT" = true ]; then
        exit 1
      fi
      echo ""
      continue
    fi

    # AWS 리전 형식 검증
    if ! [[ "$AWS_REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]; then
      log_error "Invalid AWS region: $AWS_REGION"
      exit 1
    fi

    break
  done

  # DEPLOY_MODE 설정 (다른 함수에서 사용)
  DEPLOY_MODE="$AWS_DEPLOYMENT"

  echo ""
  log_info "Configuration summary:"
  echo "  Project:      $PROJECT_NAME ($PROJECT_SLUG)"
  echo "  Backend:      $BACKEND_STACK"
  echo "  Port:         $CONTAINER_PORT"
  echo "  Health check: $HEALTH_CHECK_PATH"
  echo "  Deployment:   $AWS_DEPLOYMENT"
  echo "  Region:       $AWS_REGION"
  echo "  Frontend:     $USE_FRONTEND"
  echo "  Celery:       $USE_CELERY"
  echo "  WebSocket:    $USE_WEBSOCKET"
  echo "  Runner:       $GITHUB_RUNNER"

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
# Step 2: Render & Extract Infrastructure Files
# ==============================================================================
render_and_extract() {
  log_step "2" "Rendering & Extracting Infrastructure Files"

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  # --- 2a. cookiecutter 렌더링 (먼저 수행 — 실패 시 프로젝트 디렉토리 무변경) ---
  RENDER_TMPDIR=$(mktemp -d)
  chmod 700 "$RENDER_TMPDIR"
  log_info "Rendering template to temporary directory..."

  cookiecutter "$SCRIPT_DIR" \
    --no-input \
    --output-dir "$RENDER_TMPDIR" \
    project_name="$PROJECT_NAME" \
    backend_stack="$BACKEND_STACK" \
    container_port="$CONTAINER_PORT" \
    health_check_path="$HEALTH_CHECK_PATH" \
    use_celery="$USE_CELERY" \
    use_websocket="$USE_WEBSOCKET" \
    use_frontend="$USE_FRONTEND" \
    aws_deployment="$AWS_DEPLOYMENT" \
    aws_region="$AWS_REGION" \
    github_runner="$GITHUB_RUNNER"

  local rendered_dir="$RENDER_TMPDIR/$PROJECT_SLUG"

  if [ ! -d "$rendered_dir" ]; then
    log_error "Template rendering failed. Expected directory: $rendered_dir"
    exit 1
  fi

  log_success "Template rendered successfully"

  # --- 2b. 기존 인프라 파일 백업 (렌더링 성공 확인 후) ---
  log_info "Backing up existing infrastructure files..."

  if [ -f "$PROJECT_DIR/Makefile" ]; then
    cp "$PROJECT_DIR/Makefile" "$PROJECT_DIR/Makefile.bak.${timestamp}"
    log_info "  Makefile -> Makefile.bak.${timestamp}"
  fi

  if [ -d "$PROJECT_DIR/terraform" ]; then
    mv "$PROJECT_DIR/terraform" "$PROJECT_DIR/terraform.bak.${timestamp}"
    log_info "  terraform/ -> terraform.bak.${timestamp}/"
  fi

  local workflow_dir="$PROJECT_DIR/.github/workflows"
  if [ -d "$workflow_dir" ]; then
    for wf in create-infra.yml destroy.yml deploy.yml deploy-ec2.yml; do
      if [ -f "$workflow_dir/$wf" ]; then
        cp "$workflow_dir/$wf" "$workflow_dir/${wf}.bak.${timestamp}"
        log_info "  .github/workflows/$wf -> ${wf}.bak.${timestamp}"
      fi
    done
  fi

  # --- 2c. 인프라 파일 복사 ---
  log_info "Copying infrastructure files..."

  # terraform/ 전체 (post_gen_project.py가 ECS/EC2 정리 완료)
  cp -R "$rendered_dir/terraform" "$PROJECT_DIR/terraform"
  log_success "  terraform/"

  # .github/workflows/ — 인프라 관련 워크플로우만
  mkdir -p "$PROJECT_DIR/.github/workflows"
  cp "$rendered_dir/.github/workflows/create-infra.yml" "$PROJECT_DIR/.github/workflows/"
  cp "$rendered_dir/.github/workflows/destroy.yml" "$PROJECT_DIR/.github/workflows/"
  # deploy.yml은 ECS/EC2 모두 post_gen_project.py가 정리 후 deploy.yml로 통일
  if [ -f "$rendered_dir/.github/workflows/deploy.yml" ]; then
    cp "$rendered_dir/.github/workflows/deploy.yml" "$PROJECT_DIR/.github/workflows/"
  fi
  log_success "  .github/workflows/"

  # Makefile
  cp "$rendered_dir/Makefile" "$PROJECT_DIR/Makefile"
  log_success "  Makefile"

  # .env.example — 없는 경우만 복사
  if [ ! -f "$PROJECT_DIR/.env.example" ]; then
    cp "$rendered_dir/.env.example" "$PROJECT_DIR/.env.example"
    log_success "  .env.example (created)"
  else
    log_info "  .env.example already exists (skipped)"
  fi

  # 렌더링 결과물에 cookiecutter 잔여 변수가 없는지 검증
  local residual
  local check_paths=("$PROJECT_DIR/terraform/" "$PROJECT_DIR/.github/workflows/" "$PROJECT_DIR/Makefile")
  for check_path in "${check_paths[@]}"; do
    residual=$(grep -r '{{cookiecutter\.' "$check_path" 2>/dev/null || echo "")
    if [ -n "$residual" ]; then
      log_error "Cookiecutter residual variables found in $check_path:"
      echo "$residual"
      exit 1
    fi
  done

  log_success "Infrastructure files extracted successfully"
}

# ==============================================================================
# Step 3: Setup Git & GitHub
# ==============================================================================
setup_git_and_github() {
  log_step "3" "Setting Up Git & GitHub"

  cd "$PROJECT_DIR"

  # --- 3a. Git init ---
  if [ ! -d .git ]; then
    log_info "Initializing git repository..."
    git init
    git add .
    git commit -m "Initial commit"
    log_success "Git repository initialized"
  else
    log_info "Git repository already initialized"
  fi

  # --- 3b. GitHub remote ---
  REPO_FULL_NAME=""
  if git remote get-url origin >/dev/null 2>&1; then
    local remote_url
    remote_url=$(git remote get-url origin)
    REPO_FULL_NAME=$(gh repo view "$remote_url" --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")
  fi

  if [ -z "$REPO_FULL_NAME" ]; then
    log_info "No GitHub remote found. Creating repository..."

    local repo_name="$PROJECT_SLUG"
    if [ "$NO_INPUT" = false ]; then
      read -rp "GitHub repo name [$repo_name]: " input_name
      repo_name=${input_name:-$repo_name}
    fi

    # EC2 All-in-One은 EC2에서 직접 git clone하므로 public 필요
    local visibility="--private"
    if [ "$DEPLOY_MODE" = "ec2-all-in-one" ]; then
      visibility="--public"
    fi

    log_info "Creating GitHub repository: $repo_name ($visibility)"
    gh repo create "$repo_name" $visibility --source=. --remote=origin 2>&1
    REPO_FULL_NAME=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
    log_success "GitHub repo created: $REPO_FULL_NAME"
  else
    log_success "GitHub repo: $REPO_FULL_NAME"
  fi

  # --- 3c. GitHub Secrets ---
  log_info "Checking GitHub Secrets..."

  local secret_list
  secret_list=$(gh secret list --repo "$REPO_FULL_NAME" --json name --jq '.[].name' 2>/dev/null || echo "")

  # 필수 Secrets 목록
  local required_secrets=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_ACCOUNT_ID" "DB_PASSWORD" "DJANGO_SECRET_KEY")
  if [ "$DEPLOY_MODE" = "ec2-all-in-one" ]; then
    required_secrets+=("EC2_SSH_PRIVATE_KEY" "EC2_SSH_PUBLIC_KEY")
  fi

  local missing_secrets=()
  for secret in "${required_secrets[@]}"; do
    if ! echo "$secret_list" | grep -q "^${secret}$"; then
      missing_secrets+=("$secret")
    fi
  done

  if [ ${#missing_secrets[@]} -eq 0 ]; then
    log_success "All required GitHub Secrets already set"
    return
  fi

  log_info "Setting missing GitHub Secrets (${#missing_secrets[@]} missing)..."

  local aws_key aws_secret aws_account_id

  # AWS credentials — stdin으로 전달하여 프로세스 목록 노출 방지
  if printf '%s\n' "${missing_secrets[@]}" | grep -q "^AWS_ACCESS_KEY_ID$"; then
    aws_key=$(aws configure get aws_access_key_id 2>/dev/null || echo "")
    if [ -n "$aws_key" ]; then
      echo "$aws_key" | gh secret set AWS_ACCESS_KEY_ID --repo "$REPO_FULL_NAME"
      log_info "  AWS_ACCESS_KEY_ID set (from AWS CLI profile)"
    else
      log_error "Could not auto-detect AWS_ACCESS_KEY_ID. Set it manually:"
      log_error "  gh secret set AWS_ACCESS_KEY_ID --repo $REPO_FULL_NAME"
      exit 1
    fi
  fi

  if printf '%s\n' "${missing_secrets[@]}" | grep -q "^AWS_SECRET_ACCESS_KEY$"; then
    aws_secret=$(aws configure get aws_secret_access_key 2>/dev/null || echo "")
    if [ -n "$aws_secret" ]; then
      echo "$aws_secret" | gh secret set AWS_SECRET_ACCESS_KEY --repo "$REPO_FULL_NAME"
      log_info "  AWS_SECRET_ACCESS_KEY set (from AWS CLI profile)"
    else
      log_error "Could not auto-detect AWS_SECRET_ACCESS_KEY. Set it manually:"
      log_error "  gh secret set AWS_SECRET_ACCESS_KEY --repo $REPO_FULL_NAME"
      exit 1
    fi
  fi

  if printf '%s\n' "${missing_secrets[@]}" | grep -q "^AWS_ACCOUNT_ID$"; then
    aws_account_id=$(aws sts get-caller-identity --query Account --output text)
    echo "$aws_account_id" | gh secret set AWS_ACCOUNT_ID --repo "$REPO_FULL_NAME"
    log_info "  AWS_ACCOUNT_ID set ($aws_account_id)"
  fi

  # DB Password
  if printf '%s\n' "${missing_secrets[@]}" | grep -q "^DB_PASSWORD$"; then
    local db_pass
    db_pass=$(python3 -c "import secrets; print(secrets.token_urlsafe(16))")
    echo "$db_pass" | gh secret set DB_PASSWORD --repo "$REPO_FULL_NAME"
    log_info "  DB_PASSWORD set (auto-generated)"
  fi

  # Django Secret Key
  if printf '%s\n' "${missing_secrets[@]}" | grep -q "^DJANGO_SECRET_KEY$"; then
    local django_key
    django_key=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")
    echo "$django_key" | gh secret set DJANGO_SECRET_KEY --repo "$REPO_FULL_NAME"
    log_info "  DJANGO_SECRET_KEY set (auto-generated)"
  fi

  # EC2 SSH keys
  if [ "$DEPLOY_MODE" = "ec2-all-in-one" ]; then
    if printf '%s\n' "${missing_secrets[@]}" | grep -q "^EC2_SSH_PRIVATE_KEY$"; then
      local key_path="$HOME/.ssh/${PROJECT_SLUG//_/-}-ec2-key"
      if [ ! -f "$key_path" ]; then
        ssh-keygen -t ed25519 -f "$key_path" -N "" -C "$PROJECT_SLUG-ec2"
        log_info "  SSH key generated: $key_path"
      fi
      gh secret set EC2_SSH_PRIVATE_KEY --repo "$REPO_FULL_NAME" < "$key_path"
      cat "${key_path}.pub" | gh secret set EC2_SSH_PUBLIC_KEY --repo "$REPO_FULL_NAME"
      log_info "  EC2_SSH_PRIVATE_KEY and EC2_SSH_PUBLIC_KEY set"
    fi
  fi

  log_success "GitHub Secrets configured"
}

# ==============================================================================
# Step 4: Commit & Push Infrastructure Files
# ==============================================================================
commit_and_push_infra() {
  log_step "4" "Committing & Pushing Infrastructure Files"

  cd "$PROJECT_DIR"

  # 인프라 파일 stage
  git add terraform/ .github/workflows/ Makefile
  # .env.example이 untracked(새로 생성된) 경우에만 stage
  if [ -f .env.example ] && git ls-files --others --exclude-standard .env.example | grep -q ".env.example"; then
    git add .env.example
  fi

  # 변경사항이 있는지 확인
  if git diff --cached --quiet 2>/dev/null; then
    log_info "No changes to commit (infrastructure files already up to date)"
  else
    git commit -m "feat: add AWS infrastructure files ($DEPLOY_MODE)"
    log_success "Changes committed"
  fi

  # 현재 브랜치 확인
  local current_branch
  current_branch=$(git branch --show-current)
  if [ "$current_branch" != "main" ]; then
    log_warn "Current branch is '$current_branch', not 'main'."
    log_warn "GitHub Actions workflows typically trigger on 'main' branch pushes."
  fi

  # Push
  git push origin "$current_branch"
  log_success "Pushed to origin/$current_branch"
}

# ==============================================================================
# Step 5: Ensure Terraform State Bucket
# ==============================================================================
do_ensure_state_bucket() {
  log_step "5" "Ensuring Terraform State Bucket"

  ensure_state_bucket
}

# ==============================================================================
# Step 6: Create Infrastructure
# ==============================================================================
create_infrastructure() {
  log_step "6" "Creating AWS Infrastructure"

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
# Step 7: Deploy Application (optional)
# ==============================================================================
deploy_application() {
  if [ "$SKIP_DEPLOY" = true ]; then
    log_step "7" "Deploy Application (SKIPPED)"
    log_info "Use --skip-deploy was specified. Skipping app deployment."
    log_info "To deploy later, push to main branch or trigger the workflow manually."
    return
  fi

  log_step "7" "Deploying Application"

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
# Step 8: Verify Endpoint
# ==============================================================================
do_verify_endpoint() {
  log_step "8" "Verifying Deployment"

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

  verify_endpoint "$app_url" "${HEALTH_CHECK_PATH:-/api/health/}"
}

# ==============================================================================
# Step 9: Summary
# ==============================================================================
show_summary() {
  log_step "9" "Summary"

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
    echo "  Health:      $APP_URL${HEALTH_CHECK_PATH:-/api/health/}"
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

  check_prerequisites        # Step 0
  collect_infra_inputs        # Step 1
  render_and_extract          # Step 2
  setup_git_and_github        # Step 3
  commit_and_push_infra       # Step 4
  do_ensure_state_bucket      # Step 5
  create_infrastructure       # Step 6
  deploy_application          # Step 7
  do_verify_endpoint          # Step 8
  show_summary                # Step 9
}

main
