# Python {{cookiecutter.python_version}} base image
FROM --platform=linux/amd64 python:{{cookiecutter.python_version}}-slim AS base

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv via pip (platform-agnostic)
RUN pip install --no-cache-dir uv

# Set work directory
WORKDIR /app

# Copy dependency files
COPY pyproject.toml ./

# Install dependencies with uv
# Note: uv.lock will be generated automatically on first build
# Run 'uv lock' locally to commit a lock file for reproducible builds
RUN uv sync --no-cache

# Copy project
COPY . .

# Set up entrypoint (migrate + collectstatic on startup)
RUN chmod +x /app/entrypoint.sh

# Run as non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8000

# entrypoint handles migrate + collectstatic before starting the server
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["uv", "run", "gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3"]
