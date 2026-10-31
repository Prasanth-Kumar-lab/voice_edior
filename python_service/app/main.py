from __future__ import annotations

import asyncio
import hashlib
import hmac
import re
import time
from typing import Any, Dict, Optional

from fastapi import (
    Body,
    Depends,
    FastAPI,
    File,
    Form,
    HTTPException,
    Request,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, Response

from .admin_web import ADMIN_HTML
from .auth import (
    create_access_token,
    create_refresh_token,
    decode_token,
    enforce_rate_limit,
    get_current_user,
    get_optional_user,
    hash_password,
    require_admin,
    validate_audio_upload,
    verify_password,
)
from .config import settings
from .db import (
    DB_NAME,
    _now_str,
    _sync_dynamic_presets,
    compute_authoritative_plan_price,
    get_db,
    list_all_state,
    strip_oid,
)
from .audio_io import SR, read_audio, resample, write_wav
from .denoise import neural_available
from .jobs import store
from .mix_engine import render_mix_project
from .presets import LEVELS, PODCAST_TONES, SPACES, TONES
from .restoration import (
    debreath,
    declick,
    declip,
    dehum,
    deplosive,
    detect_speech_and_fillers,
    generate_vocal_harmony,
    separate_vocal_and_backing,
)
from .schemas import (
    AdminChangePlanRequest,
    AdminCreateFeatureRequest,
    AdminCreatePlanRequest,
    AdminCreateUserRequest,
    AdminRecordTransactionRequest,
    AdminUpdateSettingsRequest,
    BillingVerifyRequest,
    LoginRequest,
    RefreshTokenRequest,
    SignupRequest,
)

app = FastAPI(title="VocalPolish Studio DSP & Admin API", version="2.6.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)

MODES = ("podcast", "vocals")


@app.on_event("startup")
def _warm() -> None:
    neural_available()
    try:
        get_db()
    except Exception:
        pass


@app.get("/health")
def health() -> dict:
    try:
        _sync_dynamic_presets(get_db())
    except Exception:
        pass
    return {
        "status": "ok",
        "service": "vocalpolish-studio",
        "database": DB_NAME,
        "engine": "DeepFilterNet3" if neural_available() else "spectral",
        "modes": list(MODES),
        "tones": list(TONES),
        "podcast_tones": list(PODCAST_TONES),
        "levels": list(LEVELS),
        "spaces": list(SPACES),
    }


# ───────────────────────────── WEB ADMIN DASHBOARD ─────────────────────────────

@app.get("/admin", response_class=HTMLResponse)
def web_admin_dashboard() -> HTMLResponse:
    return HTMLResponse(content=ADMIN_HTML)


@app.get("/api/admin/state")
def api_admin_state(_admin: Dict[str, Any] = Depends(require_admin)) -> dict:
    return list_all_state()


@app.get("/api/app/bootstrap")
def api_app_bootstrap(
    user: Optional[Dict[str, Any]] = Depends(get_optional_user),
) -> dict:
    """Return public app plans, enabled features, global banner settings, and the caller's own profile if authenticated."""
    state = list_all_state()
    return {
        "database": DB_NAME,
        "user": strip_oid(user) if user else None,
        "plans": [p for p in state["plans"] if p.get("enabled", True)],
        "features": [f for f in state["features"] if f.get("enabled", True)],
        "settings": state["settings"],
    }


# ───────────────────────────── USER AUTH & PROFILE API (MONGODB + JWT) ─────────────────────────────

def _issue_auth_response(user: Dict[str, Any]) -> Dict[str, Any]:
    role_type = str(user.get("role_type", "admin" if user.get("is_admin") else "user"))
    access_token = create_access_token(user["id"], user["email"], role_type=role_type)
    refresh_token = create_refresh_token(user["id"], user["email"], role_type=role_type)
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "expires_in": settings.access_token_ttl_sec,
        "user": strip_oid(user),
    }


@app.post("/api/auth/login")
def api_login(payload: LoginRequest, request: Request) -> dict:
    enforce_rate_limit(request, limit_per_min=20, scope="auth_login")
    db = get_db()
    user = db.users.find_one({"email": payload.email})
    if not user:
        raise HTTPException(status_code=401, detail="Invalid email or password")

    is_valid, needs_rehash = verify_password(payload.password, str(user.get("password_hash", "")))
    if not is_valid:
        raise HTTPException(status_code=401, detail="Invalid email or password")

    if user.get("status") != "active":
        raise HTTPException(
            status_code=403,
            detail="Your account has been deactivated by the studio administrator.",
        )

    updates: Dict[str, Any] = {
        "last_active": "Online",
        "device_model": payload.device_model,
    }
    if needs_rehash:
        updates["password_hash"] = hash_password(payload.password)

    db.users.update_one({"id": user["id"]}, {"$set": updates})
    updated = db.users.find_one({"id": user["id"]}) or user
    return _issue_auth_response(updated)


@app.post("/api/auth/signup")
def api_signup(payload: SignupRequest, request: Request) -> dict:
    enforce_rate_limit(request, limit_per_min=15, scope="auth_signup")
    db = get_db()
    existing = db.users.find_one({"email": payload.email})
    if existing:
        raise HTTPException(
            status_code=409,
            detail="An account with this email address is already registered.",
        )

    next_num = 1047 + db.users.count_documents({})
    new_user = {
        "id": f"USR-{next_num}",
        "name": payload.name,
        "email": payload.email,
        "password_hash": hash_password(payload.password),
        "role": payload.role,
        "role_type": "user",
        "is_admin": False,
        "plan_name": "Creator Starter",
        "status": "active",
        "masters_count": 0,
        "minutes_processed": 0,
        "storage_used_mb": 0.0,
        "total_spent_usd": 0.0,
        "favorite_filter": "General + Bass",
        "joined_date": _now_str().split("·")[0].strip(),
        "last_active": "Online",
        "device_model": payload.device_model,
        "recent_jobs": [],
        "created_at": time.time(),
    }
    db.users.insert_one(new_user)
    return _issue_auth_response(new_user)


@app.post("/api/auth/refresh")
def api_refresh_token(payload: RefreshTokenRequest) -> dict:
    claims = decode_token(payload.refresh_token, expected_type="refresh")
    db = get_db()
    user = db.users.find_one({"id": claims.get("sub")}) or db.users.find_one(
        {"email": claims.get("email")}
    )
    if not user or user.get("status") != "active":
        raise HTTPException(status_code=401, detail="Account inactive or not found")
    return _issue_auth_response(user)


@app.get("/api/auth/me")
def api_me(user: Dict[str, Any] = Depends(get_current_user)) -> dict:
    return {"user": strip_oid(user)}


# ───────────────────────────── SERVER-VERIFIED BILLING & SUBSCRIPTIONS ─────────────────────────────

def _verify_purchase_receipt(
    user_id: str,
    plan_name: str,
    billing_cycle: str,
    provider: str,
    purchase_token: str,
    signature: Optional[str],
) -> None:
    """Validate receipt token format and optional HMAC signature."""
    token = purchase_token.strip()
    if len(token) < 8:
        raise HTTPException(status_code=400, detail="Invalid purchase receipt token")

    # If a production billing secret is configured, verify the HMAC-SHA256 receipt signature
    if settings.billing_secret:
        if not signature:
            raise HTTPException(status_code=400, detail="Missing billing receipt signature")
        msg = f"{user_id}:{plan_name}:{billing_cycle}:{provider}:{token}".encode("utf-8")
        expected = hmac.new(settings.billing_secret.encode("utf-8"), msg, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected, signature.strip()):
            raise HTTPException(status_code=403, detail="Invalid billing receipt signature")


@app.post("/api/billing/verify")
def api_billing_verify(
    payload: BillingVerifyRequest,
    user: Dict[str, Any] = Depends(get_current_user),
) -> dict:
    """Verify a Google Play / Stripe subscription purchase and assign the plan using server-side pricing."""
    db = get_db()
    if db.transactions.find_one({"receipt_id": payload.purchase_token}):
        raise HTTPException(status_code=409, detail="Purchase receipt has already been redeemed")

    try:
        pricing = compute_authoritative_plan_price(
            db, payload.plan_id, payload.plan_name, payload.billing_cycle
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc

    plan_name = pricing["plan_name"]
    amount = pricing["amount_usd"]

    _verify_purchase_receipt(
        user_id=user["id"],
        plan_name=plan_name,
        billing_cycle=payload.billing_cycle,
        provider=payload.provider,
        purchase_token=payload.purchase_token,
        signature=payload.signature,
    )

    db.users.update_one(
        {"id": user["id"]},
        {
            "$set": {"plan_name": plan_name, "last_active": "Just now"},
            "$inc": {"total_spent_usd": amount},
        },
    )
    db.plans.update_one({"name": plan_name}, {"$inc": {"active_subscribers": 1}})
    tx_doc = None
    if amount > 0:
        tx_id = f"TXN-{9922 + db.transactions.count_documents({})}"
        tx_doc = {
            "id": tx_id,
            "user_name": user["name"],
            "user_email": user["email"],
            "plan_name": plan_name,
            "amount_usd": amount,
            "billing_cycle": payload.billing_cycle,
            "timestamp": _now_str(),
            "method": payload.provider.replace("_", " ").title(),
            "receipt_id": payload.purchase_token,
            "created_at": time.time(),
        }
        db.transactions.insert_one(tx_doc)
    updated_user = db.users.find_one({"id": user["id"]})
    return {
        "user": strip_oid(updated_user),
        "transaction": strip_oid(tx_doc) if tx_doc else None,
        "verified_amount_usd": amount,
    }


@app.post("/api/users/{user_id}/subscribe")
def api_user_subscribe(
    user_id: str,
    payload: Dict[str, Any] = Body(...),
    caller: Dict[str, Any] = Depends(get_current_user),
) -> dict:
    """Authenticated subscription upgrade endpoint that strictly enforces server-side plan pricing."""
    is_admin = caller.get("role_type") == "admin" or caller.get("is_admin", False)
    if caller["id"] != user_id and not is_admin:
        raise HTTPException(status_code=403, detail="Cannot modify another user's subscription")

    db = get_db()
    user = db.users.find_one({"id": user_id})
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    plan_name = str(payload.get("plan_name", "Studio AI Pro"))
    plan_id = payload.get("plan_id")
    billing = "Monthly" if str(payload.get("billing_cycle", "Yearly")).lower() == "monthly" else "Yearly"
    purchase_token = str(payload.get("purchase_token") or f"rcpt_{user_id}_{int(time.time() * 1000)}")

    if db.transactions.find_one({"receipt_id": purchase_token}):
        raise HTTPException(status_code=409, detail="Purchase receipt has already been redeemed")

    try:
        pricing = compute_authoritative_plan_price(db, plan_id, plan_name, billing)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc

    authoritative_amount = pricing["amount_usd"]
    resolved_plan_name = pricing["plan_name"]

    db.users.update_one(
        {"id": user_id},
        {
            "$set": {"plan_name": resolved_plan_name, "last_active": "Just now"},
            "$inc": {"total_spent_usd": authoritative_amount},
        },
    )
    db.plans.update_one({"name": resolved_plan_name}, {"$inc": {"active_subscribers": 1}})
    if authoritative_amount > 0:
        tx_id = f"TXN-{9922 + db.transactions.count_documents({})}"
        db.transactions.insert_one({
            "id": tx_id,
            "user_name": user["name"],
            "user_email": user["email"],
            "plan_name": resolved_plan_name,
            "amount_usd": authoritative_amount,
            "billing_cycle": billing,
            "timestamp": _now_str(),
            "method": str(payload.get("provider", "Google Play")),
            "receipt_id": purchase_token,
            "created_at": time.time(),
        })
    return {
        "user": strip_oid(db.users.find_one({"id": user_id})),
        "verified_amount_usd": authoritative_amount,
    }


# ───────────────────────────── ADMIN CRUD ENDPOINTS (PROTECTED BY REQUIRE_ADMIN) ─────────────────────────────

@app.post("/api/admin/users")
def admin_create_user(
    payload: AdminCreateUserRequest,
    _admin: Dict[str, Any] = Depends(require_admin),
) -> dict:
    db = get_db()
    if db.users.find_one({"email": payload.email}):
        raise HTTPException(status_code=409, detail="User with this email already exists")

    next_num = 1047 + db.users.count_documents({})
    try:
        pricing = compute_authoritative_plan_price(db, None, payload.plan_name, "Yearly")
        spent = pricing["amount_usd"]
        plan_name = pricing["plan_name"]
    except ValueError:
        plan_name = payload.plan_name
        spent = 0.0

    doc = {
        "id": f"USR-{next_num}",
        "name": payload.name,
        "email": payload.email,
        "password_hash": hash_password(payload.password),
        "role": payload.role,
        "role_type": payload.role_type,
        "is_admin": payload.role_type == "admin",
        "plan_name": plan_name,
        "status": "active",
        "masters_count": 0,
        "minutes_processed": 0,
        "storage_used_mb": 0.0,
        "total_spent_usd": spent,
        "favorite_filter": "General + Bass",
        "joined_date": _now_str().split("·")[0].strip(),
        "last_active": "Provisioned by Admin",
        "device_model": "Web Admin Provisioned",
        "recent_jobs": [],
        "created_at": time.time(),
    }
    db.users.insert_one(doc)
    return strip_oid(doc)


@app.post("/api/admin/users/{user_id}/toggle-status")
def admin_toggle_user_status(
    user_id: str,
    _admin: Dict[str, Any] = Depends(require_admin),
) -> dict:
    db = get_db()
    u = db.users.find_one({"id": user_id})
    if not u:
        raise HTTPException(status_code=404, detail="User not found")
    new_status = "deactivated" if u.get("status") == "active" else "active"
    db.users.update_one({"id": user_id}, {"$set": {"status": new_status}})
    return strip_oid(db.users.find_one({"id": user_id}))


@app.post("/api/admin/users/{user_id}/plan")
def admin_change_user_plan(
    user_id: str,
    payload: AdminChangePlanRequest,
    _admin: Dict[str, Any] = Depends(require_admin),
) -> dict:
    db = get_db()
    u = db.users.find_one({"id": user_id})
    if not u:
        raise HTTPException(status_code=404, detail="User not found")
    db.users.update_one({"id": user_id}, {"$set": {"plan_name": payload.plan_name}})
    return strip_oid(db.users.find_one({"id": user_id}))


@app.delete("/api/admin/users/{user_id}")
def admin_delete_user(
    user_id: str,
    _admin: Dict[str, Any] = Depends(require_admin),
) -> dict:
    db = get_db()
    db.users.delete_one({"id": user_id})
    return {"deleted": user_id}


@app.post("/api/admin/plans")
def admin_create_plan(
    payload: AdminCreatePlanRequest,
    _admin: Dict[str, Any] = Depends(require_admin),
) -> dict:
    db = get_db()
    name = payload.name.strip()
    slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    doc = {
        "id": f"plan_{slug}_{int(time.time()) % 10000}",
        "name": name,
        "badge": payload.badge.upper(),
        "monthly_price": float(payload.monthly_price),
        "yearly_price": float(payload.yearly_price),
        "description": payload.description,
        "perks": list(payload.perks),
        "popular": bool(payload.popular),
        "active_subscribers": 1,
        "enabled": True,
    }
    db.plans.insert_one(doc)
    return strip_oid(doc)


@app.post("/api/admin/plans/{plan_id}/toggle")
def admin_toggle_plan(
    plan_id: str,
    _admin: Dict[str, Any] = Depends(require_admin),
) -> dict:
    db = get_db()
    p = db.plans.find_one({"id": plan_id})
    if not p:
        raise HTTPException(status_code=404, detail="Plan not found")
    db.plans.update_one({"id": plan_id}, {"$set": {"enabled": not p.get("enabled", True)}})
    return strip_oid(db.plans.find_one({"id": plan_id}))


@app.delete("/api/admin/plans/{plan_id}")
def admin_delete_plan(
    plan_id: str,
    _admin: Dict[str, Any] = Depends(require_admin),
) -> dict:
    db = get_db()
    db.plans.delete_one({"id": plan_id})
    return {"deleted": plan_id}


@app.post("/api/admin/features")
def admin_create_feature(
    payload: AdminCreateFeatureRequest,
    _admin: Dict[str, Any] = Depends(require_admin),
) -> dict:
    db = get_db()
    title = payload.title.strip()
    fid = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")
    bass = float(payload.bass)
    treble = float(payload.treble)
    warmth = float(payload.warmth)
    space = str(payload.space)
    dsp_str = f"bass: {bass:.2f} · treble: {treble:.2f} · warmth: {warmth:.2f}" + (
        f" · space: {space}" if space else ""
    )
    doc = {
        "id": fid,
        "title": title,
        "category": payload.category,
        "description": payload.description,
        "dsp_params": dsp_str,
        "bass": bass,
        "treble": treble,
        "warmth": warmth,
        "space": space,
        "enabled": True,
        "pro_only": bool(payload.pro_only),
        "usage_count": 1,
    }
    db.features.replace_one({"id": fid}, doc, upsert=True)
    _sync_dynamic_presets(db)
    return strip_oid(doc)


@app.post("/api/admin/features/{feat_id}/toggle")
def admin_toggle_feature(
    feat_id: str,
    _admin: Dict[str, Any] = Depends(require_admin),
) -> dict:
    db = get_db()
    f = db.features.find_one({"id": feat_id})
    if not f:
        raise HTTPException(status_code=404, detail="Feature not found")
    db.features.update_one({"id": feat_id}, {"$set": {"enabled": not f.get("enabled", True)}})
    return strip_oid(db.features.find_one({"id": feat_id}))


@app.post("/api/admin/features/{feat_id}/toggle-pro")
def admin_toggle_feature_pro(
    feat_id: str,
    _admin: Dict[str, Any] = Depends(require_admin),
) -> dict:
    db = get_db()
    f = db.features.find_one({"id": feat_id})
    if not f:
        raise HTTPException(status_code=404, detail="Feature not found")
    db.features.update_one({"id": feat_id}, {"$set": {"pro_only": not f.get("pro_only", False)}})
    return strip_oid(db.features.find_one({"id": feat_id}))


@app.delete("/api/admin/features/{feat_id}")
def admin_delete_feature(
    feat_id: str,
    _admin: Dict[str, Any] = Depends(require_admin),
) -> dict:
    db = get_db()
    db.features.delete_one({"id": feat_id})
    return {"deleted": feat_id}


@app.post("/api/admin/settings")
def admin_update_settings(
    payload: AdminUpdateSettingsRequest,
    _admin: Dict[str, Any] = Depends(require_admin),
) -> dict:
    db = get_db()
    db.settings.update_one(
        {"key": "global"},
        {
            "$set": {
                "broadcast_announcement": payload.broadcast_announcement,
                "cloud_gpu_acceleration": payload.cloud_gpu_acceleration,
                "maintenance_mode": payload.maintenance_mode,
            }
        },
        upsert=True,
    )
    return strip_oid(db.settings.find_one({"key": "global"}))


@app.post("/api/admin/transactions")
def admin_record_transaction(
    payload: AdminRecordTransactionRequest,
    _admin: Dict[str, Any] = Depends(require_admin),
) -> dict:
    db = get_db()
    try:
        pricing = compute_authoritative_plan_price(
            db, None, payload.plan_name, payload.billing_cycle
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc

    amount = pricing["amount_usd"]
    tx_id = f"TXN-{9922 + db.transactions.count_documents({})}"
    doc = {
        "id": tx_id,
        "user_name": payload.user_name,
        "user_email": payload.user_email,
        "plan_name": pricing["plan_name"],
        "amount_usd": amount,
        "billing_cycle": payload.billing_cycle,
        "timestamp": _now_str(),
        "method": payload.method,
        "receipt_id": payload.receipt_id or f"admin_rcpt_{tx_id}",
        "created_at": time.time(),
    }
    db.transactions.insert_one(doc)
    db.users.update_one({"email": payload.user_email}, {"$inc": {"total_spent_usd": amount}})
    return strip_oid(doc)


# ───────────────────────────── AUDIO ENHANCEMENT ENDPOINTS ─────────────────────────────

@app.post("/enhance")
async def enhance_audio(
    request: Request,
    mode: str = Form("podcast"),
    eq: str = Form("natural"),
    space: str = Form("dry"),
    level: str = Form("enhanced"),
    strength: float = Form(1.0),
    bass: float = Form(0.0),
    voice_isolation: bool = Form(False),
    preview_seconds: Optional[float] = Form(None),
    user_email: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None),
    user: Optional[Dict[str, Any]] = Depends(get_optional_user),
) -> dict:
    enforce_rate_limit(
        request,
        user=user,
        limit_per_min=settings.enhance_rate_limit_per_min,
        scope="enhance",
    )
    if mode not in MODES:
        raise HTTPException(status_code=400, detail="mode must be 'podcast' or 'vocals'")
    if file is None:
        raise HTTPException(status_code=400, detail="audio file required")
    data = await file.read()
    if len(data) > settings.max_upload_mb * 1024 * 1024:
        raise HTTPException(status_code=413, detail="file too large")

    validate_audio_upload(data, file.content_type)

    try:
        _sync_dynamic_presets(get_db())
    except Exception:
        pass
    tones = TONES if mode == "vocals" else {**PODCAST_TONES, "natural": None}
    if eq not in tones or space not in SPACES or level not in LEVELS:
        raise HTTPException(status_code=400, detail="unknown tone, space or level preset")

    effective_email = user["email"] if user else user_email
    job = store.submit(
        data,
        mode,
        eq,
        space,
        level,
        user_email=effective_email,
        strength=float(strength),
        bass=float(bass),
        voice_isolation=bool(voice_isolation),
        preview_seconds=preview_seconds,
    )
    return {"job_id": job.id, "status": job.status}


@app.post("/restyle/{job_id}")
def restyle_job(
    job_id: str,
    payload: Dict[str, Any] = Body(...),
) -> dict:
    """Re-run only Stage 2 (Style) on a cached job in <1s without re-uploading or re-running neural denoise."""
    job = store.restyle(
        job_id,
        eq=payload.get("eq"),
        space=payload.get("space"),
        level=payload.get("level"),
        strength=payload.get("strength"),
        bass=float(payload["bass"]) if "bass" in payload else None,
    )
    if job is None:
        raise HTTPException(status_code=404, detail="Job clean cache not found or expired")
    return {
        "job_id": job.id,
        "status": job.status,
        "download_url": f"/download/{job.id}",
        "report": job.report,
    }


@app.post("/cancel/{job_id}")
def cancel_job(job_id: str) -> dict:
    if not store.cancel(job_id):
        raise HTTPException(status_code=404, detail="unknown job")
    return {"job_id": job_id, "status": "cancelled"}


@app.websocket("/ws/jobs/{job_id}")
async def ws_job_progress(websocket: WebSocket, job_id: str) -> None:
    await websocket.accept()
    try:
        while True:
            job = store.get(job_id)
            if job is None:
                await websocket.send_json({"job_id": job_id, "status": "not_found"})
                break
            await websocket.send_json(
                {
                    "job_id": job.id,
                    "status": job.status,
                    "progress": round(job.progress, 3),
                    "stage": job.stage,
                    "download_url": f"/download/{job.id}" if job.status == "complete" else None,
                    "error": job.error,
                    "report": job.report if job.status == "complete" else None,
                }
            )
            if job.status in ("complete", "failed", "cancelled"):
                break
            await asyncio.sleep(0.25)
    except WebSocketDisconnect:
        pass


@app.get("/status/{job_id}")
def status(job_id: str) -> dict:
    job = store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="unknown job")
    return {
        "job_id": job.id,
        "mode": job.mode,
        "status": job.status,
        "progress": round(job.progress, 3),
        "stage": job.stage,
        "download_url": f"/download/{job.id}" if job.status == "complete" else None,
        "error": job.error,
        "report": job.report if job.status == "complete" else None,
    }


@app.get("/download/{job_id}")
def download(job_id: str) -> Response:
    job = store.get(job_id)
    if job is None or job.status != "complete":
        raise HTTPException(status_code=404, detail="not ready")
    return Response(content=job.result, media_type="audio/wav")


@app.post("/mix/render")
def api_mix_render(
    request: Request,
    payload: Dict[str, Any] = Body(...),
    user: Optional[Dict[str, Any]] = Depends(get_optional_user),
) -> Response:
    """Render a multi-track `.vpmix` project graph on the server and return a 48 kHz stereo WAV."""
    enforce_rate_limit(
        request,
        user=user,
        limit_per_min=settings.enhance_rate_limit_per_min,
        scope="mix_render",
    )
    project_dict = payload.get("project", payload)
    if not isinstance(project_dict, dict):
        raise HTTPException(status_code=400, detail="Valid .vpmix project dictionary required")

    wav_bytes, report = render_mix_project(project_dict)
    if payload.get("return_json") is True:
        return Response(
            content=__import__("json").dumps(
                {
                    "status": "complete",
                    "report": report,
                    "wav_size_bytes": len(wav_bytes),
                }
            ),
            media_type="application/json",
        )
    return Response(
        content=wav_bytes,
        media_type="audio/wav",
        headers={
            "X-Mix-Duration-Ms": str(report["duration_ms"]),
            "X-Mix-Lufs-Out": str(report["lufs_out"]),
        },
    )


@app.post("/mix/separate")
async def api_mix_separate(
    file: Optional[UploadFile] = File(None),
) -> dict:
    """Separate a clip into Vocal and Backing stems (Demucs / spectral harmonic-percussive mask)."""
    import base64
    import numpy as np

    if file is not None:
        raw = await file.read()
    else:
        t = np.arange(SR, dtype=np.float32) / float(SR)
        raw = write_wav((0.3 * np.sin(2.0 * 3.14159265 * 220.0 * t)).astype(np.float32), sr=SR)

    vocal_wav, backing_wav, meta = separate_vocal_and_backing(raw)
    return {
        "status": "complete",
        **meta,
        "vocal_wav_b64": base64.b64encode(vocal_wav).decode("ascii"),
        "backing_wav_b64": base64.b64encode(backing_wav).decode("ascii"),
    }


@app.post("/mix/transcribe")
async def api_mix_transcribe(
    file: Optional[UploadFile] = File(None),
) -> dict:
    """Detect speech phrases and filler words ('um', 'uh') with millisecond timestamps."""
    import numpy as np

    if file is not None:
        raw = await file.read()
    else:
        t = np.arange(SR * 2, dtype=np.float32) / float(SR)
        raw = write_wav((0.25 * np.sin(2.0 * 3.14159265 * 190.0 * t)).astype(np.float32), sr=SR)

    res = detect_speech_and_fillers(raw)
    return {
        "status": "complete",
        **res,
    }


@app.post("/mix/restore")
async def api_mix_restore(
    pass_name: str = Form("declick"),
    semitones: float = Form(4.0),
    file: Optional[UploadFile] = File(None),
) -> Response:
    """Run an advanced restoration or AI harmony pass on a clip and return a 48 kHz WAV."""
    import numpy as np

    if file is not None:
        raw = await file.read()
        x, sr = read_audio(raw)
        x = resample(x, sr, SR)
    else:
        t = np.arange(SR, dtype=np.float32) / float(SR)
        x = (0.3 * np.sin(2.0 * 3.14159265 * 220.0 * t)).astype(np.float32)

    p = pass_name.strip().lower()
    if p == "declick":
        y = declick(x, sr=SR)
    elif p == "deplosive":
        y = deplosive(x, sr=SR)
    elif p == "dehum":
        y = dehum(x, base_hz=50.0, sr=SR)
    elif p == "debreath":
        y = debreath(x, reduction_db=-12.0, sr=SR)
    elif p == "declip":
        y = declip(x, clip_threshold=0.95)
    elif p == "harmony":
        y = generate_vocal_harmony(x, intervals_semitones=(semitones, -4.0, 7.0), sr=SR)
    else:
        raise HTTPException(status_code=400, detail=f"Unknown restoration pass: {pass_name}")

    return Response(content=write_wav(y, sr=SR), media_type="audio/wav")
