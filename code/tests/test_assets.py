def test_list_filters(client):
    response = client.get("/api/v1/assets/filters")
    assert response.status_code == 200
    res_json = response.json()
    assert res_json["code"] == 200
    assert len(res_json["data"]) == 4
    lut_ids = [item["lut_id"] for item in res_json["data"]]
    assert "lut_film_warm_01" in lut_ids
    assert "lut_clean_bright_02" in lut_ids
    assert "lut_cyber_teal_orange_03" in lut_ids
    assert "lut_mono_contrast_04" in lut_ids
    for item in res_json["data"]:
        assert item["lut_url"].startswith("/static/luts/")
        assert len(item["md5"]) == 32
