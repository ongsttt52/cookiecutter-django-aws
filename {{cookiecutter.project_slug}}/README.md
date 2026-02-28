# {{cookiecutter.project_name}}

Django REST API project with AWS deployment

## Project Information

- **Python**: {{cookiecutter.python_version}}
- **Django**: {{cookiecutter.django_version}}
- **Database**: {{cookiecutter.database}}

## Tech Stack

- **Backend**: Django REST Framework
- **Authentication**: JWT
{% if cookiecutter.use_frontend == "yes" -%}
- **Frontend**: Next.js 15 + React 19 + TypeScript + Tailwind CSS
{% endif -%}
{% if cookiecutter.use_celery == "yes" or cookiecutter.use_websocket == "yes" -%}
- **Cache**: Redis
{% endif -%}
{% if cookiecutter.use_celery == "yes" -%}
- **Task Queue**: Celery
{% endif -%}
{% if cookiecutter.aws_deployment == "ecs-fargate" %}- **Deployment**: AWS ECS Fargate (production-grade){% endif %}
{% if cookiecutter.aws_deployment == "ec2-all-in-one" %}- **Deployment**: AWS EC2 All-in-One (cost-effective demo, ~$15/month){% endif %}
{% if cookiecutter.use_terraform == "yes" -%}
- **Infrastructure**: Terraform
{% endif -%}

## Quick Start

### Prerequisites

- Docker & Docker Compose
{% if cookiecutter.use_terraform == "yes" -%}
- Terraform >= 1.0
{% endif -%}
- AWS Account with S3 access (required for file storage)

### Local Development

1. Clone the repository:
```bash
git clone <repository-url>
cd {{cookiecutter.project_slug}}
```

2. Copy and configure environment variables:
```bash
cp .env.example .env
```

**Important**: Edit `.env` and add your AWS credentials:
```bash
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_STORAGE_BUCKET_NAME={{cookiecutter.project_slug}}-media-prod
```

3. Start all services:
```bash
docker compose up -d
```

This will start:
- PostgreSQL database (port 5432)
- Redis (port 6379)
- Django backend (port 8000)
{% if cookiecutter.use_frontend == "yes" -%}
- Next.js frontend (port 3000)
{% endif -%}
{% if cookiecutter.use_websocket == "yes" -%}
- WebSocket server (port 8001)
{% endif -%}
{% if cookiecutter.use_celery == "yes" -%}
- Celery worker
- Celery beat scheduler
{% endif -%}

4. Run database migrations:
```bash
docker compose exec backend uv run python manage.py migrate
```

5. Create a superuser:
```bash
docker compose exec backend uv run python manage.py createsuperuser
```

6. Access the application:
- Admin: http://localhost:8000/api/admin/
- API Docs: http://localhost:8000/api/docs/
{% if cookiecutter.use_frontend == "yes" -%}
- Frontend: http://localhost:3000
{% endif -%}
{% if cookiecutter.use_websocket == "yes" -%}
- WebSocket: ws://localhost:8001/
{% endif -%}

## Project Structure

```
{{cookiecutter.project_slug}}/
├── backend/              # Django REST API
│   ├── apps/            # Django apps
│   ├── config/          # Django settings
│   └── pyproject.toml   # Python dependencies
{% if cookiecutter.use_frontend == "yes" -%}
├── frontend/            # Next.js frontend
│   ├── src/app/         # App Router pages
│   ├── package.json     # Node.js dependencies
│   └── Dockerfile.prod  # Production Docker image
{% endif -%}
├── terraform/           # Infrastructure as Code
├── .github/workflows/   # CI/CD pipelines
└── docker-compose.yml   # Local development
```

{% if cookiecutter.use_frontend == "yes" -%}
## Architecture

```
ALB (port 80)
├── /api/*  → Backend (Django, port 8000)
└── /*      → Frontend (Next.js, port 3000)
```

The frontend proxies `/api/*` requests to the backend through Next.js rewrites in local development.
In production, ALB listener rules handle the routing.

{% endif -%}
## Development

### Running Tests

```bash
docker compose exec backend uv run pytest
```

### Code Quality

```bash
# Format code
docker compose exec backend uv run black .

# Lint
docker compose exec backend uv run ruff check .

# Type check
docker compose exec backend uv run mypy .
```

{% if cookiecutter.use_terraform == "yes" -%}
## Deployment

### Terraform State Bucket

Each project uses its own S3 bucket (`{{cookiecutter.terraform_state_bucket}}`) for Terraform state.
The bucket is **automatically created** when you:
- Run the "Create AWS Infrastructure" GitHub Actions workflow, or
- Use `deploy.sh`

To manually create it:
```bash
aws s3api create-bucket \
  --bucket {{cookiecutter.terraform_state_bucket}} \
  --create-bucket-configuration LocationConstraint={{cookiecutter.aws_region}}
aws s3api put-bucket-versioning \
  --bucket {{cookiecutter.terraform_state_bucket}} \
  --versioning-configuration Status=Enabled
```

To delete the state bucket (after destroying all infrastructure):
```bash
# Use the "Destroy AWS Infrastructure" workflow with "delete_state_bucket: yes"
# Or use: make destroy-aws-manual (will prompt for state bucket deletion)
```

### Infrastructure Setup

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Application Deployment

Deployment is automated via {{cookiecutter.ci_cd_platform}} on push to main branch.

{% if cookiecutter.aws_deployment == "ec2-all-in-one" %}
### EC2 All-in-One Architecture

All services run on a single EC2 instance via Docker Compose:

```
EC2 Instance (t3.small, ~$15/month)
├── Docker Compose
│   ├── PostgreSQL (container)
│   ├── Redis (container)
│   ├── Django + Gunicorn (container, port 80)
│   ├── Celery Worker (optional)
│   └── Next.js Frontend (optional)
└── S3 (external, for media files)
```

**Cost comparison:**

| Mode | Monthly Cost | Best For |
|------|-------------|----------|
| EC2 All-in-One | ~$15 | Client demos, prototypes |
| ECS Fargate | ~$60 | Production, scalability |
{% endif %}
{% endif -%}

## Environment Variables

See `.env.example` for required environment variables.

## S3 File Storage

This project uses AWS S3 with presigned URLs for all file operations (both static and media files).

### Architecture

- **No automatic file storage**: Files are NOT stored in Django's file system
- **Client-side uploads**: Frontend uploads files directly to S3 using presigned URLs
- **Presigned URLs**: Backend generates temporary signed URLs for secure uploads/downloads

### Implementing Presigned URL Endpoints

Create API endpoints in your Django apps to generate presigned URLs:

```python
import boto3
from django.conf import settings
from rest_framework.decorators import api_view
from rest_framework.response import Response

@api_view(['POST'])
def get_upload_url(request):
    """Generate presigned URL for uploading to S3"""
    s3_client = boto3.client(
        's3',
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
        region_name=settings.AWS_S3_REGION_NAME,
    )

    filename = request.data.get('filename')
    file_key = f'uploads/{filename}'

    presigned_url = s3_client.generate_presigned_url(
        'put_object',
        Params={
            'Bucket': settings.AWS_STORAGE_BUCKET_NAME,
            'Key': file_key,
        },
        ExpiresIn=settings.AWS_PRESIGNED_URL_EXPIRY
    )

    return Response({
        'upload_url': presigned_url,
        'file_key': file_key
    })
```

For more details, see [AWS boto3 presigned URL documentation](https://boto3.amazonaws.com/v1/documentation/api/latest/guide/s3-presigned-urls.html).

## License

MIT
