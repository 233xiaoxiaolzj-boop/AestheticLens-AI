import pytest
from app.core.config import settings
from app.core.security import verify_token
from fastapi.security import HTTPAuthorizationCredentials
from fastapi import HTTPException

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

def test_production_rejects_mock_token():
    # 模拟进入生产环境
    original_env = settings.ENVIRONMENT
    try:
        settings.ENVIRONMENT = "production"
        creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="mock_token_hacker_bypass")
        with pytest.raises(HTTPException) as exc_info:
            verify_token(creds)
        assert exc_info.value.status_code == 401
    finally:
        settings.ENVIRONMENT = original_env

def test_production_rejects_weak_secret():
    original_env = settings.ENVIRONMENT
    original_secret = settings.JWT_SECRET_KEY
    try:
        settings.ENVIRONMENT = "production"
        settings.JWT_SECRET_KEY = "dev_secret_key_change_in_production_32bytes_min"
        with pytest.raises(RuntimeError) as exc_info:
            settings.validate_production_secrets()
        assert "FATAL SECURITY" in str(exc_info.value)
    finally:
        settings.ENVIRONMENT = original_env
        settings.JWT_SECRET_KEY = original_secret
