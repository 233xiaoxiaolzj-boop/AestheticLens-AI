from pydantic import BaseModel

class FilterItem(BaseModel):
    lut_id: str
    name_zh: str
    category: str
    lut_url: str
    thumbnail_url: str
    md5: str
