#!/bin/bash
set -e

echo "Running database migrations..."
uv run python manage.py migrate --noinput

# Superuser 자동 생성 (환경변수가 설정된 경우에만)
if [ -n "$DJANGO_SUPERUSER_EMAIL" ] && [ -n "$DJANGO_SUPERUSER_PASSWORD" ]; then
    echo "Creating superuser..."
    uv run python manage.py createsuperuser \
        --noinput \
        --email "$DJANGO_SUPERUSER_EMAIL" \
        --username "${DJANGO_SUPERUSER_USERNAME:-admin}" \
        2>&1 || echo "Superuser creation skipped (may already exist)."
fi

echo "Collecting static files..."
uv run python manage.py collectstatic --noinput

echo "Starting server..."
exec "$@"
