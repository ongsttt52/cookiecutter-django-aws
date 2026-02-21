.PHONY: help init setup-secrets dev destroy-aws-manual

PROJECT_NAME = {{cookiecutter.project_slug}}
PROJECT_NAME_NORMALIZED = $(shell echo {{cookiecutter.project_slug}} | tr '_' '-')
AWS_REGION = {{cookiecutter.aws_region}}

help:
	@echo ""
	@echo "{{cookiecutter.project_name}} - Available Commands"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  make init               - Create GitHub repo & initial deployment"
	@echo "  make setup-secrets      - Setup GitHub Secrets"
	@echo "  make dev                - Start local development"
	@echo "  make destroy-aws-manual - (Emergency) Manual AWS resource cleanup"
	@echo ""
	@echo "💡 Tip: Use GitHub Actions 'Destroy AWS Infrastructure' workflow instead"
	@echo ""

init:
	@echo ""
	@echo "🚀 Initializing GitHub Repository..."
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "🔍 Checking .env file..."
	@if [ ! -f .env ]; then \
		echo ""; \
		echo "❌ .env file not found!"; \
		echo ""; \
		echo "Please create .env file first:"; \
		echo "  1. cp .env.example .env"; \
		echo "  2. Edit .env and add your AWS credentials"; \
		echo ""; \
		echo "Required in .env:"; \
		echo "  - AWS_ACCESS_KEY_ID"; \
		echo "  - AWS_SECRET_ACCESS_KEY"; \
		echo ""; \
		echo "Then run: make init"; \
		exit 1; \
	fi
	@. ./.env && \
	if [ -z "$$AWS_ACCESS_KEY_ID" ] || [ -z "$$AWS_SECRET_ACCESS_KEY" ]; then \
		echo ""; \
		echo "❌ AWS credentials not found in .env!"; \
		echo ""; \
		echo "Please add to .env:"; \
		echo "  AWS_ACCESS_KEY_ID=your-key"; \
		echo "  AWS_SECRET_ACCESS_KEY=your-secret"; \
		echo ""; \
		exit 1; \
	fi
	@echo "✓ .env file found with AWS credentials"
	@echo ""
	@if [ ! -d .git ]; then \
		echo "📦 Initializing git..."; \
		git init; \
		git add .; \
		git commit -m "Initial commit: Django AWS project"; \
	fi
	@echo ""
	@echo "Checking GitHub CLI..."
	@if ! gh auth status >/dev/null 2>&1; then \
		echo "❌ Please login to GitHub CLI first:"; \
		echo "   gh auth login"; \
		exit 1; \
	fi
	@echo "✓ GitHub CLI authenticated"
	@echo ""
	@read -p "GitHub repository name [$(PROJECT_NAME)]: " REPO_NAME; \
	REPO_NAME=$${REPO_NAME:-$(PROJECT_NAME)}; \
	read -p "Use organization? (y/N): " USE_ORG; \
	if [ "$$USE_ORG" = "y" ] || [ "$$USE_ORG" = "Y" ]; then \
		read -p "Organization name: " ORG_NAME; \
		REPO_NAME="$$ORG_NAME/$$REPO_NAME"; \
	fi; \
	read -p "Private repository? (y/N): " IS_PRIVATE; \
	echo ""; \
	echo "📝 Creating GitHub repository: $$REPO_NAME"; \
	if [ "$$IS_PRIVATE" = "y" ] || [ "$$IS_PRIVATE" = "Y" ]; then \
		gh repo create $$REPO_NAME --private --source=. --remote=origin; \
	else \
		gh repo create $$REPO_NAME --public --source=. --remote=origin; \
	fi
	@echo ""
	@echo "✅ Repository created!"
	@echo ""
	@echo "🔐 Setting up GitHub Secrets..."
	@echo ""
	@. ./.env && \
	AWS_ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo ""); \
	if [ -z "$$AWS_ACCOUNT_ID" ]; then \
		echo "⚠️  Could not auto-detect AWS Account ID"; \
		read -p "AWS Account ID: " AWS_ACCOUNT_ID; \
	else \
		echo "✓ AWS Account ID: $$AWS_ACCOUNT_ID"; \
	fi; \
	read -sp "Database Password (default: postgres): " DB_PASS; \
	DB_PASS=$${DB_PASS:-postgres}; \
	echo ""; \
	echo ""; \
	echo "Setting secrets..."; \
	gh secret set AWS_ACCESS_KEY_ID --body "$$AWS_ACCESS_KEY_ID" && \
	gh secret set AWS_SECRET_ACCESS_KEY --body "$$AWS_SECRET_ACCESS_KEY" && \
	gh secret set AWS_ACCOUNT_ID --body "$$AWS_ACCOUNT_ID" && \
	gh secret set DB_PASSWORD --body "$$DB_PASS"
	@echo ""
	@echo "✅ Secrets configured!"
	@echo ""
	@echo "🌿 Creating dev branch (local only)..."
	@git checkout -b dev
	@git checkout main
	@echo "✓ dev branch created for local development"
	@echo ""
	@echo "🚀 Pushing main branch to GitHub..."
	@git push origin main
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "✅ Repository initialized!"
	@echo ""
	@echo "📋 Branch structure:"
	@echo "  - main: AWS demo deployment (auto-deploy on push)"
	@echo "  - dev:  Local development only (docker-compose)"
	@echo ""
	@echo "🔗 Links:"
	@echo "  Repository: https://github.com/$$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
	@echo "  Actions:    https://github.com/$$(gh repo view --json nameWithOwner --jq .nameWithOwner)/actions"
	@echo ""
	@echo "📝 Next steps:"
	@echo "  1. Go to GitHub Actions tab"
	@echo "  2. Run 'Create AWS Infrastructure' workflow (one-time setup)"
	@echo "  3. After infrastructure is created:"
	@echo "     - Push to main → auto-deploy to AWS ✅"
	@echo "     - Work on dev → local development only 💻"
	@echo ""
	@echo "💡 Local development:"
	@echo "  git checkout dev"
	@echo "  make dev"
	@echo ""

setup-secrets:
	@echo ""
	@echo "🔐 Setting up GitHub Secrets..."
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@if [ ! -f .env ]; then \
		echo "❌ .env file not found!"; \
		echo ""; \
		echo "Please create .env file first:"; \
		echo "  cp .env.example .env"; \
		echo "  # Edit .env with your AWS credentials"; \
		echo ""; \
		exit 1; \
	fi
	@echo "📖 Reading from .env file..."
	@echo ""
	@. ./.env && \
	if [ -z "$$AWS_ACCESS_KEY_ID" ] || [ -z "$$AWS_SECRET_ACCESS_KEY" ]; then \
		echo "❌ AWS credentials not found in .env file!"; \
		echo "Please add AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY to .env"; \
		exit 1; \
	fi; \
	AWS_ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo ""); \
	if [ -z "$$AWS_ACCOUNT_ID" ]; then \
		echo "⚠️  Could not auto-detect AWS Account ID"; \
		read -p "AWS Account ID: " AWS_ACCOUNT_ID; \
	else \
		echo "✓ AWS Account ID: $$AWS_ACCOUNT_ID"; \
	fi; \
	read -sp "Database Password (default: postgres): " DB_PASS; \
	DB_PASS=$${DB_PASS:-postgres}; \
	echo ""; \
	echo ""; \
	echo "Setting secrets..."; \
	gh secret set AWS_ACCESS_KEY_ID --body "$$AWS_ACCESS_KEY_ID" && \
	gh secret set AWS_SECRET_ACCESS_KEY --body "$$AWS_SECRET_ACCESS_KEY" && \
	gh secret set AWS_ACCOUNT_ID --body "$$AWS_ACCOUNT_ID" && \
	gh secret set DB_PASSWORD --body "$$DB_PASS"
	@echo ""
	@echo "✅ Secrets configured!"
	@echo ""
	@echo "Now push to trigger deployment:"
	@echo "  git push origin main"
	@echo ""

dev:
	@echo ""
	@echo "🚀 Starting Local Development..."
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@if [ ! -f .env ]; then \
		echo "⚠️  .env file not found. Copying from .env.example..."; \
		cp .env.example .env; \
		echo ""; \
		echo "❌ Please edit .env file with your AWS credentials!"; \
		echo "   Required: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"; \
		exit 1; \
	fi
	@echo "🐳 Starting Docker Compose..."
	@docker compose up -d
	@echo ""
	@echo "✅ Services started!"
	@echo ""
	@echo "Access at:"
	@echo "  Backend API:  http://localhost:8000/api/"
	@echo "  Admin Panel:  http://localhost:8000/api/admin/"
	@echo "  API Docs:     http://localhost:8000/api/docs/"
{% if cookiecutter.use_frontend == "yes" %}	@echo "  Frontend:     http://localhost:3000"
{% endif %}{% if cookiecutter.use_websocket == "yes" %}	@echo "  WebSocket:    ws://localhost:8001"
{% endif %}	@echo ""
	@echo "Useful commands:"
	@echo "  View logs:       docker compose logs -f"
	@echo "  Stop services:   docker compose down"
	@echo "  Run migrations:  docker compose exec backend uv run python manage.py migrate"
	@echo "  Create superuser: docker compose exec backend uv run python manage.py createsuperuser"
	@echo ""

destroy-aws-manual:
	@echo ""
	@echo "⚠️  Manual AWS Resource Deletion (Emergency Only)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "⚠️  WARNING: Use GitHub Actions 'Destroy AWS Infrastructure' workflow instead!"
	@echo "   This manual cleanup is only for emergencies (e.g., Terraform state issues)"
	@echo ""
	@echo "⚠️  This will DELETE ALL AWS resources!"
	@echo ""
	@echo "Resources to be deleted:"
	@echo "  - ECS Cluster & Service"
	@echo "  - RDS Database"
	@echo "  - ElastiCache Redis"
	@echo "  - S3 Bucket (with all files)"
	@echo "  - ECR Repository (with all images)"
	@echo "  - VPC & Networking"
	@echo "  - IAM Roles"
	@echo ""
	@if [ ! -f .env ]; then \
		echo "❌ .env file not found!"; \
		echo "Please create .env with AWS credentials first."; \
		exit 1; \
	fi
	@read -p "Type 'destroy demo' to confirm deletion: " CONFIRM; \
	if [ "$$CONFIRM" != "destroy demo" ]; then \
		echo ""; \
		echo "❌ Deletion cancelled."; \
		exit 1; \
	fi
	@echo ""
	@echo "🗑️  Starting deletion..."
	@echo ""
	@. ./.env && \
	PROJECT_SLUG=$(PROJECT_NAME_NORMALIZED); \
	REGION=$(AWS_REGION); \
	\
	echo "1️⃣  Deleting ECS Services..."; \
	aws ecs update-service \
		--cluster $${PROJECT_SLUG}-cluster-demo \
		--service $${PROJECT_SLUG}-backend-service-demo \
		--desired-count 0 \
		--region $$REGION 2>/dev/null || echo "  ⚠️  Backend ECS Service not found or already deleted"; \
	aws ecs update-service \
		--cluster $${PROJECT_SLUG}-cluster-demo \
		--service $${PROJECT_SLUG}-frontend-service-demo \
		--desired-count 0 \
		--region $$REGION 2>/dev/null || echo "  ⚠️  Frontend ECS Service not found (may not exist)"; \
	sleep 10; \
	aws ecs delete-service \
		--cluster $${PROJECT_SLUG}-cluster-demo \
		--service $${PROJECT_SLUG}-backend-service-demo \
		--force \
		--region $$REGION 2>/dev/null || echo "  ⚠️  Could not delete Backend ECS Service"; \
	aws ecs delete-service \
		--cluster $${PROJECT_SLUG}-cluster-demo \
		--service $${PROJECT_SLUG}-frontend-service-demo \
		--force \
		--region $$REGION 2>/dev/null || echo "  ⚠️  Could not delete Frontend ECS Service (may not exist)"; \
	echo ""; \
	\
	echo "2️⃣  Deleting ECS Task Definitions..."; \
	for FAMILY_PREFIX in $${PROJECT_SLUG}-backend-demo $${PROJECT_SLUG}-frontend-demo; do \
		TASK_DEFS=$$(aws ecs list-task-definitions \
			--family-prefix $$FAMILY_PREFIX \
			--region $$REGION \
			--query 'taskDefinitionArns[]' \
			--output text 2>/dev/null); \
		for task_def in $$TASK_DEFS; do \
			aws ecs deregister-task-definition \
				--task-definition $$task_def \
				--region $$REGION 2>/dev/null; \
		done; \
	done; \
	echo ""; \
	\
	echo "3️⃣  Deleting ECS Cluster..."; \
	aws ecs delete-cluster \
		--cluster $${PROJECT_SLUG}-cluster-demo \
		--region $$REGION 2>/dev/null || echo "  ⚠️  ECS Cluster not found"; \
	echo ""; \
	\
	echo "4️⃣  Deleting ALB..."; \
	ALB_ARN=$$(aws elbv2 describe-load-balancers \
		--names $${PROJECT_SLUG}-alb-demo \
		--region $$REGION \
		--query 'LoadBalancers[0].LoadBalancerArn' \
		--output text 2>/dev/null); \
	if [ "$$ALB_ARN" != "None" ] && [ -n "$$ALB_ARN" ]; then \
		aws elbv2 delete-load-balancer \
			--load-balancer-arn $$ALB_ARN \
			--region $$REGION 2>/dev/null; \
		echo "  ✓ ALB deleted"; \
	else \
		echo "  ⚠️  ALB not found"; \
	fi; \
	echo ""; \
	\
	echo "5️⃣  Deleting Target Groups..."; \
	TG_ARNS=$$(aws elbv2 describe-target-groups \
		--region $$REGION \
		--query "TargetGroups[?starts_with(TargetGroupName, '$${PROJECT_SLUG}')].TargetGroupArn" \
		--output text 2>/dev/null); \
	for tg_arn in $$TG_ARNS; do \
		aws elbv2 delete-target-group \
			--target-group-arn $$tg_arn \
			--region $$REGION 2>/dev/null; \
	done; \
	echo ""; \
	\
	echo "6️⃣  Deleting RDS Database..."; \
	aws rds delete-db-instance \
		--db-instance-identifier $${PROJECT_SLUG}-db-demo \
		--skip-final-snapshot \
		--delete-automated-backups \
		--region $$REGION 2>/dev/null || echo "  ⚠️  RDS not found"; \
	echo ""; \
	\
	echo "7️⃣  Deleting ElastiCache Redis..."; \
	aws elasticache delete-cache-cluster \
		--cache-cluster-id $${PROJECT_SLUG}-redis-demo \
		--region $$REGION 2>/dev/null || echo "  ⚠️  Redis not found"; \
	echo ""; \
	\
	echo "8️⃣  Deleting S3 Bucket..."; \
	aws s3 rb s3://$${PROJECT_SLUG}-media-demo \
		--force \
		--region $$REGION 2>/dev/null || echo "  ⚠️  S3 Bucket not found"; \
	echo ""; \
	\
	echo "9️⃣  Deleting ECR Repositories..."; \
	aws ecr delete-repository \
		--repository-name $${PROJECT_SLUG}-backend-demo \
		--force \
		--region $$REGION 2>/dev/null || echo "  ⚠️  Backend ECR Repository not found"; \
	aws ecr delete-repository \
		--repository-name $${PROJECT_SLUG}-frontend-demo \
		--force \
		--region $$REGION 2>/dev/null || echo "  ⚠️  Frontend ECR Repository not found (may not exist)"; \
	echo ""; \
	\
	echo "🔟  Deleting CloudWatch Log Groups..."; \
	aws logs delete-log-group \
		--log-group-name /ecs/$${PROJECT_SLUG}-backend-demo \
		--region $$REGION 2>/dev/null || echo "  ⚠️  Backend log group not found"; \
	aws logs delete-log-group \
		--log-group-name /ecs/$${PROJECT_SLUG}-frontend-demo \
		--region $$REGION 2>/dev/null || echo "  ⚠️  Frontend log group not found (may not exist)"; \
	echo ""; \
	\
	echo "1️⃣1️⃣  Waiting for resources to finish deleting..."; \
	echo "  (RDS and ElastiCache may take 5-10 minutes)"; \
	sleep 30; \
	echo ""; \
	\
	echo "1️⃣2️⃣  Deleting Security Groups..."; \
	VPC_ID=$$(aws ec2 describe-vpcs \
		--filters "Name=tag:Name,Values=$${PROJECT_SLUG}-vpc-demo" \
		--region $$REGION \
		--query 'Vpcs[0].VpcId' \
		--output text 2>/dev/null); \
	if [ "$$VPC_ID" != "None" ] && [ -n "$$VPC_ID" ]; then \
		SG_IDS=$$(aws ec2 describe-security-groups \
			--filters "Name=vpc-id,Values=$$VPC_ID" \
			--region $$REGION \
			--query 'SecurityGroups[?GroupName!=`default`].GroupId' \
			--output text 2>/dev/null); \
		for sg_id in $$SG_IDS; do \
			aws ec2 delete-security-group \
				--group-id $$sg_id \
				--region $$REGION 2>/dev/null; \
		done; \
	fi; \
	echo ""; \
	\
	echo "1️⃣3️⃣  Deleting Subnets..."; \
	if [ "$$VPC_ID" != "None" ] && [ -n "$$VPC_ID" ]; then \
		SUBNET_IDS=$$(aws ec2 describe-subnets \
			--filters "Name=vpc-id,Values=$$VPC_ID" \
			--region $$REGION \
			--query 'Subnets[].SubnetId' \
			--output text 2>/dev/null); \
		for subnet_id in $$SUBNET_IDS; do \
			aws ec2 delete-subnet \
				--subnet-id $$subnet_id \
				--region $$REGION 2>/dev/null; \
		done; \
	fi; \
	echo ""; \
	\
	echo "1️⃣4️⃣  Deleting Internet Gateway..."; \
	if [ "$$VPC_ID" != "None" ] && [ -n "$$VPC_ID" ]; then \
		IGW_ID=$$(aws ec2 describe-internet-gateways \
			--filters "Name=attachment.vpc-id,Values=$$VPC_ID" \
			--region $$REGION \
			--query 'InternetGateways[0].InternetGatewayId' \
			--output text 2>/dev/null); \
		if [ "$$IGW_ID" != "None" ] && [ -n "$$IGW_ID" ]; then \
			aws ec2 detach-internet-gateway \
				--internet-gateway-id $$IGW_ID \
				--vpc-id $$VPC_ID \
				--region $$REGION 2>/dev/null; \
			aws ec2 delete-internet-gateway \
				--internet-gateway-id $$IGW_ID \
				--region $$REGION 2>/dev/null; \
		fi; \
	fi; \
	echo ""; \
	\
	echo "1️⃣5️⃣  Deleting Route Tables..."; \
	if [ "$$VPC_ID" != "None" ] && [ -n "$$VPC_ID" ]; then \
		RT_IDS=$$(aws ec2 describe-route-tables \
			--filters "Name=vpc-id,Values=$$VPC_ID" \
			--region $$REGION \
			--query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
			--output text 2>/dev/null); \
		for rt_id in $$RT_IDS; do \
			aws ec2 delete-route-table \
				--route-table-id $$rt_id \
				--region $$REGION 2>/dev/null; \
		done; \
	fi; \
	echo ""; \
	\
	echo "1️⃣6️⃣  Deleting VPC..."; \
	if [ "$$VPC_ID" != "None" ] && [ -n "$$VPC_ID" ]; then \
		aws ec2 delete-vpc \
			--vpc-id $$VPC_ID \
			--region $$REGION 2>/dev/null || echo "  ⚠️  VPC deletion failed (may need manual cleanup)"; \
	fi; \
	echo ""; \
	\
	echo "1️⃣7️⃣  Deleting RDS Subnet Group..."; \
	aws rds delete-db-subnet-group \
		--db-subnet-group-name $${PROJECT_SLUG}-db-subnet-demo \
		--region $$REGION 2>/dev/null || echo "  ⚠️  RDS Subnet Group not found"; \
	echo ""; \
	\
	echo "1️⃣8️⃣  Deleting ElastiCache Subnet Group..."; \
	aws elasticache delete-cache-subnet-group \
		--cache-subnet-group-name $${PROJECT_SLUG}-redis-subnet-demo \
		--region $$REGION 2>/dev/null || echo "  ⚠️  Redis Subnet Group not found"; \
	echo ""; \
	\
	echo "1️⃣9️⃣  Deleting IAM Roles..."; \
	for ROLE_NAME in $${PROJECT_SLUG}-ecs-execution-role-demo $${PROJECT_SLUG}-ecs-task-role-demo; do \
		echo "  Deleting role: $$ROLE_NAME"; \
		POLICIES=$$(aws iam list-attached-role-policies \
			--role-name $$ROLE_NAME \
			--query 'AttachedPolicies[].PolicyArn' \
			--output text 2>/dev/null); \
		for policy in $$POLICIES; do \
			aws iam detach-role-policy \
				--role-name $$ROLE_NAME \
				--policy-arn $$policy 2>/dev/null; \
		done; \
		INLINE_POLICIES=$$(aws iam list-role-policies \
			--role-name $$ROLE_NAME \
			--query 'PolicyNames[]' \
			--output text 2>/dev/null); \
		for policy in $$INLINE_POLICIES; do \
			aws iam delete-role-policy \
				--role-name $$ROLE_NAME \
				--policy-name $$policy 2>/dev/null; \
		done; \
		aws iam delete-role --role-name $$ROLE_NAME 2>/dev/null && echo "    ✓ Deleted" || echo "    ⚠️  Not found"; \
	done; \
	echo ""; \
	\
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "✅ AWS resources deletion completed!"; \
	echo ""; \
	echo "⚠️  Note: RDS and ElastiCache deletion may still be in progress."; \
	echo "   Check AWS Console to verify all resources are deleted."; \
	echo ""; \
	echo "To verify deletion:"; \
	echo "  aws resourcegroupstaggingapi get-resources --region $$REGION"; \
	echo ""

.DEFAULT_GOAL := help
