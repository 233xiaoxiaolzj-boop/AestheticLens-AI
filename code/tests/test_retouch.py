def test_analyze_and_grade_unauthorized(client):
    payload = {
        "client_version": "2.0.0",
        "photo_id": "photo_001",
        "image_meta": {"width": 1920, "height": 1440, "format": "jpeg"},
        "image_base64": "mock_base64"
    }
    response = client.post("/api/v1/retouch/analyze-and-grade", json=payload)
    assert response.status_code == 401
    assert response.json()["code"] == 40101

def test_analyze_and_grade_success(client, auth_headers):
    payload = {
        "client_version": "2.0.0",
        "photo_id": "photo_001",
        "image_meta": {"width": 1920, "height": 1440, "format": "jpeg"},
        "image_base64": "mock_base64"
    }
    response = client.post("/api/v1/retouch/analyze-and-grade", json=payload, headers=auth_headers)
    assert response.status_code == 200
    res_json = response.json()
    assert res_json["code"] == 200
    data = res_json["data"]
    assert "aesthetic_diagnosis" in data
    assert "recommended_recipe" in data
    assert "parameters" in data["recommended_recipe"]
