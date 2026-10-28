"""Authentication, per-user salted password hashing, JWT tokens, rate limiting, and upload validation."""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import threading
import time
from typing import Any, Dict, Optional, Tuple

from fastapi import Depends, Header, HTTPException, Request

from .config import settings


# ───────────────────────────── PASSWORD HASHING (SCRYPT + LEGACY MIGRATION) ─────────────────────────────

_SCRYPT_N = 16384
_SCRYPT_R = 8
_SCRYPT_P = 1
_SCRYPT_DKLEN = 64


def hash_password(password: str) -> str:
    """Hash a password using RFC-7914 scrypt with a unique 16-byte cryptographic salt per user."""
    salt = secrets.token_bytes(16)
    derived = hashlib.scrypt(
        password.encode("utf-8"),
        salt=salt,
        n=_SCRYPT_N,
        r=_SCRYPT_R,
        p=_SCRYPT_P,
        dklen=_SCRYPT_DKLEN,
    )
    return f"scrypt${_SCRYPT_N}${_SCRYPT_R}${_SCRYPT_P}${salt.hex()}${derived.hex()}"


def _legacy_sha256(password: str) -> str:
    return hashlib.sha256(f"vp_salt_{password}".encode("utf-8")).hexdigest()


def verify_password(plain_password: str, stored_hash: str) -> Tuple[bool, bool]:
    """Verify `plain_password` against `stored_hash`.

    Returns `(is_valid, needs_rehash)`.
    Automatically detects legacy static-salt SHA-256 hashes and flags them for
    transparent upgrade to per-user salted `scrypt` on successful login.
    """
    if not stored_hash or not plain_password:
        return False, False

    if stored_hash.startswith("scrypt$"):
        try:
            parts = stored_hash.split("$")
            if len(parts) != 6:
                return False, False
            _, n_str, r_str, p_str, salt_hex, expected_hex = parts
            salt = bytes.fromhex(salt_hex)
            expected = bytes.fromhex(expected_hex)
            derived = hashlib.scrypt(
                plain_password.encode("utf-8"),
                salt=salt,
                n=int(n_str),
                r=int(r_str),
                p=int(p_str),
                dklen=len(expected),
            )
            return hmac.compare_digest(derived, expected), False
        except Exception:
            return False, False

    # Legacy 64-character hex SHA-256 migration path
    if len(stored_hash) == 64:
        legacy_candidate = _legacy_sha256(plain_password)
        if hmac.compare_digest(legacy_candidate, stored_hash):
            return True, True

    return False, False


# ───────────────────────────── RFC-7519 JWT (HS256) ─────────────────────────────

def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64url_decode(segment: str) -> bytes:
    padding = "=" * (-len(segment) % 4)
    return base64.urlsafe_b64decode((segment + padding).encode("ascii"))


def _encode_jwt(payload: Dict[str, Any]) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    h_b64 = _b64url_encode(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    p_b64 = _b64url_encode(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signing_input = f"{h_b64}.{p_b64}".encode("ascii")
    sig = hmac.new(settings.jwt_secret.encode("utf-8"), signing_input, hashlib.sha256).digest()
    return f"{h_b64}.{p_b64}.{_b64url_encode(sig)}"


def decode_token(token: str, expected_type: Optional[str] = "access") -> Dict[str, Any]:
    try:
        parts = token.strip().split(".")
        if len(parts) != 3:
            raise ValueError("Invalid token format")
        h_b64, p_b64, s_b64 = parts
        signing_input = f"{h_b64}.{p_b64}".encode("ascii")
        expected_sig = hmac.new(
            settings.jwt_secret.encode("utf-8"), signing_input, hashlib.sha256
        ).digest()
        actual_sig = _b64url_decode(s_b64)
        if not hmac.compare_digest(expected_sig, actual_sig):
            raise ValueError("Invalid token signature")
        payload = json.loads(_b64url_decode(p_b64).decode("utf-8"))
        now = int(time.time())
        if int(payload.get("exp", 0)) < now:
            raise ValueError("Token expired")
        if expected_type and payload.get("type") != expected_type:
            raise ValueError(f"Expected {expected_type} token")
        return payload
    except ValueError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid authentication token") from exc


def create_access_token(user_id: str, email: str, role_type: str = "user") -> str:
    now = int(time.time())
    return _encode_jwt({
        "sub": user_id,
        "email": email.lower().strip(),
        "role_type": role_type,
        "type": "access",
        "iat": now,
        "exp": now + settings.access_token_ttl_sec,
        "jti": secrets.token_hex(8),
    })


def create_refresh_token(user_id: str, email: str, role_type: str = "user") -> str:
    now = int(time.time())
    return _encode_jwt({
        "sub": user_id,
        "email": email.lower().strip(),
        "role_type": role_type,
        "type": "refresh",
        "iat": now,
        "exp": now + settings.refresh_token_ttl_sec,
        "jti": secrets.token_hex(12),
    })


# ───────────────────────────── FASTAPI AUTH DEPENDENCIES ─────────────────────────────

def _extract_bearer(authorization: Optional[str]) -> Optional[str]:
    if not authorization:
        return None
    parts = authorization.strip().split(" ", 1)
    if len(parts) == 2 and parts[0].lower() == "bearer" and parts[1].strip():
        return parts[1].strip()
    return None


def get_optional_user(authorization: Optional[str] = Header(default=None)) -> Optional[Dict[str, Any]]:
    token = _extract_bearer(authorization)
    if not token:
        return None
    payload = decode_token(token, expected_type="access")
    from .db import get_db

    db = get_db()
    user = db.users.find_one({"id": payload.get("sub")}) or db.users.find_one(
        {"email": payload.get("email")}
    )
    if not user:
        raise HTTPException(status_code=401, detail="User no longer exists")
    if user.get("status") != "active":
        raise HTTPException(status_code=403, detail="Account has been deactivated")
    return user


def get_current_user(authorization: Optional[str] = Header(default=None)) -> Dict[str, Any]:
    token = _extract_bearer(authorization)
    if not token:
        raise HTTPException(status_code=401, detail="Missing Authorization Bearer token")
    user = get_optional_user(authorization)
    if not user:
        raise HTTPException(status_code=401, detail="Authentication required")
    return user


def require_admin(user: Dict[str, Any] = Depends(get_current_user)) -> Dict[str, Any]:
    role_type = str(user.get("role_type", "user")).lower()
    if role_type != "admin" and not user.get("is_admin", False):
        raise HTTPException(status_code=403, detail="Administrator privileges required")
    return user


# ───────────────────────────── TOKEN-BUCKET RATE LIMITER ─────────────────────────────

class TokenBucketLimiter:
    """Thread-safe sliding-window / token-bucket rate limiter keyed by user ID or client IP."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._buckets: Dict[str, Tuple[float, float]] = {}

    def check(self, key: str, max_per_minute: int) -> None:
        now = time.monotonic()
        rate_per_sec = max_per_minute / 60.0
        with self._lock:
            tokens, last_ts = self._buckets.get(key, (float(max_per_minute), now))
            elapsed = max(0.0, now - last_ts)
            tokens = min(float(max_per_minute), tokens + elapsed * rate_per_sec)
            if tokens < 1.0:
                raise HTTPException(
                    status_code=429,
                    detail="Rate limit exceeded. Please wait before submitting more requests.",
                )
            self._buckets[key] = (tokens - 1.0, now)

    def reset(self) -> None:
        with self._lock:
            self._buckets.clear()


rate_limiter = TokenBucketLimiter()


def enforce_rate_limit(
    request: Request,
    user: Optional[Dict[str, Any]] = None,
    limit_per_min: Optional[int] = None,
    scope: str = "api",
) -> None:
    max_rpm = limit_per_min or settings.rate_limit_per_min
    ident = (
        str(user.get("id"))
        if user and user.get("id")
        else (request.client.host if request.client else "anonymous")
    )
    rate_limiter.check(f"{scope}:{ident}", max_rpm)


# ───────────────────────────── AUDIO MAGIC-BYTE VALIDATION ─────────────────────────────

_ALLOWED_CONTENT_TYPES = {
    "audio/wav",
    "audio/x-wav",
    "audio/wave",
    "audio/mpeg",
    "audio/mp3",
    "audio/flac",
    "audio/x-flac",
    "audio/ogg",
    "audio/mp4",
    "audio/x-m4a",
    "audio/aac",
    "audio/aiff",
    "audio/x-aiff",
    "application/octet-stream",
}


def validate_audio_upload(data: bytes, content_type: Optional[str] = None) -> str:
    """Inspect magic bytes of uploaded file to guarantee it is a valid audio container."""
    if not data or len(data) < 12:
        raise HTTPException(status_code=400, detail="Audio file is empty or truncated")

    if content_type:
        base_ct = content_type.split(";")[0].strip().lower()
        if base_ct and base_ct not in _ALLOWED_CONTENT_TYPES:
            raise HTTPException(
                status_code=415,
                detail=f"Unsupported Content-Type '{base_ct}'. Upload WAV, MP3, FLAC, OGG, or M4A.",
            )

    head = data[:16]
    # WAV: RIFF....WAVE
    if head[:4] == b"RIFF" and head[8:12] == b"WAVE":
        return "wav"
    # FLAC: fLaC
    if head[:4] == b"fLaC":
        return "flac"
    # OGG: OggS
    if head[:4] == b"OggS":
        return "ogg"
    # AIFF: FORM....AIFF or AIFC
    if head[:4] == b"FORM" and head[8:12] in (b"AIFF", b"AIFC"):
        return "aiff"
    # MP4 / M4A / AAC container: ....ftyp
    if head[4:8] == b"ftyp":
        return "m4a"
    # MP3: ID3v2 tag or MPEG frame sync (0xFFE0 mask)
    if head[:3] == b"ID3" or (head[0] == 0xFF and (head[1] & 0xE0) == 0xE0):
        return "mp3"

    raise HTTPException(
        status_code=415,
        detail="Invalid audio file header. Supported formats: WAV, MP3, FLAC, OGG, M4A, AIFF.",
    )
