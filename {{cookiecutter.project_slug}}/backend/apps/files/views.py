import logging
import os
import uuid

import boto3
from botocore.config import Config as BotoConfig
from django.conf import settings
from drf_spectacular.utils import extend_schema, inline_serializer
from rest_framework import serializers, status
from rest_framework.decorators import api_view
from rest_framework.response import Response

logger = logging.getLogger(__name__)

ALLOWED_EXTENSIONS = {
    "jpg", "jpeg", "png", "gif", "webp", "svg",
    "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
    "mp4", "mov", "avi", "webm", "mp3", "wav",
    "zip", "tar", "gz", "csv", "json", "txt",
}

MAX_FILE_SIZE = getattr(settings, "AWS_MAX_FILE_SIZE", 100 * 1024 * 1024)


def _get_s3_client():
    kwargs = {
        "region_name": settings.AWS_S3_REGION_NAME,
        "config": BotoConfig(signature_version=settings.AWS_S3_SIGNATURE_VERSION),
    }
    if settings.AWS_ACCESS_KEY_ID and settings.AWS_SECRET_ACCESS_KEY:
        kwargs["aws_access_key_id"] = settings.AWS_ACCESS_KEY_ID
        kwargs["aws_secret_access_key"] = settings.AWS_SECRET_ACCESS_KEY
    return boto3.client("s3", **kwargs)


def _get_extension(filename: str) -> str:
    return filename.rsplit(".", 1)[-1].lower() if "." in filename else ""


@extend_schema(
    tags=["files"],
    summary="Upload Presigned URL 생성",
    description="S3에 파일을 업로드하기 위한 Presigned URL을 생성합니다.",
    request=inline_serializer(
        name="UploadRequest",
        fields={
            "filename": serializers.CharField(help_text="업로드할 파일명 (확장자 포함)"),
            "content_type": serializers.CharField(help_text="파일 MIME 타입 (예: image/png)"),
        },
    ),
    responses={
        200: inline_serializer(
            name="UploadResponse",
            fields={
                "upload_url": serializers.URLField(),
                "file_key": serializers.CharField(),
                "expires_in": serializers.IntegerField(),
            },
        ),
    },
)
@api_view(["POST"])
def upload_presigned_url(request):
    """S3 Upload Presigned URL을 생성합니다."""
    filename = request.data.get("filename")
    content_type = request.data.get("content_type")

    if not filename or not content_type:
        return Response(
            {"error": "filename and content_type are required."},
            status=status.HTTP_400_BAD_REQUEST,
        )

    # 경로 구분자 제거 (S3 키 오염 방지)
    filename = os.path.basename(filename)
    if not filename:
        return Response(
            {"error": "Invalid filename."},
            status=status.HTTP_400_BAD_REQUEST,
        )

    ext = _get_extension(filename)
    if ext not in ALLOWED_EXTENSIONS:
        return Response(
            {"error": f"File extension '{ext}' is not allowed."},
            status=status.HTTP_400_BAD_REQUEST,
        )

    short_uuid = uuid.uuid4().hex[:8]
    file_key = f"uploads/{request.user.id}/{short_uuid}_{filename}"

    try:
        s3_client = _get_s3_client()
        presigned_url = s3_client.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": settings.AWS_STORAGE_BUCKET_NAME,
                "Key": file_key,
                "ContentType": content_type,
            },
            ExpiresIn=settings.AWS_PRESIGNED_URL_EXPIRY,
        )
    except Exception as e:
        logger.error("Failed to generate upload presigned URL: %s", e)
        return Response(
            {"error": "Failed to generate upload URL."},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )

    return Response({
        "upload_url": presigned_url,
        "file_key": file_key,
        "expires_in": settings.AWS_PRESIGNED_URL_EXPIRY,
    })


@extend_schema(
    tags=["files"],
    summary="Download Presigned URL 생성",
    description="S3에서 파일을 다운로드하기 위한 Presigned URL을 생성합니다.",
    request=inline_serializer(
        name="DownloadRequest",
        fields={
            "file_key": serializers.CharField(help_text="S3 파일 키 (upload 응답의 file_key)"),
        },
    ),
    responses={
        200: inline_serializer(
            name="DownloadResponse",
            fields={
                "download_url": serializers.URLField(),
                "expires_in": serializers.IntegerField(),
            },
        ),
    },
)
@api_view(["POST"])
def download_presigned_url(request):
    """S3 Download Presigned URL을 생성합니다."""
    file_key = request.data.get("file_key")

    if not file_key:
        return Response(
            {"error": "file_key is required."},
            status=status.HTTP_400_BAD_REQUEST,
        )

    # 소유권 검증: 자신의 uploads 디렉토리만 접근 가능
    allowed_prefix = f"uploads/{request.user.id}/"
    if not file_key.startswith(allowed_prefix):
        return Response(
            {"error": "Access denied."},
            status=status.HTTP_403_FORBIDDEN,
        )

    try:
        s3_client = _get_s3_client()
        presigned_url = s3_client.generate_presigned_url(
            "get_object",
            Params={
                "Bucket": settings.AWS_STORAGE_BUCKET_NAME,
                "Key": file_key,
            },
            ExpiresIn=settings.AWS_PRESIGNED_URL_EXPIRY,
        )
    except Exception as e:
        logger.error("Failed to generate download presigned URL: %s", e)
        return Response(
            {"error": "Failed to generate download URL."},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )

    return Response({
        "download_url": presigned_url,
        "expires_in": settings.AWS_PRESIGNED_URL_EXPIRY,
    })
