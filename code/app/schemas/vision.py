from typing import List, Optional
from pydantic import BaseModel, Field

class SensorAttitude(BaseModel):
    pitch: float
    roll: float

class DeviceInfo(BaseModel):
    platform: str = "ios"
    focal_length_mm: Optional[float] = 26.0
    sensor_attitude: SensorAttitude

class ImageMeta(BaseModel):
    width: int
    height: int
    format: str = "jpeg"

class AnalyzeCompositionRequest(BaseModel):
    client_version: Optional[str] = "2.0.0"
    device_info: Optional[DeviceInfo] = None
    image_meta: Optional[ImageMeta] = None
    image_base64: str
    # 扁平请求兼容字段
    pitch: Optional[float] = 0.0
    roll: Optional[float] = 0.0

    def model_post_init(self, __context):
        if self.device_info is None:
            self.device_info = DeviceInfo(
                platform="ios",
                focal_length_mm=26.0,
                sensor_attitude=SensorAttitude(pitch=self.pitch or 0.0, roll=self.roll or 0.0)
            )
        if self.image_meta is None:
            self.image_meta = ImageMeta(width=720, height=960, format="jpeg")

class CropBox(BaseModel):
    ymin: float = Field(..., ge=0.0, le=1.0)
    xmin: float = Field(..., ge=0.0, le=1.0)
    ymax: float = Field(..., ge=0.0, le=1.0)
    xmax: float = Field(..., ge=0.0, le=1.0)

class NavigationVector(BaseModel):
    forward_steps: Optional[int] = Field(None, ge=1, le=3)
    horizontal_translation_m: Optional[float] = Field(None, ge=-1.0, le=1.0)
    vertical_translation_cm: Optional[float] = Field(None, ge=-30.0, le=30.0)

class SceneAnalysis(BaseModel):
    scene_type: str
    scene_label_zh: str
    confidence: float
    detected_issues: List[str] = []

class CompositionGuidance(BaseModel):
    coach_tip: str = Field(..., max_length=20)
    action_type: str
    recommended_grid: str
    suggested_crop_box: CropBox
    target_pitch_adjustment_deg: Optional[float] = 0.0
    navigation_vector: Optional[NavigationVector] = None

class ColorAdjustments(BaseModel):
    exposure: Optional[float] = 0.0
    temperature: Optional[float] = 0.0
    contrast: Optional[float] = 0.0

class FilterRecommendation(BaseModel):
    recommended_lut_id: str
    preset_name_zh: str
    recommended_intensity: float = 0.85
    color_adjustments: Optional[ColorAdjustments] = None

class AIDiagnostics(BaseModel):
    is_real_ai: bool = Field(False, description="是否真实调用了在线大模型")
    ai_source: str = Field(..., description="调用源标识，如 qwen-vl-plus:online / fallback-mock:no_key / fallback-mock:timeout")
    model_name: str = Field("golden-mock-engine", description="生效模型名称")
    latency_ms: float = Field(0.0, description="端到端处理耗时(毫秒)")
    detail: Optional[str] = Field(None, description="详细诊断或降级原因")

class AnalyzeCompositionData(BaseModel):
    scene_analysis: SceneAnalysis
    composition_guidance: CompositionGuidance
    filter_recommendation: FilterRecommendation
    diagnostics: Optional[AIDiagnostics] = Field(None, description="AI 调用诊断监控元数据")

