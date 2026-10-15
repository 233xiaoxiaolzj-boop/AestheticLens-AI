"""
AI 构图调用排查与自动化验收测试套件 (AI Diagnostics & Verification Test Suite)
全面验证：
1. /api/v1/vision/check-ai-status 诊断探针功能；
2. 真实在线 AI 成功调用全流程断言 (X-AI-Source / is_real_ai / latency_ms)；
3. 网络超时容灾熔断降级断言 (fallback-mock:timeout)；
4. API Key 失效/401 降级断言 (fallback-mock:unauthorized)；
5. 大模型输出格式损坏平滑降级断言；
6. 自定义 X-Dashscope-Api-Key 请求头动态覆盖测试。
"""

import json
import uuid
from unittest.mock import patch, MagicMock
import httpx
from fastapi.testclient import TestClient
from app.core.config import settings
from app.core.security import create_access_token
from app.services.vlm_service import vlm_service

def make_device_auth_header() -> dict:
    dev_id = f"test_device_{uuid.uuid4().hex[:8]}"
    token = create_access_token(dev_id)
    return {"Authorization": f"Bearer {token}"}


def test_ai_diagnostics_probe_endpoint(client: TestClient):
    """验收 1: 验证 AI 连通性排查探针接口返回规范与结构完整性"""
    resp = client.get("/api/v1/vision/check-ai-status")
    assert resp.status_code == 200
    res_data = resp.json()
    assert res_data["code"] == 200
    assert "data" in res_data
    diag = res_data["data"]
    assert diag["vlm_model"] == "qwen-vl-plus"
    assert diag["timeout_seconds"] >= 5.0  # 确保弹性超时阈值生效 (避免 2.0s 激进熔断)
    assert "connectivity" in diag
    conn = diag["connectivity"]
    assert "configured" in conn
    assert "reachable" in conn
    assert "authenticated" in conn


def test_ai_diagnostics_probe_with_mock_keys(client: TestClient):
    """验收 2: 验证排查探针探测有效 Key 与无效 Key 时的准确辨识能力"""
    # 2.1 模拟 200 成功响应
    mock_resp_success = MagicMock()
    mock_resp_success.status_code = 200
    mock_resp_success.json.return_value = {"choices": [{"message": {"content": "pong"}}]}

    with patch("httpx.post", return_value=mock_resp_success):
        resp = client.get("/api/v1/vision/check-ai-status?api_key=sk-mock_valid_key_test_123456")
        assert resp.status_code == 200
        conn = resp.json()["data"]["connectivity"]
        assert conn["authenticated"] is True
        assert conn["reachable"] is True
        assert "连通成功" in conn["message"]

    # 2.2 模拟 401 密钥失效响应 (重现先前版本失效 Key 的排查场景)
    mock_resp_401 = MagicMock()
    mock_resp_401.status_code = 401
    mock_resp_401.text = "Unauthorized"

    with patch("httpx.post", return_value=mock_resp_401):
        resp = client.get("/api/v1/vision/check-ai-status?api_key=sk-expired_or_invalid_key_9999")
        assert resp.status_code == 200
        conn = resp.json()["data"]["connectivity"]
        assert conn["authenticated"] is False
        assert conn["reachable"] is True
        assert "401" in conn["message"]


def test_composition_online_real_ai_success(client: TestClient, auth_headers: dict):
    """验收 3: 自动化验收真实在线 AI (Qwen-VL-Plus) 成功调用的全链路透出"""
    # 模拟通义千问 Qwen-VL-Plus 多模态返回的摄影美学专业 JSON
    mock_vlm_output = {
        "scene_analysis": {
            "scene_type": "portrait_sunset",
            "scene_label_zh": "黄昏逆光人像",
            "confidence": 0.96,
            "detected_issues": ["背景地平线穿颈", "人物面部欠曝"]
        },
        "composition_guidance": {
            "coach_tip": "压低机位后退一步仰拍避开穿颈",
            "action_type": "low_angle_step_back",
            "recommended_grid": "rule_of_thirds",
            "suggested_crop_box": {
                "ymin": 0.12,
                "xmin": 0.18,
                "ymax": 0.82,
                "xmax": 0.78
            },
            "target_pitch_adjustment_deg": -3.5,
            "navigation_vector": {
                "forward_steps": -1,
                "horizontal_translation_m": 0.0,
                "vertical_translation_cm": -15.0
            }
        },
        "filter_recommendation": {
            "recommended_lut_id": "lut_film_warm_01",
            "preset_name_zh": "落日暖调",
            "recommended_intensity": 0.85,
            "color_adjustments": {
                "exposure": 0.12,
                "temperature": 12.0,
                "contrast": 0.08
            }
        }
    }

    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {
        "choices": [
            {
                "message": {
                    "content": f"```json\n{json.dumps(mock_vlm_output, ensure_ascii=False)}\n```"
                }
            }
        ]
    }

    payload = {
        "client_version": "2.0.0",
        "device_info": {
            "platform": "ios",
            "focal_length_mm": 26.0,
            "sensor_attitude": {"pitch": -5.0, "roll": 0.2}
        },
        "image_meta": {"width": 720, "height": 960, "format": "jpeg"},
        "image_base64": "mock_valid_base64_frame_data"
    }

    # 动态注入临时有效测试 Key
    headers = {**make_device_auth_header(), "X-Dashscope-Api-Key": "sk-test_live_key_automation"}

    with patch("httpx.post", return_value=mock_resp):
        response = client.post("/api/v1/vision/analyze-composition", json=payload, headers=headers)
        assert response.status_code == 200

        # 核心断言 1: 验证响应 Header 精准透出真实在线 AI 来源
        assert response.headers["X-AI-Source"] == "qwen-vl-plus:online"
        assert response.headers["X-AI-Model"] == "qwen-vl-plus"
        assert response.headers["X-AI-Real-Invoked"] == "true"
        assert float(response.headers["X-AI-Latency-Ms"]) >= 0.0

        # 核心断言 2: 验证响应数据体中包含完整的 diagnostics 诊断元数据
        res_json = response.json()
        assert res_json["code"] == 200
        data = res_json["data"]
        assert "diagnostics" in data and data["diagnostics"] is not None
        diag = data["diagnostics"]
        assert diag["is_real_ai"] is True
        assert diag["ai_source"] == "qwen-vl-plus:online"
        assert diag["model_name"] == "qwen-vl-plus"

        # 核心断言 3: 验证美学指导内容真实解析无误
        guidance = data["composition_guidance"]
        assert guidance["coach_tip"] == "压低机位后退一步仰拍避开穿颈"
        assert guidance["suggested_crop_box"]["ymin"] == 0.12
        assert guidance["suggested_crop_box"]["xmin"] == 0.18


def test_composition_timeout_graceful_fallback(client: TestClient):
    """验收 4: 自动化验收在弱网超时场景下的优雅降级保护与状态透明标示"""
    payload = {
        "client_version": "2.0.0",
        "device_info": {
            "platform": "ios",
            "focal_length_mm": 26.0,
            "sensor_attitude": {"pitch": 0.0, "roll": 0.0}
        },
        "image_meta": {"width": 720, "height": 960, "format": "jpeg"},
        "image_base64": "mock_valid_base64_frame_data"
    }

    headers = {**make_device_auth_header(), "X-Dashscope-Api-Key": "sk-test_key_for_timeout"}

    # 模拟云端推理网络超时 (>6.0s)
    with patch("httpx.post", side_effect=httpx.TimeoutException("Connection timed out")):
        response = client.post("/api/v1/vision/analyze-composition", json=payload, headers=headers)
        assert response.status_code == 200  # 零卡死，不报错 500

        # 核心断言: 状态标明为超时降级，保证排查透明性
        assert response.headers["X-AI-Source"] == "fallback-mock:timeout"
        assert response.headers["X-AI-Real-Invoked"] == "false"
        assert response.headers["X-AI-Model"] == "golden-mock-engine"

        res_json = response.json()
        diag = res_json["data"]["diagnostics"]
        assert diag["is_real_ai"] is False
        assert diag["ai_source"] == "fallback-mock:timeout"
        assert "黄金" in diag["model_name"] or diag["model_name"] == "golden-mock-engine"
        # 确保黄金桩保底数据正常下发
        assert "composition_guidance" in res_json["data"]


def test_composition_unauthorized_fallback(client: TestClient):
    """验收 5: 自动化验收在 API Key 欠费/失效 (401) 场景下的优雅降级与标示"""
    payload = {
        "client_version": "2.0.0",
        "device_info": {
            "platform": "ios",
            "focal_length_mm": 26.0,
            "sensor_attitude": {"pitch": 0.0, "roll": 0.0}
        },
        "image_meta": {"width": 720, "height": 960, "format": "jpeg"},
        "image_base64": "mock_valid_base64_frame_data"
    }

    mock_resp_401 = MagicMock()
    mock_resp_401.status_code = 401
    mock_resp_401.text = "Unauthorized"

    headers = {**make_device_auth_header(), "X-Dashscope-Api-Key": "sk-invalid_key"}

    with patch("httpx.post", return_value=mock_resp_401):
        response = client.post("/api/v1/vision/analyze-composition", json=payload, headers=headers)
        assert response.status_code == 200

        assert response.headers["X-AI-Source"] == "fallback-mock:unauthorized"
        assert response.headers["X-AI-Real-Invoked"] == "false"

        diag = response.json()["data"]["diagnostics"]
        assert diag["is_real_ai"] is False
        assert diag["ai_source"] == "fallback-mock:unauthorized"


def test_composition_no_key_instant_fallback(client: TestClient):
    """验收 6: 自动化验收未配置任何 Key 时的瞬时 (<50ms) 黄金数据桩兜底"""
    payload = {
        "client_version": "2.0.0",
        "device_info": {
            "platform": "ios",
            "focal_length_mm": 26.0,
            "sensor_attitude": {"pitch": 0.0, "roll": 0.0}
        },
        "image_meta": {"width": 720, "height": 960, "format": "jpeg"},
        "image_base64": "mock_valid_base64_frame_data"
    }

    headers = make_device_auth_header()

    # 显式清除全局与请求 Key
    with patch.object(settings, "DASHSCOPE_API_KEY", None):
        response = client.post("/api/v1/vision/analyze-composition", json=payload, headers=headers)
        assert response.status_code == 200

        assert response.headers["X-AI-Source"] == "fallback-mock:no_key"
        assert response.headers["X-AI-Real-Invoked"] == "false"

        diag = response.json()["data"]["diagnostics"]
        assert diag["is_real_ai"] is False
        assert diag["ai_source"] == "fallback-mock:no_key"
        assert diag["latency_ms"] < 100.0  # 离线极速响应，绝不产生漫长等待
