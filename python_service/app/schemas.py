"""Pydantic request and response schemas with strict validation for VocalPolish APIs."""
from __future__ import annotations

import re
from typing import List, Literal, Optional

from pydantic import BaseModel, Field, field_validator

_EMAIL_RE = re.compile(r"^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$")


def _clean_email(v: str) -> str:
    email = v.strip().lower()
    if not email or len(email) > 254 or not _EMAIL_RE.match(email):
        raise ValueError("Invalid email address")
    return email


class LoginRequest(BaseModel):
    email: str = Field(..., min_length=3, max_length=254)
    password: str = Field(..., min_length=6, max_length=128)
    device_model: str = Field(default="Android Studio Device", max_length=120)

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        return _clean_email(v)


class SignupRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    email: str = Field(..., min_length=3, max_length=254)
    password: str = Field(..., min_length=6, max_length=128)
    role: str = Field(default="Podcaster", max_length=40)
    device_model: str = Field(default="Android Studio Device", max_length=120)

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        return _clean_email(v)

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        cleaned = v.strip()
        if not cleaned:
            raise ValueError("Name cannot be blank")
        return cleaned


class RefreshTokenRequest(BaseModel):
    refresh_token: str = Field(..., min_length=16, max_length=2048)


class BillingVerifyRequest(BaseModel):
    plan_id: Optional[str] = Field(default=None, max_length=80)
    plan_name: Optional[str] = Field(default=None, max_length=100)
    billing_cycle: Literal["Monthly", "Yearly"] = Field(default="Yearly")
    provider: Literal["google_play", "stripe", "apple_pay", "in_app_purchase"] = Field(
        default="google_play"
    )
    purchase_token: str = Field(..., min_length=8, max_length=2048)
    signature: Optional[str] = Field(default=None, max_length=512)


class AdminCreateUserRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    email: str = Field(..., min_length=3, max_length=254)
    password: str = Field(..., min_length=6, max_length=128)
    role: str = Field(default="Podcaster", max_length=40)
    plan_name: str = Field(default="Studio AI Pro", max_length=100)
    role_type: Literal["user", "admin"] = Field(default="user")

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        return _clean_email(v)


class AdminChangePlanRequest(BaseModel):
    plan_name: str = Field(..., min_length=1, max_length=100)


class AdminCreatePlanRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=80)
    badge: str = Field(default="NEW", min_length=1, max_length=30)
    monthly_price: float = Field(..., ge=0.0, le=9999.0)
    yearly_price: float = Field(..., ge=0.0, le=9999.0)
    description: str = Field(default="", max_length=500)
    perks: List[str] = Field(default_factory=list, max_length=20)
    popular: bool = Field(default=False)


class AdminCreateFeatureRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=80)
    category: Literal["Podcast Filter", "DSP Engine", "Mastering"] = Field(
        default="Podcast Filter"
    )
    description: str = Field(default="Custom AI Studio filter", max_length=400)
    bass: float = Field(default=0.6, ge=0.0, le=1.5)
    treble: float = Field(default=0.5, ge=0.0, le=1.5)
    warmth: float = Field(default=0.15, ge=0.0, le=1.0)
    space: Literal["", "theatre", "booth", "room", "plate", "hall", "wide"] = Field(
        default=""
    )
    pro_only: bool = Field(default=True)


class AdminUpdateSettingsRequest(BaseModel):
    broadcast_announcement: str = Field(default="", max_length=500)
    cloud_gpu_acceleration: bool = Field(default=True)
    maintenance_mode: bool = Field(default=False)


class AdminRecordTransactionRequest(BaseModel):
    user_name: str = Field(..., min_length=1, max_length=100)
    user_email: str = Field(..., min_length=3, max_length=254)
    plan_name: str = Field(..., min_length=1, max_length=100)
    billing_cycle: Literal["Monthly", "Yearly"] = Field(default="Yearly")
    method: str = Field(default="Stripe", max_length=60)
    receipt_id: Optional[str] = Field(default=None, max_length=256)

    @field_validator("user_email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        return _clean_email(v)
