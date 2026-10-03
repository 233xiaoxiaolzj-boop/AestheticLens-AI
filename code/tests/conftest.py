import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.core.security import create_access_token

@pytest.fixture
def client():
    return TestClient(app)

@pytest.fixture
def auth_headers():
    token = create_access_token("test_device_uuid_12345")
    return {"Authorization": f"Bearer {token}"}
