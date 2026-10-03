def test_analyze_composition_unauthorized(client):
    payload = {
        "client_version": "2.0.0",
        "device_info": {
            "platform": "ios",
            "focal_length_mm": 26.0,
            "sensor_attitude": {"pitch": -5.0, "roll": 0.5}
        },
        "image_meta": {"width": 720, "height": 960, "format": "jpeg"},
        "image_base64": "mock_valid_base64"
    }
    # 缺少 Authorization Header 应返回 401
    response = client.post("/api/v1/vision/analyze-composition", json=payload)
    assert response.status_code == 401
    assert response.json()["code"] == 40101

def test_analyze_composition_success(client, auth_headers):
    payload = {
        "client_version": "2.0.0",
        "device_info": {
            "platform": "ios",
            "focal_length_mm": 26.0,
            "sensor_attitude": {"pitch": -8.5, "roll": 1.2}
        },
        "image_meta": {"width": 720, "height": 960, "format": "jpeg"},
        "image_base64": "mock_valid_base64"
    }
    response = client.post("/api/v1/vision/analyze-composition", json=payload, headers=auth_headers)
    assert response.status_code == 200
    res_json = response.json()
    assert res_json["code"] == 200
    data = res_json["data"]
    assert "scene_analysis" in data
    assert "composition_guidance" in data
    assert "filter_recommendation" in data
    assert len(data["composition_guidance"]["coach_tip"]) <= 20
    assert 0.0 <= data["composition_guidance"]["suggested_crop_box"]["ymin"] <= 1.0

def test_analyze_composition_payload_too_large(client, auth_headers):
    # 模拟超过 200KB (200 * 1024 字节) 的超大载荷
    huge_base64 = "A" * (201 * 1024)
    payload = {
        "client_version": "2.0.0",
        "device_info": {
            "platform": "ios",
            "focal_length_mm": 26.0,
            "sensor_attitude": {"pitch": 0.0, "roll": 0.0}
        },
        "image_meta": {"width": 720, "height": 960, "format": "jpeg"},
        "image_base64": huge_base64
    }
    response = client.post("/api/v1/vision/analyze-composition", json=payload, headers=auth_headers)
    assert response.status_code == 413
    assert response.json()["code"] == 41301
