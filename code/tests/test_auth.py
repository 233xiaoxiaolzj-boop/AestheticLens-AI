def test_device_register_success(client):
    payload = {
        "device_id": "test_device_sha256_hash",
        "app_version": "2.0.0",
        "platform": "ios"
    }
    response = client.post("/api/v1/auth/device-register", json=payload)
    assert response.status_code == 200
    res_json = response.json()
    assert res_json["code"] == 200
    assert res_json["message"] == "success"
    assert "token" in res_json["data"]
    assert res_json["data"]["expires_in"] == 30 * 24 * 3600
    assert res_json["data"]["daily_quota"]["analyze_composition_limit"] == 300
    assert res_json["data"]["daily_quota"]["analyze_and_grade_limit"] == 50

def test_device_register_missing_param(client):
    # 缺少 device_id 触发 400
    response = client.post("/api/v1/auth/device-register", json={"platform": "ios"})
    assert response.status_code == 400
    assert response.json()["code"] == 40001
