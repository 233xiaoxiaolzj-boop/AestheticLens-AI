import uuid
from fastapi import APIRouter, Depends, HTTPException, Response
from app.schemas.common import Envelope
from app.schemas.retouch import (
    AnalyzeAndGradeRequest,
    AnalyzeAndGradeData,
    AnalyzeVideoRequest,
    VideoRetouchData
)
from app.core.security import verify_token
from app.core.limiter import limiter
from app.core.config import settings
from app.services.vlm_service import vlm_service

router = APIRouter(prefix="/retouch", tags=["🎨 拍后智能美学诊断与色彩配方 (Post Retouch)"])

@router.post(
    "/analyze-and-grade",
    response_model=Envelope[AnalyzeAndGradeData],
    summary="拍后智能美学诊断与胶片调色参数输出",
    description="""
接收拍摄完成的高清照片，执行多维度深度美学诊断并输出 10 项专业无损调色滑块配方：
1. **美学诊断**：针对光质反差、高光暗部、色彩调和给出大师级美学评价；
2. **专业 10 项可逆参数**：
   - 基础光影：曝光 (exposure)、对比度 (contrast)、高光 (highlights)、阴影 (shadows)；
   - 色彩科学：色温 (temperature)、色调 (tint)、自然饱和度 (vibrance)、纯饱和度 (saturation)；
   - 质感风格：暗角 (vignette)、噪点颗粒 (grain)；
3. **色彩安全护栏**：严格限制极端过冲，保护自然肤色通透感；
4. **推荐滤镜**：匹配最契合意境的 3D LUT 胶片预设。
    """,
    response_description="AI 美学诊断评论与 10 项专业调色滑块配方"
)
def analyze_and_grade(
    payload: AnalyzeAndGradeRequest,
    response: Response,
    device_id: str = Depends(verify_token)
):
    if len(payload.image_base64) > settings.RETOUCH_PAYLOAD_LIMIT_BYTES:
        raise HTTPException(
            status_code=413,
            detail={
                "code": 41301,
                "message": f"Base64 载荷超过上限 ({settings.RETOUCH_PAYLOAD_LIMIT_BYTES // 1024 // 1024} MB)",
                "data": None
            }
        )
    
    limiter.check_retouch_limit(device_id)
    
    analysis_data = vlm_service.analyze_retouch(payload)
    req_id = f"req_{uuid.uuid4().hex[:12]}"
    
    # 注入真实模型溯源响应头
    response.headers["X-AI-Source"] = "qwen-vl-plus" if settings.DASHSCOPE_API_KEY else "fallback-mock"
    
    return Envelope[AnalyzeAndGradeData](
        code=200,
        message="success",
        request_id=req_id,
        data=analysis_data
    )

@router.post(
    "/analyze-video",
    response_model=Envelope[VideoRetouchData],
    summary="成品视频多关键帧 AI 美学诊断与全局调色配方",
    description="""
接收视频多张关键帧（建议3张典型帧）与时长帧率元数据：
1. **多帧全局光影诊断**：分析全片动态范围与运镜平稳度；
2. **全局母版调色配方 (Master Recipe)**：输出 10 项专业无损调色滑块矩阵；
3. **推荐视频 3D LUT**：匹配赛博青橙、电影宽银幕、落日胶片等高阶动态风格。
    """,
    response_description="视频美学诊断、运镜评价与 10 项调色滑块配方"
)
def analyze_video(
    payload: AnalyzeVideoRequest,
    response: Response,
    device_id: str = Depends(verify_token)
):
    # 视频关键帧载荷守卫：多帧 Base64 总体积限制在 2.5MB
    total_frames_bytes = sum(len(f.image_base64) for f in payload.keyframes)
    if total_frames_bytes > settings.RETOUCH_PAYLOAD_LIMIT_BYTES:
        raise HTTPException(
            status_code=413,
            detail={
                "code": 41301,
                "message": f"视频关键帧总载荷超过上限 ({settings.RETOUCH_PAYLOAD_LIMIT_BYTES // 1024 // 1024} MB)",
                "data": None
            }
        )

    limiter.check_retouch_limit(device_id)
    analysis_data = vlm_service.analyze_video(payload)
    req_id = f"req_{uuid.uuid4().hex[:12]}"
    
    # 注入真实模型溯源响应头
    response.headers["X-AI-Source"] = "qwen-vl-plus" if settings.DASHSCOPE_API_KEY else "fallback-mock"
    
    return Envelope[VideoRetouchData](
        code=200,
        message="success",
        request_id=req_id,
        data=analysis_data
    )

