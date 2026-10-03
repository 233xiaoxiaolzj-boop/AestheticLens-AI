from typing import List
from fastapi import APIRouter
from app.schemas.common import Envelope
from app.schemas.assets import FilterItem

router = APIRouter(prefix="/assets", tags=["📦 胶片滤镜与 3D LUT 资产 (Filter Assets)"])

# 4 套经典 LUT 基础元数据
FILTERS_DB = [
    FilterItem(
        lut_id="lut_warm_film_03",
        name_zh="落日余晖胶片",
        category="film",
        lut_url="https://assets.aestheticlens.ai/luts/lut_warm_film_03.png",
        thumbnail_url="https://assets.aestheticlens.ai/thumbnails/lut_warm_film_03.jpg",
        md5="e8b5c92f1d4a6789e0bc123456789abc"
    ),
    FilterItem(
        lut_id="lut_cyber_neon_01",
        name_zh="赛博霓虹夜景",
        category="cyberpunk",
        lut_url="https://assets.aestheticlens.ai/luts/lut_cyber_neon_01.png",
        thumbnail_url="https://assets.aestheticlens.ai/thumbnails/lut_cyber_neon_01.jpg",
        md5="a1b2c3d4e5f67890123456789abcdef0"
    ),
    FilterItem(
        lut_id="lut_minimal_bw_02",
        name_zh="德味高反差黑白",
        category="monochrome",
        lut_url="https://assets.aestheticlens.ai/luts/lut_minimal_bw_02.png",
        thumbnail_url="https://assets.aestheticlens.ai/thumbnails/lut_minimal_bw_02.jpg",
        md5="c4d5e6f7a8b90123456789abcdef0123"
    ),
    FilterItem(
        lut_id="lut_vintage_green_04",
        name_zh="清冷质感绿调",
        category="vintage",
        lut_url="https://assets.aestheticlens.ai/luts/lut_vintage_green_04.png",
        thumbnail_url="https://assets.aestheticlens.ai/thumbnails/lut_vintage_green_04.jpg",
        md5="f9e8d7c6b5a43210987654321fedcba9"
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
