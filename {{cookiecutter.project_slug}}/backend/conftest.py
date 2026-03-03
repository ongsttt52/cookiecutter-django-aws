import pytest
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient

User = get_user_model()


@pytest.fixture()
def user(db):
    """테스트용 일반 사용자."""
    return User.objects.create_user(
        username="testuser",
        email="test@example.com",
        password="testpass1234",
    )


@pytest.fixture()
def api_client():
    """인증되지 않은 DRF APIClient."""
    return APIClient()


@pytest.fixture()
def authenticated_client(api_client, user):
    """force_authenticate 적용된 DRF APIClient."""
    api_client.force_authenticate(user=user)
    return api_client
