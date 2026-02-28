# Terraform State Backend Configuration
# 프로젝트별 전용 S3 버킷에 state를 저장합니다.
# 버킷은 GitHub Actions 또는 deploy.sh에서 자동 생성됩니다.
# 버킷: {{cookiecutter.terraform_state_bucket}}
# 경로: {{cookiecutter.project_slug}}/<environment>/terraform.tfstate

terraform {
  backend "s3" {
    bucket = "{{cookiecutter.terraform_state_bucket}}"
    key    = "{{cookiecutter.project_slug}}/demo/terraform.tfstate"
    region = "{{cookiecutter.aws_region}}"
    encrypt = true
  }
}
