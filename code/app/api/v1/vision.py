import uuid
from fastapi import APIRouter, Depends, HTTPException, Response
from app.schemas.common import Envelope
from app.schemas.vision import AnalyzeCompositionRequest, AnalyzeCompositionData
from app.core.security import verify_token
from app.core.limiter import limiter
from app.core.config import settings
from app.services.vlm_service import vlm_service

router = APIRouter(prefix="/vision", tags=["👁️ 实时取景构图与机位空间导航 (Live Vision)"])

@router.post(
    "/analyze-composition",
    response_model=Envelope[AnalyzeCompositionData],
    summary="实时取景抽帧分析与机位微调导航",
    description="""
接收 iPhone 相机取景器抽帧图像（长边 720px，Base64 编码，上限 200KB）与 CoreMotion 陀螺仪姿态（Pitch / Roll 倾角）：
1. **限流保护**：同一设备调用频次严格限制为 **1.5 秒/次**，超过将触发 429 与 `Retry-After`；
2. **美学专家 Skill 分析**：前置识别画面构图缺陷（如穿颈、头顶留白大、中轴偏移），给出动词开头的物理机位微动作指令（如“前进两步放低机位仰拍”，严格不超过 20 字）；
3. **空间导航向量**：下发步数、横向平移与高度升降厘米数；
4. **容灾双保险**：若遭遇弱网超时（>2.0s）或无 API Key，自动平滑降级至本地黄金数据桩，确保真机演示零卡顿！
    """,
    response_description="构图裁剪框、机位微动指令与推荐滤镜"
)
def analyze_composition(
    payload: AnalyzeCompositionRequest,
    response: Response,
    device_id: str = Depends(verify_token)
):
    # 1. 载荷大小兜底校验 (Base64 上限 200KB)
    if len(payload.image_base64) > settings.VISION_PAYLOAD_LIMIT_BYTES:
        raise HTTPException(
            status_code=413,
            detail={
                "code": 41301,
                "message": f"Base64 载荷超过上限 ({settings.VISION_PAYLOAD_LIMIT_BYTES // 1024} KB)",
                "data": None
            }
        )
    
    # 2. 滑动窗口限流校验
    limiter.check_vision_limit(device_id)
    
    # 3. 通过 VLM 服务中台执行摄影美学 Skill 分析 (在线/降级双保险)
    analysis_data = vlm_service.analyze_composition(payload)
    req_id = f"req_{uuid.uuid4().hex[:12]}"
    response.headers["X-AI-Source"] = "qwen-vl-plus" if settings.DASHSCOPE_API_KEY else "fallback-mock"
    
    return Envelope[AnalyzeCompositionData](
        code=200,
        message="success",
        request_id=req_id,
        data=analysis_data
    )
