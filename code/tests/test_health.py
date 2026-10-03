def test_health_root(client):
    response = client.get("/health")
    assert response.status_code == 200
    res = response.json()
    assert res["status"] == "ok"
    assert "vlm_configured" in res
    assert "environment" in res
    assert "version" in res

def test_health_api_v1(client):
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    res = response.json()
    assert res["status"] == "ok"
    assert "vlm_configured" in res
    assert "environment" in res
    assert "version" in res
