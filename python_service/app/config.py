import os


class Settings:
    """Single place to swap host/port. Bind 0.0.0.0 only when the phone reaches the server over Wi-Fi."""

    host: str = os.environ.get("VP_HOST", "127.0.0.1")
    port: int = int(os.environ.get("VP_PORT", "8088"))
    max_upload_mb: int = int(os.environ.get("VP_MAX_MB", "200"))
    job_ttl_s: int = 3600


settings = Settings()
