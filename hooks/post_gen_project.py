"""Post-generation hook for cookiecutter-django-aws.

Removes optional directories/files based on user selections.
"""

import os
import shutil
import subprocess


def remove_directory(path: str) -> None:
    """Remove a directory if it exists."""
    if os.path.exists(path):
        shutil.rmtree(path)
        print(f"  Removed: {path}/")


def remove_file(path: str) -> None:
    """Remove a file if it exists."""
    if os.path.exists(path):
        os.remove(path)
        print(f"  Removed: {path}")


def rename_file(src: str, dst: str) -> None:
    """Rename a file if src exists."""
    if os.path.exists(src):
        os.rename(src, dst)
        print(f"  Renamed: {src} -> {dst}")


def generate_package_lock() -> None:
    """Generate package-lock.json for the frontend directory."""
    frontend_dir = os.path.join(os.getcwd(), "frontend")
    try:
        subprocess.run(
            ["npm", "install", "--package-lock-only"],
            cwd=frontend_dir,
            check=True,
            capture_output=True,
        )
        print("  Generated: frontend/package-lock.json")
    except FileNotFoundError:
        print("  WARNING: npm not found. Run 'npm install --package-lock-only' in frontend/ manually.")
    except subprocess.CalledProcessError as e:
        print(f"  WARNING: Failed to generate package-lock.json: {e}")


def main() -> None:
    backend_stack = "{{ cookiecutter.backend_stack }}"
    use_frontend = "{{ cookiecutter.use_frontend }}"
    use_celery = "{{ cookiecutter.use_celery }}"
    aws_deployment = "{{ cookiecutter.aws_deployment }}"

    # Phase B에서 스택별 backend/ 정리 로직 추가 예정
    print(f"backend_stack={backend_stack}")

    if use_frontend != "yes":
        print("use_frontend=no: Removing frontend/ directory...")
        remove_directory("frontend")
    else:
        print("use_frontend=yes: Generating package-lock.json...")
        generate_package_lock()

    if use_celery != "yes":
        print("use_celery=no: Removing celery config...")
        remove_file(os.path.join("backend", "config", "celery.py"))

    # Deployment mode cleanup
    workflows_dir = os.path.join(".github", "workflows")

    if aws_deployment == "ecs-fargate":
        print("aws_deployment=ecs-fargate: Removing EC2 files...")
        remove_file("docker-compose.prod.yml")
        remove_file(os.path.join(workflows_dir, "deploy-ec2.yml"))
        remove_file(os.path.join("terraform", "user-data.sh"))
        for f in ["ec2.tf", "ec2_iam.tf", "ec2_security.tf"]:
            remove_file(os.path.join("terraform", f))

    elif aws_deployment == "ec2-all-in-one":
        print("aws_deployment=ec2-all-in-one: Removing ECS files...")
        remove_file(os.path.join(workflows_dir, "deploy.yml"))
        rename_file(
            os.path.join(workflows_dir, "deploy-ec2.yml"),
            os.path.join(workflows_dir, "deploy.yml"),
        )
        for f in ["ecs.tf", "ecr.tf", "alb.tf", "security.tf", "elasticache.tf", "rds.tf", "iam.tf"]:
            remove_file(os.path.join("terraform", f))

    print("Post-generation hook completed.")


if __name__ == "__main__":
    main()
