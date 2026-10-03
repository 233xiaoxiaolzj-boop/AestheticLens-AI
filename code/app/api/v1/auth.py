import uuid
from fastapi import APIRouter
from app.schemas.common import Envelope
from app.schemas.auth import DeviceRegisterRequest, DeviceRegisterData, DailyQuota
from app.core.security import create_access_token
from app.core.config import settings

router = APIRouter(prefix="/auth", tags=["🔐 设备认证与鉴权 (Device Auth)"])

@router.post(
    "/device-register",
    response_model=Envelope[DeviceRegisterData],
    summary="设备首次激活注册与 JWT 令牌签发",
    description="""
接收手机端设备唯一指纹与平台标识，签发 30 天有效期的 JWT Bearer Token，并返回该设备的单日调用配额：
* **取景分析日配额**：300 次/天
* **拍后调色日配额**：50 次/天
后续受保护接口需在请求头携带：`Authorization: Bearer <token>`。
    """,
    response_description="设备注册成功并返回 Token 与每日配额"
)
def register_device(payload: DeviceRegisterRequest):
    req_id = f"req_{uuid.uuid4().hex[:12]}"
    token = create_access_token(payload.device_id)
    
    data = DeviceRegisterData(
        token=token,
        expires_in=settings.JWT_EXPIRE_SECONDS,
        daily_quota=DailyQuota(
            analyze_composition_limit=settings.VISION_DAILY_LIMIT,
            analyze_and_grade_limit=settings.RETOUCH_DAILY_LIMIT
        )
    )
    return Envelope[DeviceRegisterData](
        code=200,
        message="success",
        request_id=req_id,
        data=data
    )
