import base64
import io
import pytest
from PIL import Image
from fastapi.testclient import TestClient

def generate_test_keyframe(color=(120, 180, 240)) -> str:
    img = Image.new("RGB", (100, 100), color=color)
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    return base64.b64encode(buf.getvalue()).decode("utf-8")

def test_analyze_video_unauthorized(client: TestClient):
    """验证未提供 JWT Token 时访问视频调色接口被 401 拦截"""
    payload = {
        "client_version": "2.0.0",
        "video_id": "vid_unauth_001",
        "video_meta": {"duration_sec": 12.0, "width": 1920, "height": 1080, "fps": 60.0, "format": "mp4"},
        "keyframes": [
            {"timestamp_sec": 0.0, "frame_index": 0, "image_base64": generate_test_keyframe()}
        ]
    }
    resp = client.post("/api/v1/retouch/analyze-video", json=payload)
    assert resp.status_code == 401

def test_analyze_video_success(client: TestClient):
    """验证提供3张关键帧时，成功输出全局视频调色配方与运镜美学诊断"""
    from app.core.security import create_access_token
    token = create_access_token("video_test_exclusive_device_001")
    auth_headers = {"Authorization": f"Bearer {token}"}
    
    kf1 = generate_test_keyframe((100, 150, 200))
    kf2 = generate_test_keyframe((120, 160, 220))
    kf3 = generate_test_keyframe((80, 130, 190))
    
    payload = {
        "client_version": "2.0.0",
        "video_id": "vid_test_cinematic_01",
        "video_meta": {
            "duration_sec": 15.5,
            "width": 1920,
            "height": 1080,
            "fps": 60.0,
            "format": "mp4"
        },
        "keyframes": [
            {"timestamp_sec": 0.0, "frame_index": 0, "image_base64": kf1},
            {"timestamp_sec": 7.5, "frame_index": 450, "image_base64": kf2},
            {"timestamp_sec": 14.0, "frame_index": 840, "image_base64": kf3}
        ]
    }
    
    resp = client.post("/api/v1/retouch/analyze-video", json=payload, headers=auth_headers)
    assert resp.status_code == 200
    res_json = resp.json()
    assert res_json["code"] == 200
    data = res_json["data"]
    
    # 验证视频美学诊断与运镜评价
    diag = data["aesthetic_diagnosis"]
    assert "overall_critique" in diag
    assert "style_name_zh" in diag
    assert "camera_movement_critique" in diag
    
    # 验证全局母版调色配方
    recipe = data["recommended_recipe"]
    assert "lut_id" in recipe
    assert 0.0 <= recipe["lut_intensity"] <= 1.0
    params = recipe["parameters"]
    assert -1.0 <= params["exposure"] <= 1.0
    assert -1.0 <= params["contrast"] <= 1.0
    assert -30.0 <= params["temperature"] <= 30.0
    assert -1.0 <= params["vignette"] <= 1.0
    
    # 验证视频连贯性评价
    if data.get("scene_continuity"):
        cont = data["scene_continuity"]
        assert 0.0 <= cont["consistency_score"] <= 1.0
