from django.db import connection
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response


@api_view(["GET"])
@permission_classes([AllowAny])
def health_check(request):
    """ALB 헬스체크 엔드포인트. DB 연결 상태를 함께 확인합니다."""
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
        return Response({"status": "healthy", "database": "connected"})
    except Exception as e:
        return Response(
            {"status": "unhealthy", "database": str(e)},
            status=503,
        )
