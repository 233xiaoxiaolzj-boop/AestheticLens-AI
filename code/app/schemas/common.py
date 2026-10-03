from typing import Generic, Optional, TypeVar, Any
from pydantic import BaseModel
from enum import IntEnum

T = TypeVar("T")

class BusinessErrorCode(IntEnum):
    SUCCESS = 200
    BAD_REQUEST = 40001
    UNAUTHORIZED = 40101
    PAYLOAD_TOO_LARGE = 41301
    TOO_MANY_REQUESTS = 42901
    INTERNAL_SERVER_ERROR = 50001
    VLM_UPSTREAM_ERROR = 50201
    SERVICE_DEGRADED = 50301

class Envelope(BaseModel, Generic[T]):
    code: int = 200
    message: str = "success"
    request_id: str
    data: Optional[T] = None

class ErrorEnvelope(BaseModel):
    code: int
    message: str
    request_id: str
    data: Optional[Any] = None
