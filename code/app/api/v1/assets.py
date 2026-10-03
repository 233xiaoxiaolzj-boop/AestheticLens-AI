from typing import List
from fastapi import APIRouter
from app.schemas.common import Envelope
from app.schemas.assets import FilterItem

router = APIRouter(prefix="/assets", tags=["📦 胶片滤镜与 3D LUT 资产 (Filter Assets)"])

# 4 套经典 512x512 3D LUT 真实元数据 (以 static/luts/ 为单一事实来源 SSOT)
FILTERS_DB = [
    FilterItem(
        lut_id="lut_film_warm_01",
        name_zh="落日暖调胶片",
        category="film",
        lut_url="/static/luts/lut_film_warm_01.png",
        thumbnail_url="/static/luts/lut_film_warm_01.png",
        md5="51345148ca63efa0bd4efddd49b4efe9"
    ),
    FilterItem(
        lut_id="lut_clean_bright_02",
        name_zh="清透质感人像",
        category="portrait",
        lut_url="/static/luts/lut_clean_bright_02.png",
        thumbnail_url="/static/luts/lut_clean_bright_02.png",
        md5="e14285993df00da59d5b207aa31ed629"
    ),
    FilterItem(
        lut_id="lut_cyber_teal_orange_03",
        name_zh="赛博青橙夜景",
        category="cyberpunk",
        lut_url="/static/luts/lut_cyber_teal_orange_03.png",
        thumbnail_url="/static/luts/lut_cyber_teal_orange_03.png",
        md5="11bc10681a33ee21cdb13714b2e26be7"
    ),
    FilterItem(
        lut_id="lut_mono_contrast_04",
        name_zh="德味高反差黑白",
        category="monochrome",
        lut_url="/static/luts/lut_mono_contrast_04.png",
        thumbnail_url="/static/luts/lut_mono_contrast_04.png",
        md5="9cf9ebe44f1d7374ae80532b8acc034e"
    )
]

@router.get(
    "/filters",
    response_model=Envelope[List[FilterItem]],
    summary="全量胶片滤镜与 3D LUT 资产清单同步",
    description="向 iPhone 手机端下发预置的 4 套经典胶片滤镜元数据，包含中英文名称、分类标签、云端 512x512 纹理下载链接与 MD5 校验和。",
    response_description="4 套经典胶片滤镜元数据清单"
)
def list_filters():
    return Envelope[List[FilterItem]](
        code=200,
        message="success",
        request_id="req_filters_list",
        data=FILTERS_DB
    )
