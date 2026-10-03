from pydantic import BaseModel, Field

class DeviceRegisterRequest(BaseModel):
    device_id: str = Field(..., description="客户端设备的 SHA256 哈希唯一标识")
    app_version: str = Field("2.0.0", description="客户端应用版本号")
    platform: str = Field("ios", description="设备操作系统平台")

class DailyQuota(BaseModel):
    analyze_composition_limit: int = 300
    analyze_and_grade_limit: int = 50

class DeviceRegisterData(BaseModel):
    token: str
    expires_in: int
    daily_quota: DailyQuota
