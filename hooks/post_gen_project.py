"""Post-generation hook for cookiecutter-django-aws.

Removes optional directories/files based on user selections.
"""

import os
import shutil


def remove_directory(path: str) -> None:
    """Remove a directory if it exists."""
    if os.path.exists(path):
        shutil.rmtree(path)
        print(f"  Removed: {path}/")


def main() -> None:
    use_frontend = "{{ cookiecutter.use_frontend }}"

    if use_frontend != "yes":
        print("use_frontend=no: Removing frontend/ directory...")
        remove_directory("frontend")

    print("Post-generation hook completed.")


if __name__ == "__main__":
    main()
