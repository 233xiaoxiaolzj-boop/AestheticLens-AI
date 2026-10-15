import os
from pathlib import Path
from typing import Optional

def _load_dotenv_file():
    """轻量加载本地 .env 文件环境变量 (无需额外三方依赖)"""
    current = Path(__file__).resolve()
    for parent in [current.parent, current.parents[1], current.parents[2]]:
        env_file = parent / ".env"
        if env_file.exists():
            try:
                with open(env_file, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith("#") and "=" in line:
                            k, v = line.split("=", 1)
                            k, v = k.strip(), v.strip().strip("'\"")
                            if k not in os.environ:
                                os.environ[k] = v
            except Exception:
                pass
            break

_load_dotenv_file()

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
    
    # 运行环境与生产自检
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
    
    # 阿里云百炼
    DASHSCOPE_API_KEY: Optional[str] = os.getenv("DASHSCOPE_API_KEY")
    # 视觉大模型弹性超时时间 (默认 6.0 秒，避免多模态推理生成被 2.0s 误熔断)
    VLM_TIMEOUT_SECONDS: float = float(os.getenv("VLM_TIMEOUT_SECONDS", "6.0"))

    def validate_production_secrets(self) -> None:
        """生产环境启动硬安全断言检查"""
        if self.ENVIRONMENT == "production":
            weak_keys = {
                "dev_secret_key_change_in_production_32bytes_min",
                "aestheticlens_dev_secret_key_2026",
                "AestheticLens_Secret_2026_Key",
                "secret",
                "123456"
            }
            if not self.JWT_SECRET_KEY or self.JWT_SECRET_KEY in weak_keys or len(self.JWT_SECRET_KEY) < 32:
                raise RuntimeError(
                    "[FATAL SECURITY] 生产环境 (ENVIRONMENT=production) 必须配置高强度随机 JWT_SECRET_KEY (至少32字符)，且严禁使用默认弱密钥！"
                )

settings = Settings()
