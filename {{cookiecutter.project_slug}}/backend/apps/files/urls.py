from django.urls import path

from apps.files.views import download_presigned_url, upload_presigned_url

urlpatterns = [
    path("upload/", upload_presigned_url, name="file-upload"),
    path("download/", download_presigned_url, name="file-download"),
]
