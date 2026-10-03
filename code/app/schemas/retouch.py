from typing import Optional
from pydantic import BaseModel
from app.schemas.vision import ImageMeta

class AnalyzeAndGradeRequest(BaseModel):
    client_version: str = "2.0.0"
    photo_id: str
    image_meta: ImageMeta
    image_base64: str

class AestheticDiagnosis(BaseModel):
    overall_critique: str
    target_style: str
    style_name_zh: str

class RecipeParameters(BaseModel):
    exposure: float = 0.0
    contrast: float = 0.0
    highlights: float = 0.0
    shadows: float = 0.0
    temperature: float = 0.0
    tint: float = 0.0
    vibrance: float = 0.0
    saturation: float = 0.0
    vignette: float = 0.0
    grain: float = 0.0

class RecommendedRecipe(BaseModel):
    lut_id: str
    lut_intensity: float = 0.85
    parameters: RecipeParameters

class AnalyzeAndGradeData(BaseModel):
    aesthetic_diagnosis: AestheticDiagnosis
    recommended_recipe: RecommendedRecipe

class VideoMeta(BaseModel):
    duration_sec: float
    width: int
    height: int
    fps: float = 60.0
    format: str = "mp4"

class KeyframeItem(BaseModel):
    timestamp_sec: float
    frame_index: int
    image_base64: str

class AnalyzeVideoRequest(BaseModel):
    client_version: str = "2.0.0"
    video_id: str
    video_meta: VideoMeta
    keyframes: list[KeyframeItem]

class VideoAestheticDiagnosis(BaseModel):
    overall_critique: str
    target_style: str
    style_name_zh: str
    camera_movement_critique: Optional[str] = "运镜稳定流畅"

class SceneContinuity(BaseModel):
    consistency_score: float = 0.90
    detected_flickers: bool = False

class VideoRetouchData(BaseModel):
    aesthetic_diagnosis: VideoAestheticDiagnosis
    recommended_recipe: RecommendedRecipe
    scene_continuity: Optional[SceneContinuity] = None

