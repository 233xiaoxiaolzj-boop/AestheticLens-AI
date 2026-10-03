def test_list_filters(client):
    response = client.get("/api/v1/assets/filters")
    assert response.status_code == 200
    res_json = response.json()
    assert res_json["code"] == 200
    assert len(res_json["data"]) == 4
    lut_ids = [item["lut_id"] for item in res_json["data"]]
    assert "lut_warm_film_03" in lut_ids
    assert "lut_cyber_neon_01" in lut_ids
