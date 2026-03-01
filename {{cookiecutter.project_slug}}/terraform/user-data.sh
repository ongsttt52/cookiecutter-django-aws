#!/bin/bash
set -euo pipefail

# ==============================================================================
# EC2 User Data Script — Initial setup for Docker Compose deployment
# ==============================================================================

LOG_FILE="/var/log/user-data.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== User data script started at $(date) ==="

# 1. Install Docker
echo ">>> Installing Docker..."
dnf update -y
dnf install -y docker git
systemctl enable docker
systemctl start docker

# 2. Install Docker Compose plugin
echo ">>> Installing Docker Compose..."
DOCKER_COMPOSE_VERSION="v2.27.1"
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Verify installation
docker compose version

# 3. Create app directory
APP_DIR="/opt/app"
mkdir -p "$APP_DIR"

# 4. Write .env file
echo ">>> Writing .env file..."
cat > "$APP_DIR/.env" <<'ENVEOF'
DEBUG=0
SECRET_KEY=${django_secret_key}
ALLOWED_HOSTS=*
ENVIRONMENT=${environment}

DATABASE_URL=postgresql://postgres:${db_password}@db:5432/${project_slug}

REDIS_URL=redis://redis:6379/0
CELERY_BROKER_URL=redis://redis:6379/0
CHANNEL_LAYERS_HOST=redis://redis:6379/1

AWS_STORAGE_BUCKET_NAME=${s3_bucket_name}
AWS_DEFAULT_REGION=${aws_region}

POSTGRES_DB=${project_slug}
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${db_password}

DJANGO_SUPERUSER_EMAIL=${django_superuser_email}
DJANGO_SUPERUSER_PASSWORD=${django_superuser_password}
DJANGO_SUPERUSER_USERNAME=admin
ENVEOF

# 5. Register systemd service for auto-start on reboot
echo ">>> Registering Docker Compose systemd service..."
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

# 6. Write a marker for deploy script
echo "ready" > "$APP_DIR/.setup-complete"

echo "=== User data script completed at $(date) ==="
echo ">>> Waiting for git clone via deploy workflow..."
