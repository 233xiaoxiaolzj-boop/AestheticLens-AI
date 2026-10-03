from fastapi import APIRouter

router = APIRouter(tags=["🩺 系统健康监测 (Health)"])

@router.get(
    "/health",
    summary="系统健康探测与连通性检查",
    description="供云平台容器探针（Zeabur / Docker）与手机 App 客户端进行网络连通性探测。免鉴权直接访问，正常返回状态为 ok。",
    response_description="服务连通正常状态"
)
def health_check():
    return {"status": "ok"}
