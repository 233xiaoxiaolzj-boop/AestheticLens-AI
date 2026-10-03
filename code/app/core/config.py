import os
from typing import Optional

class Settings:
    PROJECT_NAME: str = "AestheticLens-AI Cloud Gateway"
    VERSION: str = "2.0.0"
    API_V1_STR: str = "/api/v1"
    
    # 鉴权配置
    JWT_SECRET_KEY: str = os.getenv("JWT_SECRET_KEY", "dev_secret_key_change_in_production_32bytes_min")
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_SECONDS: int = 30 * 24 * 3600  # 30 天
    
    # 配额限制与滑动窗口
    VISION_RATE_INTERVAL_SECONDS: float = 1.5
    VISION_DAILY_LIMIT: int = 300
    RETOUCH_RATE_INTERVAL_SECONDS: float = 3.0
    RETOUCH_DAILY_LIMIT: int = 50
    
    # 载荷上限 (Payload Guard)
    VISION_PAYLOAD_LIMIT_BYTES: int = 200 * 1024       # 200 KB
    RETOUCH_PAYLOAD_LIMIT_BYTES: int = 2500 * 1024     # 2.5 MB
    
    # 阿里云百炼
    DASHSCOPE_API_KEY: Optional[str] = os.getenv("DASHSCOPE_API_KEY")

settings = Settings()
