from __future__ import annotations

import re
import time
from typing import Any, Dict, List, Optional

from fastapi import Body, FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, Response

from .admin_web import ADMIN_HTML
from .config import settings
from .db import DB_NAME, _hash_pw, _now_str, _sync_dynamic_presets, get_db, list_all_state, strip_oid
from .denoise import neural_available
from .jobs import store
from .presets import LEVELS, PODCAST_TONES, SPACES, TONES

app = FastAPI(title="VocalPolish Studio DSP & Admin API", version="2.5.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

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
def api_admin_state() -> dict:
    return list_all_state()


@app.get("/api/app/bootstrap")
def api_app_bootstrap(email: Optional[str] = None) -> dict:
    state = list_all_state()
    db = get_db()
    user_doc = None
    if email:
        user_doc = db.users.find_one({"email": email.lower().strip()})
    if not user_doc:
        user_doc = db.users.find_one({"status": "active"})
    return {
        "database": DB_NAME,
        "user": strip_oid(user_doc),
        "plans": [p for p in state["plans"] if p.get("enabled", True)],
        "features": [f for f in state["features"] if f.get("enabled", True)],
        "settings": state["settings"],
    }


# ───────────────────────────── USER AUTH & PROFILE API (MONGODB) ─────────────────────────────

@app.post("/api/auth/login")
def api_login(payload: Dict[str, Any] = Body(...)) -> dict:
    db = get_db()
    email = str(payload.get("email", "")).lower().strip()
    if not email:
        raise HTTPException(status_code=400, detail="Email required")
    user = db.users.find_one({"email": email})
    if not user:
        # Auto-provision if signing in with a new studio email
        next_num = 1047 + db.users.count_documents({})
        user = {
            "id": f"USR-{next_num}",
            "name": email.split("@")[0].replace(".", " ").title(),
            "email": email,
            "password_hash": _hash_pw(str(payload.get("password", "studio123"))),
            "role": "Podcaster",
            "plan_name": "Studio AI Pro",
            "status": "active",
            "masters_count": 0,
            "minutes_processed": 0,
            "storage_used_mb": 0.0,
            "total_spent_usd": 0.0,
            "favorite_filter": "General + Bass",
            "joined_date": _now_str().split("·")[0].strip(),
            "last_active": "Online",
            "device_model": str(payload.get("device_model", "vivo V2336 · Android")),
            "recent_jobs": [],
            "created_at": time.time(),
        }
        db.users.insert_one(user)
    else:
        if user.get("status") != "active":
            raise HTTPException(status_code=403, detail="Your account has been deactivated by the studio administrator.")
        db.users.update_one({"id": user["id"]}, {"$set": {"last_active": "Online"}})
        user = db.users.find_one({"id": user["id"]})
    return {"user": strip_oid(user)}


@app.post("/api/auth/signup")
def api_signup(payload: Dict[str, Any] = Body(...)) -> dict:
    db = get_db()
    email = str(payload.get("email", "")).lower().strip()
    name = str(payload.get("name", "")).strip() or "Studio Creator"
    role = str(payload.get("role", "Podcaster")).strip()
    if not email:
        raise HTTPException(status_code=400, detail="Email required")
    existing = db.users.find_one({"email": email})
    if existing:
        db.users.update_one(
            {"id": existing["id"]},
            {"$set": {"name": name, "role": role, "last_active": "Online"}},
        )
        return {"user": strip_oid(db.users.find_one({"id": existing["id"]}))}

    next_num = 1047 + db.users.count_documents({})
    new_user = {
        "id": f"USR-{next_num}",
        "name": name,
        "email": email,
        "password_hash": _hash_pw(str(payload.get("password", "studio123"))),
        "role": role,
        "plan_name": "Creator Starter",
        "status": "active",
        "masters_count": 0,
        "minutes_processed": 0,
        "storage_used_mb": 0.0,
        "total_spent_usd": 0.0,
        "favorite_filter": "General + Bass",
        "joined_date": _now_str().split("·")[0].strip(),
        "last_active": "Online",
        "device_model": str(payload.get("device_model", "vivo V2336 · Android")),
        "recent_jobs": [],
        "created_at": time.time(),
    }
    db.users.insert_one(new_user)
    return {"user": strip_oid(new_user)}


@app.post("/api/users/{user_id}/subscribe")
def api_user_subscribe(user_id: str, payload: Dict[str, Any] = Body(...)) -> dict:
    db = get_db()
    plan_name = str(payload.get("plan_name", "Studio AI Pro"))
    amount = float(payload.get("amount_usd", 95.88))
    billing = str(payload.get("billing_cycle", "Yearly"))
    user = db.users.find_one({"id": user_id})
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    db.users.update_one(
        {"id": user_id},
        {
            "$set": {"plan_name": plan_name, "last_active": "Just now"},
            "$inc": {"total_spent_usd": amount},
        },
    )
    db.plans.update_one({"name": plan_name}, {"$inc": {"active_subscribers": 1}})
    if amount > 0:
        tx_id = f"TXN-{9922 + db.transactions.count_documents({})}"
        db.transactions.insert_one({
            "id": tx_id,
            "user_name": user["name"],
            "user_email": user["email"],
            "plan_name": plan_name,
            "amount_usd": amount,
            "billing_cycle": billing,
            "timestamp": _now_str(),
            "method": "In-App Purchase",
            "created_at": time.time(),
        })
    return {"user": strip_oid(db.users.find_one({"id": user_id}))}


# ───────────────────────────── ADMIN CRUD ENDPOINTS (MONGODB) ─────────────────────────────

@app.post("/api/admin/users")
def admin_create_user(payload: Dict[str, Any] = Body(...)) -> dict:
    db = get_db()
    next_num = 1047 + db.users.count_documents({})
    plan_name = str(payload.get("plan_name", "Studio AI Pro"))
    spent = 0.0 if plan_name == "Creator Starter" else 95.88
    doc = {
        "id": f"USR-{next_num}",
        "name": str(payload.get("name", "New Creator")).strip(),
        "email": str(payload.get("email", "")).lower().strip(),
        "password_hash": _hash_pw(str(payload.get("password", "studio123"))),
        "role": str(payload.get("role", "Podcaster")),
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
def admin_toggle_user_status(user_id: str) -> dict:
    db = get_db()
    u = db.users.find_one({"id": user_id})
    if not u:
        raise HTTPException(status_code=404, detail="User not found")
    new_status = "deactivated" if u.get("status") == "active" else "active"
    db.users.update_one({"id": user_id}, {"$set": {"status": new_status}})
    return strip_oid(db.users.find_one({"id": user_id}))


@app.post("/api/admin/users/{user_id}/plan")
def admin_change_user_plan(user_id: str, payload: Dict[str, Any] = Body(...)) -> dict:
    db = get_db()
    plan_name = str(payload.get("plan_name", "Studio AI Pro"))
    db.users.update_one({"id": user_id}, {"$set": {"plan_name": plan_name}})
    return strip_oid(db.users.find_one({"id": user_id}))


@app.delete("/api/admin/users/{user_id}")
def admin_delete_user(user_id: str) -> dict:
    db = get_db()
    db.users.delete_one({"id": user_id})
    return {"deleted": user_id}


@app.post("/api/admin/plans")
def admin_create_plan(payload: Dict[str, Any] = Body(...)) -> dict:
    db = get_db()
    name = str(payload.get("name", "Custom Plan")).strip()
    slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    doc = {
        "id": f"plan_{slug}_{int(time.time()) % 10000}",
        "name": name,
        "badge": str(payload.get("badge", "NEW")).upper(),
        "monthly_price": float(payload.get("monthly_price", 19.99)),
        "yearly_price": float(payload.get("yearly_price", 12.99)),
        "description": str(payload.get("description", "")),
        "perks": list(payload.get("perks", [])),
        "popular": bool(payload.get("popular", False)),
        "active_subscribers": 1,
        "enabled": True,
    }
    db.plans.insert_one(doc)
    return strip_oid(doc)


@app.post("/api/admin/plans/{plan_id}/toggle")
def admin_toggle_plan(plan_id: str) -> dict:
    db = get_db()
    p = db.plans.find_one({"id": plan_id})
    if not p:
        raise HTTPException(status_code=404, detail="Plan not found")
    db.plans.update_one({"id": plan_id}, {"$set": {"enabled": not p.get("enabled", True)}})
    return strip_oid(db.plans.find_one({"id": plan_id}))


@app.delete("/api/admin/plans/{plan_id}")
def admin_delete_plan(plan_id: str) -> dict:
    db = get_db()
    db.plans.delete_one({"id": plan_id})
    return {"deleted": plan_id}


@app.post("/api/admin/features")
def admin_create_feature(payload: Dict[str, Any] = Body(...)) -> dict:
    db = get_db()
    title = str(payload.get("title", "New Filter")).strip()
    fid = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")
    bass = float(payload.get("bass", 0.6))
    treble = float(payload.get("treble", 0.5))
    warmth = float(payload.get("warmth", 0.15))
    space = str(payload.get("space", ""))
    dsp_str = f"bass: {bass:.2f} · treble: {treble:.2f} · warmth: {warmth:.2f}" + (f" · space: {space}" if space else "")
    doc = {
        "id": fid,
        "title": title,
        "category": str(payload.get("category", "Podcast Filter")),
        "description": str(payload.get("description", "Custom AI Studio filter")),
        "dsp_params": dsp_str,
        "bass": bass,
        "treble": treble,
        "warmth": warmth,
        "space": space,
        "enabled": True,
        "pro_only": bool(payload.get("pro_only", True)),
        "usage_count": 1,
    }
    db.features.replace_one({"id": fid}, doc, upsert=True)
    _sync_dynamic_presets(db)
    return strip_oid(doc)


@app.post("/api/admin/features/{feat_id}/toggle")
def admin_toggle_feature(feat_id: str) -> dict:
    db = get_db()
    f = db.features.find_one({"id": feat_id})
    if not f:
        raise HTTPException(status_code=404, detail="Feature not found")
    db.features.update_one({"id": feat_id}, {"$set": {"enabled": not f.get("enabled", True)}})
    return strip_oid(db.features.find_one({"id": feat_id}))


@app.post("/api/admin/features/{feat_id}/toggle-pro")
def admin_toggle_feature_pro(feat_id: str) -> dict:
    db = get_db()
    f = db.features.find_one({"id": feat_id})
    if not f:
        raise HTTPException(status_code=404, detail="Feature not found")
    db.features.update_one({"id": feat_id}, {"$set": {"pro_only": not f.get("pro_only", False)}})
    return strip_oid(db.features.find_one({"id": feat_id}))


@app.delete("/api/admin/features/{feat_id}")
def admin_delete_feature(feat_id: str) -> dict:
    db = get_db()
    db.features.delete_one({"id": feat_id})
    return {"deleted": feat_id}


@app.post("/api/admin/settings")
def admin_update_settings(payload: Dict[str, Any] = Body(...)) -> dict:
    db = get_db()
    db.settings.update_one(
        {"key": "global"},
        {
            "$set": {
                "broadcast_announcement": str(payload.get("broadcast_announcement", "")),
                "cloud_gpu_acceleration": bool(payload.get("cloud_gpu_acceleration", True)),
                "maintenance_mode": bool(payload.get("maintenance_mode", False)),
            }
        },
        upsert=True,
    )
    return strip_oid(db.settings.find_one({"key": "global"}))


@app.post("/api/admin/transactions")
def admin_record_transaction(payload: Dict[str, Any] = Body(...)) -> dict:
    db = get_db()
    tx_id = f"TXN-{9922 + db.transactions.count_documents({})}"
    amount = float(payload.get("amount_usd", 95.88))
    email = str(payload.get("user_email", "")).lower().strip()
    doc = {
        "id": tx_id,
        "user_name": str(payload.get("user_name", "Studio Customer")),
        "user_email": email,
        "plan_name": str(payload.get("plan_name", "Studio AI Pro")),
        "amount_usd": amount,
        "billing_cycle": str(payload.get("billing_cycle", "Yearly")),
        "timestamp": _now_str(),
        "method": str(payload.get("method", "Stripe")),
        "created_at": time.time(),
    }
    db.transactions.insert_one(doc)
    if email:
        db.users.update_one({"email": email}, {"$inc": {"total_spent_usd": amount}})
    return strip_oid(doc)


# ───────────────────────────── AUDIO ENHANCEMENT ENDPOINTS ─────────────────────────────

@app.post("/enhance")
async def enhance_audio(
    mode: str = Form("podcast"),
    eq: str = Form("natural"),
    space: str = Form("dry"),
    level: str = Form("enhanced"),
    user_email: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None),
) -> dict:
    if mode not in MODES:
        raise HTTPException(status_code=400, detail="mode must be 'podcast' or 'vocals'")
    if file is None:
        raise HTTPException(status_code=400, detail="audio file required")
    data = await file.read()
    if len(data) > settings.max_upload_mb * 1024 * 1024:
        raise HTTPException(status_code=413, detail="file too large")
    try:
        _sync_dynamic_presets(get_db())
    except Exception:
        pass
    tones = TONES if mode == "vocals" else {**PODCAST_TONES, "natural": None}
    if eq not in tones or space not in SPACES or level not in LEVELS:
        raise HTTPException(status_code=400, detail="unknown tone, space or level preset")
    job = store.submit(data, mode, eq, space, level, user_email=user_email)
    return {"job_id": job.id, "status": job.status}


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
