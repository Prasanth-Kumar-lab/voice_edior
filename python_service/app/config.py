from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import List


def _parse_origins(raw: str) -> List[str]:
    items = [x.strip() for x in raw.split(",") if x.strip()]
    return items or [
        "https://voice-edior.onrender.com",
        "http://127.0.0.1:8088",
        "http://localhost:8088",
        "http://10.0.2.2:8088",
    ]


@dataclass(frozen=True)
class Settings:
    target_sr: int = 48_000
    podcast_lufs: float = -16.0
    vocals_lufs: float = -14.0
    true_peak_dbtp: float = -1.0
    max_upload_mb: int = int(os.getenv("VP_MAX_MB", "80"))
    workers: int = int(os.getenv("VP_WORKERS", "2"))
    jwt_secret: str = os.getenv(
        "VP_JWT_SECRET",
        "vp_prod_hmac_secret_9f8e7d6c5b4a392817263544536271809a8b7c6d5e4f",
    )
    access_token_ttl_sec: int = int(os.getenv("VP_ACCESS_TOKEN_TTL", "3600"))
    refresh_token_ttl_sec: int = int(os.getenv("VP_REFRESH_TOKEN_TTL", str(30 * 86400)))
    rate_limit_per_min: int = int(os.getenv("VP_RATE_LIMIT_PER_MIN", "30"))
    enhance_rate_limit_per_min: int = int(os.getenv("VP_ENHANCE_RATE_LIMIT_PER_MIN", "12"))
    billing_secret: str = os.getenv("VP_BILLING_SECRET", "")
    allowed_origins: List[str] = field(
        default_factory=lambda: _parse_origins(os.getenv("VP_ALLOWED_ORIGINS", ""))
    )


settings = Settings()
