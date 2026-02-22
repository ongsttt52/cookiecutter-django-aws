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
    use_frontend = "{{ cookiecutter.use_frontend }}"
    use_celery = "{{ cookiecutter.use_celery }}"

    if use_frontend != "yes":
        print("use_frontend=no: Removing frontend/ directory...")
        remove_directory("frontend")
    else:
        print("use_frontend=yes: Generating package-lock.json...")
        generate_package_lock()

    if use_celery != "yes":
        print("use_celery=no: Removing celery config...")
        remove_file(os.path.join("backend", "config", "celery.py"))

    print("Post-generation hook completed.")


if __name__ == "__main__":
    main()
