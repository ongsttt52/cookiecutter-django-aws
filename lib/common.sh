#!/usr/bin/env bash
# ==============================================================================
# lib/common.sh — deploy.sh / infra-only.sh 공통 함수
#
# 사용법:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/common.sh"
# ==============================================================================

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
# ensure_state_bucket — Terraform state용 S3 버킷 생성/확인
#
# 필요 변수: PROJECT_SLUG, AWS_REGION, NO_INPUT
# 필요 변수 (선택): PROJECT_DIR (버킷명 변경 시 backend.tf 업데이트)
# 출력 변수: TF_STATE_BUCKET
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
      log_error "Re-run with a custom terraform_state_bucket value."
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
  local backend_file="${PROJECT_DIR:-$(pwd)}/terraform/backend.tf"
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
# trigger_and_wait_workflow — GitHub Actions workflow 트리거 + 완료 대기
#
# 인자: $1=workflow_name, $2=max_wait(seconds), $3=repo(owner/name)
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

# ==============================================================================
# verify_endpoint — 배포 후 /api/health/ 헬스체크
#
# 인자: $1=app_url
# 출력 변수: APP_URL (검증 성공 시 설정)
# ==============================================================================
verify_endpoint() {
  local app_url="$1"

  if [ -z "$app_url" ]; then
    log_warn "No app URL provided. Skipping endpoint verification."
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
