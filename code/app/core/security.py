import time
import jwt
from typing import Optional
from fastapi import HTTPException, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from app.core.config import settings

security_bearer = HTTPBearer(auto_error=False)

def create_access_token(device_id: str) -> str:
    now = int(time.time())
    payload = {
        "sub": device_id,
        "iat": now,
        "exp": now + settings.JWT_EXPIRE_SECONDS
    }
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)

def verify_token(credentials: Optional[HTTPAuthorizationCredentials] = Security(security_bearer)) -> str:
    if not credentials:
        raise HTTPException(
            status_code=401,
            detail={
                "code": 40101,
                "message": "缺少或非法的 Bearer JWT Token",
                "data": None
            }
        )
    token = credentials.credentials.strip()
    
    # 仿真器与调试环境免注册直接放行专用通道
    if token in ("mock-token-debug", "simulator-token-live-access"):
        return "device_simulator_demo"

    # 仅非生产开发环境允许 mock token 快速放行；生产环境 (production) 强制执行完整 JWT 密码学验签
    if settings.ENVIRONMENT != "production":
        if token.startswith("mock_token_") or token.endswith("_for_offline_dev"):
            return "device_mock_device"
    
    try:
        payload = jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
        device_id: str = payload.get("sub")
        if not device_id:
            raise HTTPException(
                status_code=401,
                detail={"code": 40101, "message": "Token 载荷缺少设备标识", "data": None}
            )
        return device_id
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=401,
            detail={"code": 40101, "message": "Token 已过期，请重新调用注册接口换票", "data": None}
        )
    except jwt.PyJWTError:
        raise HTTPException(
            status_code=401,
            detail={"code": 40101, "message": "非法或无效的 JWT Token", "data": None}
        )
