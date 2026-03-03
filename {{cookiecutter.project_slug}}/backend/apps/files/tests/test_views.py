from unittest.mock import MagicMock, patch

import pytest
from django.urls import reverse

from apps.files.views import _get_extension


UPLOAD_URL = reverse("file-upload")
DOWNLOAD_URL = reverse("file-download")

MOCK_PRESIGNED_URL = "https://s3.amazonaws.com/bucket/test?signed=true"


def _mock_s3_client():
    """generate_presigned_url 을 가짜로 반환하는 S3 클라이언트 mock."""
    client = MagicMock()
    client.generate_presigned_url.return_value = MOCK_PRESIGNED_URL
    return client


# ---------------------------------------------------------------------------
# Upload Presigned URL
# ---------------------------------------------------------------------------
@pytest.mark.django_db
class TestUploadPresignedUrl:
    """POST /api/files/upload/ 테스트."""

    def test_success(self, authenticated_client):
        """정상 요청 시 200 + upload_url, file_key, expires_in 반환."""
        with patch("apps.files.views._get_s3_client", return_value=_mock_s3_client()):
            response = authenticated_client.post(
                UPLOAD_URL,
                {"filename": "photo.jpg", "content_type": "image/jpeg"},
                format="json",
            )

        assert response.status_code == 200
        data = response.data
        assert "upload_url" in data
        assert "file_key" in data
        assert "expires_in" in data
        assert data["file_key"].endswith("_photo.jpg")

    def test_missing_filename(self, authenticated_client):
        """filename 누락 시 400."""
        response = authenticated_client.post(
            UPLOAD_URL,
            {"content_type": "image/jpeg"},
            format="json",
        )
        assert response.status_code == 400

    def test_missing_content_type(self, authenticated_client):
        """content_type 누락 시 400."""
        response = authenticated_client.post(
            UPLOAD_URL,
            {"filename": "photo.jpg"},
            format="json",
        )
        assert response.status_code == 400

    def test_disallowed_extension(self, authenticated_client):
        """허용되지 않은 확장자(.exe) 시 400."""
        response = authenticated_client.post(
            UPLOAD_URL,
            {"filename": "malware.exe", "content_type": "application/octet-stream"},
            format="json",
        )
        assert response.status_code == 400

    def test_path_traversal_sanitized(self, authenticated_client):
        """경로 구분자 포함 filename이 basename으로 정규화되어 200."""
        with patch("apps.files.views._get_s3_client", return_value=_mock_s3_client()):
            response = authenticated_client.post(
                UPLOAD_URL,
                {"filename": "../../hack.jpg", "content_type": "image/jpeg"},
                format="json",
            )

        assert response.status_code == 200
        assert "../../" not in response.data["file_key"]
        assert response.data["file_key"].endswith("_hack.jpg")

    def test_unauthenticated(self, api_client):
        """인증 없이 접근 시 401."""
        response = api_client.post(
            UPLOAD_URL,
            {"filename": "photo.jpg", "content_type": "image/jpeg"},
            format="json",
        )
        assert response.status_code == 401

    def test_s3_client_error(self, authenticated_client):
        """S3 클라이언트 예외 시 500."""
        broken = MagicMock()
        broken.generate_presigned_url.side_effect = Exception("S3 error")
        with patch("apps.files.views._get_s3_client", return_value=broken):
            response = authenticated_client.post(
                UPLOAD_URL,
                {"filename": "photo.jpg", "content_type": "image/jpeg"},
                format="json",
            )
        assert response.status_code == 500


# ---------------------------------------------------------------------------
# Download Presigned URL
# ---------------------------------------------------------------------------
@pytest.mark.django_db
class TestDownloadPresignedUrl:
    """POST /api/files/download/ 테스트."""

    def test_success(self, authenticated_client, user):
        """자신의 파일 다운로드 시 200 + download_url, expires_in 반환."""
        file_key = f"uploads/{user.id}/abc12345_photo.jpg"
        with patch("apps.files.views._get_s3_client", return_value=_mock_s3_client()):
            response = authenticated_client.post(
                DOWNLOAD_URL,
                {"file_key": file_key},
                format="json",
            )

        assert response.status_code == 200
        assert "download_url" in response.data
        assert "expires_in" in response.data

    def test_missing_file_key(self, authenticated_client):
        """file_key 누락 시 400."""
        response = authenticated_client.post(DOWNLOAD_URL, {}, format="json")
        assert response.status_code == 400

    def test_access_denied_other_user(self, authenticated_client):
        """다른 사용자의 파일 접근 시 403."""
        response = authenticated_client.post(
            DOWNLOAD_URL,
            {"file_key": "uploads/99999/abc12345_secret.jpg"},
            format="json",
        )
        assert response.status_code == 403

    def test_unauthenticated(self, api_client):
        """인증 없이 접근 시 401."""
        response = api_client.post(
            DOWNLOAD_URL,
            {"file_key": "uploads/1/abc_photo.jpg"},
            format="json",
        )
        assert response.status_code == 401

    def test_s3_client_error(self, authenticated_client, user):
        """S3 클라이언트 예외 시 500."""
        file_key = f"uploads/{user.id}/abc12345_photo.jpg"
        broken = MagicMock()
        broken.generate_presigned_url.side_effect = Exception("S3 error")
        with patch("apps.files.views._get_s3_client", return_value=broken):
            response = authenticated_client.post(
                DOWNLOAD_URL,
                {"file_key": file_key},
                format="json",
            )
        assert response.status_code == 500


# ---------------------------------------------------------------------------
# _get_extension 헬퍼
# ---------------------------------------------------------------------------
class TestGetExtension:
    """_get_extension 유틸 함수 테스트."""

    @pytest.mark.parametrize(
        ("filename", "expected"),
        [
            ("photo.jpg", "jpg"),
            ("archive.tar.gz", "gz"),
            ("no_extension", ""),
            ("UPPER.PNG", "png"),
        ],
    )
    def test_returns_expected_extension(self, filename, expected):
        assert _get_extension(filename) == expected
