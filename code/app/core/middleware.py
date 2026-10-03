import json
import logging
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse
from app.core.config import settings

logger = logging.getLogger("AestheticLensGateway")

class PayloadGuardMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # 针对抽帧与调色接口检查 Content-Length
        content_length = request.headers.get("content-length")
        path = request.url.path
        
        if content_length:
            try:
                length = int(content_length)
                if "/vision/analyze-composition" in path and length > settings.VISION_PAYLOAD_LIMIT_BYTES:
                    return JSONResponse(
                        status_code=413,
                        content={
                            "code": 41301,
                            "message": f"上传载荷超过安全阈值 (上限 {settings.VISION_PAYLOAD_LIMIT_BYTES // 1024} KB)",
                            "request_id": "req_err_413",
                            "data": None
                        }
                    )
                elif "/retouch/analyze-and-grade" in path and length > settings.RETOUCH_PAYLOAD_LIMIT_BYTES:
                    return JSONResponse(
                        status_code=413,
                        content={
                            "code": 41301,
                            "message": f"上传载荷超过安全阈值 (上限 {settings.RETOUCH_PAYLOAD_LIMIT_BYTES // 1024 // 1024} MB)",
                            "request_id": "req_err_413",
                            "data": None
                        }
                    )
            except (ValueError, TypeError):
                pass
        
        response = await call_next(request)
        return response
