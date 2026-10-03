from app.core.security import create_access_token

def test_rate_limiter_trigger(client):
    device_id = "device_rate_limit_test_999"
    token = create_access_token(device_id)
    headers = {"Authorization": f"Bearer {token}"}
    
    payload = {
        "client_version": "2.0.0",
        "device_info": {
            "platform": "ios",
            "focal_length_mm": 26.0,
            "sensor_attitude": {"pitch": 0.0, "roll": 0.0}
        },
        "image_meta": {"width": 720, "height": 960, "format": "jpeg"},
        "image_base64": "mock_valid_base64"
    }
    
    # 第一次请求成功
    resp1 = client.post("/api/v1/vision/analyze-composition", json=payload, headers=headers)
    assert resp1.status_code == 200
    
    # 紧接着立即发起第二次请求（间隔远小于 1.5s），应触发 429
    resp2 = client.post("/api/v1/vision/analyze-composition", json=payload, headers=headers)
    assert resp2.status_code == 429
    assert resp2.json()["code"] == 42901
    assert "Retry-After" in resp2.headers
