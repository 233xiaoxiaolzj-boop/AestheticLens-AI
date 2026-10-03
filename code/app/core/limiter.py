import time
from typing import Dict, Tuple
from fastapi import HTTPException
from app.core.config import settings

class SlidingWindowLimiter:
    def __init__(self):
        # 记录: device_id -> (上次调用时间戳, 今日调用次数, 上次调用的日期YYYYMMDD)
        self._vision_records: Dict[str, Tuple[float, int, str]] = {}
        self._retouch_records: Dict[str, Tuple[float, int, str]] = {}

    def _today_str(self) -> str:
        return time.strftime("%Y%m%d", time.localtime())

    def check_vision_limit(self, device_id: str):
        now = time.time()
        today = self._today_str()
        
        last_time, count, date_str = self._vision_records.get(device_id, (0.0, 0, today))
        if date_str != today:
            count = 0
            date_str = today

        # 检查最小时间间隔 (1.5s)
        time_diff = now - last_time
        if time_diff < settings.VISION_RATE_INTERVAL_SECONDS:
            retry_after = int(settings.VISION_RATE_INTERVAL_SECONDS - time_diff) + 1
            raise HTTPException(
                status_code=429,
                detail={"code": 42901, "message": "取景抽帧请求过于频繁，请稍候再试", "data": None},
                headers={"Retry-After": str(retry_after)}
            )

        # 检查单日上限 (300 次)
        if count >= settings.VISION_DAILY_LIMIT:
            raise HTTPException(
                status_code=429,
                detail={"code": 42901, "message": "今日 AI 构图额度已用完 (300次/天)，已转入本地离线模式", "data": None},
                headers={"Retry-After": "86400"}
            )

        self._vision_records[device_id] = (now, count + 1, date_str)

    def check_retouch_limit(self, device_id: str):
        now = time.time()
        today = self._today_str()
        
        last_time, count, date_str = self._retouch_records.get(device_id, (0.0, 0, today))
        if date_str != today:
            count = 0
            date_str = today

        # 检查最小时间间隔 (3.0s)
        time_diff = now - last_time
        if time_diff < settings.RETOUCH_RATE_INTERVAL_SECONDS:
            retry_after = int(settings.RETOUCH_RATE_INTERVAL_SECONDS - time_diff) + 1
            raise HTTPException(
                status_code=429,
                detail={"code": 42901, "message": "拍后调色请求过于频繁，请稍候再试", "data": None},
                headers={"Retry-After": str(retry_after)}
            )

        # 检查单日上限 (50 次)
        if count >= settings.RETOUCH_DAILY_LIMIT:
            raise HTTPException(
                status_code=429,
                detail={"code": 42901, "message": "今日 AI 调色额度已用完 (50次/天)，已转入本地离线模式", "data": None},
                headers={"Retry-After": "86400"}
            )

        self._retouch_records[device_id] = (now, count + 1, date_str)

limiter = SlidingWindowLimiter()
