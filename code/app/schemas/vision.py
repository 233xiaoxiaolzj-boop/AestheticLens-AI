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
    client_version: str = "2.0.0"
    device_info: DeviceInfo
    image_meta: ImageMeta
    image_base64: str

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

class AnalyzeCompositionData(BaseModel):
    scene_analysis: SceneAnalysis
    composition_guidance: CompositionGuidance
    filter_recommendation: FilterRecommendation
