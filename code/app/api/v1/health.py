from fastapi import APIRouter

router = APIRouter(tags=["🩺 系统健康监测 (Health)"])

from app.core.config import settings

@router.get(
    "/health",
    summary="系统健康探测与连通性检查",
    description="供云平台容器探针（Zeabur / Docker）与手机 App 客户端进行网络连通性探测。免鉴权直接访问，正常返回状态为 ok 并上报 VLM 配置情况与当前环境。",
    response_description="服务连通正常状态与关键运行时配置"
)
def health_check():
    return {
        "status": "ok",
        "vlm_configured": bool(settings.DASHSCOPE_API_KEY),
        "environment": settings.ENVIRONMENT,
        "version": settings.VERSION
    }
