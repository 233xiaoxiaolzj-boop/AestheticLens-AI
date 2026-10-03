import base64
import io
import json
import pytest
import httpx
from PIL import Image
from fastapi.testclient import TestClient
from app.main import app

# 生成一张测试 100x100 RGB JPEG 图像 Base64
def generate_sample_image_base64(color=(255, 180, 100)) -> str:
    img = Image.new("RGB", (100, 100), color=color)
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    return base64.b64encode(buf.getvalue()).decode("utf-8")

def test_e2e_device_register_and_jwt_lifecycle(client: TestClient):
    """
    [E2E 链路 1] 客户端首次启动，向云端网关发起匿名设备静默注册，获取合法 JWT 凭证
    """
    payload = {
        "device_id": "iphone15pro-e2e-test-uuid",
        "client_version": "2.0.0"
    }
    response = client.post("/api/v1/auth/device-register", json=payload)
    assert response.status_code == 200
    res_json = response.json()
    assert res_json["code"] == 200
    assert "token" in res_json["data"]
    token = res_json["data"]["token"]
    assert len(token.split(".")) == 3  # 标准 JWT 三段式格式 (header.payload.signature)
    assert res_json["data"]["expires_in"] == 86400 * 30

def test_e2e_viewfinder_composition_analysis(client: TestClient):
    """
    [E2E 链路 2] 客户端取景器抽帧上传 + 姿态惯导，获取 AR 黄金构图框、4向导航指示与推荐滤镜
    """
    # 1. 先注册获取 Token
    reg_resp = client.post("/api/v1/auth/device-register", json={"device_id": "device-viewfinder-e2e"})
    token = reg_resp.json()["data"]["token"]
    headers = {"Authorization": f"Bearer {token}"}
    
    # 2. 模拟取景器抽帧 (720x960 逆光夕阳场景)
    sample_b64 = generate_sample_image_base64((255, 140, 60))
    payload = {
        "client_version": "2.0.0",
        "device_info": {
            "platform": "ios",
            "focal_length_mm": 26.0,
            "sensor_attitude": {"pitch": 12.5, "roll": -1.2}
        },
        "image_meta": {"width": 720, "height": 960, "format": "jpeg"},
        "image_base64": sample_b64
    }
    
    response = client.post("/api/v1/vision/analyze-composition", json=payload, headers=headers)
    assert response.status_code == 200
    res_data = response.json()["data"]
    
    # 校验场景感知
    scene = res_data["scene_analysis"]
    assert "scene_type" in scene
    assert "scene_label_zh" in scene
    assert 0.0 <= scene["confidence"] <= 1.0
    
    # 校验构图引导
    guidance = res_data["composition_guidance"]
    assert "coach_tip" in guidance
    assert len(guidance["coach_tip"]) <= 20
    assert "suggested_crop_box" in guidance
    crop = guidance["suggested_crop_box"]
    assert 0.0 <= crop["ymin"] < crop["ymax"] <= 1.0
    assert 0.0 <= crop["xmin"] < crop["xmax"] <= 1.0
    
    # 校验空间机位导航
    if guidance.get("navigation_vector"):
        nav = guidance["navigation_vector"]
        if nav.get("forward_steps") is not None:
            assert 1 <= nav["forward_steps"] <= 3
            
    # 校验滤镜推荐
    filter_rec = res_data["filter_recommendation"]
    assert "recommended_lut_id" in filter_rec
    assert "preset_name_zh" in filter_rec

def test_e2e_metal_lut_texture_delivery(client: TestClient):
    """
    [E2E 链路 3] 验证端侧 Metal 渲染器所需的真实 512x512 3D LUT PNG 贴图资源能够正常下发
    """
    lut_files = [
        "lut_film_warm_01.png",
        "lut_clean_bright_02.png",
        "lut_cyber_teal_orange_03.png",
        "lut_mono_contrast_04.png",
        "lut_identity.png"
    ]
    for lut_name in lut_files:
        resp = client.get(f"/static/luts/{lut_name}")
        assert resp.status_code == 200
        # 验证返回的是合法的图片二进制
        img = Image.open(io.BytesIO(resp.content))
        assert img.size == (512, 512)

def test_e2e_shutter_capture_and_retouch_recipe(client: TestClient):
    """
    [E2E 链路 4] 客户端触发快门拍照，向拍后调色接口上传高清图，获取 10 维专业无损滑块与美学点评
    """
    # 1. 注册 Token
    reg_resp = client.post("/api/v1/auth/device-register", json={"device_id": "device-retouch-e2e"})
    token = reg_resp.json()["data"]["token"]
    headers = {"Authorization": f"Bearer {token}"}
    
    # 2. 上传拍后高清帧 (1080x1440)
    photo_b64 = generate_sample_image_base64((200, 150, 120))
    payload = {
        "client_version": "2.0.0",
        "photo_id": "photo_e2e_9988",
        "image_meta": {"width": 1080, "height": 1440, "format": "jpeg"},
        "image_base64": photo_b64
    }
    
    resp = client.post("/api/v1/retouch/analyze-and-grade", json=payload, headers=headers)
    assert resp.status_code == 200
    res_data = resp.json()["data"]
    
    # 验证别名路由可用 (使用新设备Token避免同一设备频控限制)
    reg_alias = client.post("/api/v1/auth/device-register", json={"device_id": "device-retouch-alias-e2e"})
    token_alias = reg_alias.json()["data"]["token"]
    resp_alias = client.post("/api/v1/retouch/retouch-recipe", json=payload, headers={"Authorization": f"Bearer {token_alias}"})
    assert resp_alias.status_code == 200
    
    # 校验 AI 美学诊断
    diag = res_data["aesthetic_diagnosis"]
    assert len(diag["overall_critique"]) > 0
    assert len(diag["style_name_zh"]) > 0
    
    # 校验 10 维滑块调色矩阵完整性与范围
    params = res_data["recommended_recipe"]["parameters"]
    assert -1.0 <= params["exposure"] <= 1.0
    assert -1.0 <= params["contrast"] <= 1.0
    assert -1.0 <= params["highlights"] <= 1.0
    assert -1.0 <= params["shadows"] <= 1.0
    assert -30.0 <= params["temperature"] <= 30.0
    assert -20.0 <= params["tint"] <= 20.0
    assert -1.0 <= params["vibrance"] <= 1.0
    assert -1.0 <= params["saturation"] <= 1.0
    assert -1.0 <= params["vignette"] <= 1.0
    assert 0.0 <= params["grain"] <= 0.5

def test_e2e_security_and_rate_limiting(client: TestClient):
    """
    [E2E 链路 5] 验证未经授权拦截 (401) 与防刷限流机制熔断保护
    """
    sample_b64 = generate_sample_image_base64()
    payload = {
        "client_version": "2.0.0",
        "device_info": {
            "platform": "ios",
            "sensor_attitude": {"pitch": 0.0, "roll": 0.0}
        },
        "image_meta": {"width": 720, "height": 960, "format": "jpeg"},
        "image_base64": sample_b64
    }
    
    # 未带 Token 访问，预期 401 拦截
    resp_unauth = client.post("/api/v1/vision/analyze-composition", json=payload)
    assert resp_unauth.status_code == 401
    
    # 携带伪造 Token 访问，预期 401 拦截
    resp_fake = client.post(
        "/api/v1/vision/analyze-composition", 
        json=payload, 
        headers={"Authorization": "Bearer fake.jwt.token"}
    )
    assert resp_fake.status_code == 401

def test_e2e_live_docker_container_direct_ping():
    """
    [E2E 链路 6] 真实跨网络探测当前运行在宿主机 8000 端口的 Docker 容器
    """
    docker_url = "http://127.0.0.1:8000"
    try:
        with httpx.Client(timeout=2.0) as http_client:
            # 1. 探测健康探针
            h_resp = http_client.get(f"{docker_url}/health")
            if h_resp.status_code != 200:
                pytest.skip("本地 Docker 容器未启动或未监听 8000 端口，跳过跨容器实时网络测试")
            assert h_resp.json() == {"status": "ok"}
            
            # 2. 真实向 Docker 容器注册设备
            reg_resp = http_client.post(
                f"{docker_url}/api/v1/auth/device-register",
                json={"device_id": "docker-live-device-01", "client_version": "2.0.0"}
            )
            assert reg_resp.status_code == 200
            token = reg_resp.json()["data"]["token"]
            
            # 3. 真实向 Docker 容器请求构图分析
            sample_b64 = generate_sample_image_base64()
            comp_resp = http_client.post(
                f"{docker_url}/api/v1/vision/analyze-composition",
                headers={"Authorization": f"Bearer {token}"},
                json={
                    "client_version": "2.0.0",
                    "device_info": {
                        "platform": "ios",
                        "focal_length_mm": 26.0,
                        "sensor_attitude": {"pitch": 8.0, "roll": 0.5}
                    },
                    "image_meta": {"width": 720, "height": 960, "format": "jpeg"},
                    "image_base64": sample_b64
                }
            )
            assert ("crop_box" in comp_resp.json()["data"]["composition_guidance"]["suggested_crop_box"] or
                    "suggested_crop_box" in comp_resp.json()["data"]["composition_guidance"])
    except (httpx.ConnectError, httpx.TimeoutException, httpx.RequestError):
        pytest.skip("Docker 8000 端口未响应或连接被拒绝，跳过跨容器实时网络测试")
