from unittest.mock import patch

import pytest
from django.urls import reverse


HEALTH_URL = reverse("health-check")


@pytest.mark.django_db
class TestHealthCheck:
    """GET /api/health/ 테스트."""

    def test_healthy_with_db_connected(self, api_client):
        """정상 DB 연결 시 200 + healthy 응답."""
        response = api_client.get(HEALTH_URL)

        assert response.status_code == 200
        assert response.data == {"status": "healthy", "database": "connected"}

    def test_unhealthy_when_db_fails(self, api_client):
        """DB 연결 실패 시 503 + unhealthy 응답."""
        with patch("apps.core.views.connection") as mock_conn:
            mock_conn.cursor.side_effect = Exception("connection refused")
            response = api_client.get(HEALTH_URL)

        assert response.status_code == 503
        assert response.data == {"status": "unhealthy", "database": "disconnected"}

    def test_allows_unauthenticated_access(self, api_client):
        """인증 없이도 접근 가능 (AllowAny)."""
        response = api_client.get(HEALTH_URL)

        assert response.status_code == 200
