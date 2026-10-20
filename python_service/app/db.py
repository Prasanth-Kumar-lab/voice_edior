"""MongoDB integration for VocalPolish Studio (`vocalpolish_studio` database).

Creates and manages the `vocalpolish_studio` database in local MongoDB (visible in MongoDB Compass)
while preserving all existing databases on the server.
"""
from __future__ import annotations

import hashlib
import os
import time
from datetime import datetime
from typing import Any, Dict, List, Optional

from pymongo import MongoClient
from pymongo.database import Database

from .presets import PODCAST_TONES

MONGO_URI = os.getenv("MONGO_URI", "mongodb://127.0.0.1:27017")
DB_NAME = os.getenv("MONGO_DB", "vocalpolish_studio")

_client: Optional[MongoClient] = None
_db: Optional[Database] = None


def _hash_pw(password: str) -> str:
    return hashlib.sha256(f"vp_salt_{password}".encode("utf-8")).hexdigest()


def get_db() -> Database:
    global _client, _db
    if _db is None:
        _client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=3000)
        _db = _client[DB_NAME]
        _seed_if_empty(_db)
        _sync_dynamic_presets(_db)
    return _db


def _now_str() -> str:
    return datetime.now().strftime("%b %d, %Y · %I:%M %p")


def _seed_if_empty(db: Database) -> None:
    """Seed initial collections in `vocalpolish_studio` if empty so MongoDB Compass is immediately populated."""
    if db.users.count_documents({}) == 0:
        db.users.insert_many([
            {
                "id": "USR-1041",
                "name": "Alex Rivera",
                "email": "alex@podcaststudio.io",
                "password_hash": _hash_pw("studio123"),
                "role": "Podcaster",
                "plan_name": "Studio AI Pro",
                "status": "active",
                "masters_count": 148,
                "minutes_processed": 842,
                "storage_used_mb": 1240.5,
                "total_spent_usd": 191.76,
                "favorite_filter": "Theatrical",
                "joined_date": "Jan 12, 2026",
                "last_active": "Online",
                "device_model": "vivo V2336 · Android 16",
                "recent_jobs": [
                    "Ep 42 · Late Night Cinema Intro.wav (-16.0 LUFS · Theatrical)",
                    "Host Monologue · Tech Breakdown.wav (-16.0 LUFS · General + Bass)",
                    "Sponsor Read · Q4 Campaign.wav (-16.0 LUFS · Bass + Treble)",
                ],
                "created_at": time.time() - 86400 * 60,
            },
            {
                "id": "USR-1042",
                "name": "Maya Lin",
                "email": "maya.vocals@soundlab.co",
                "password_hash": _hash_pw("studio123"),
                "role": "Vocalist",
                "plan_name": "Broadcast Master Suite",
                "status": "active",
                "masters_count": 312,
                "minutes_processed": 1620,
                "storage_used_mb": 2890.0,
                "total_spent_usd": 479.76,
                "favorite_filter": "Bass + Treble",
                "joined_date": "Feb 03, 2026",
                "last_active": "14 mins ago",
                "device_model": "Pixel 9 Pro · Android 16",
                "recent_jobs": [
                    "Acoustic Hook Vocal Take 04.wav (-14.0 LUFS · Bright + Plate)",
                    "Chorus Stack Lead.wav (-14.0 LUFS · Warm + Hall)",
                ],
                "created_at": time.time() - 86400 * 45,
            },
            {
                "id": "USR-1043",
                "name": "Marcus Vance",
                "email": "mvance@trailervoice.tv",
                "password_hash": _hash_pw("studio123"),
                "role": "Voiceover",
                "plan_name": "Studio AI Pro",
                "status": "active",
                "masters_count": 94,
                "minutes_processed": 410,
                "storage_used_mb": 780.2,
                "total_spent_usd": 95.88,
                "favorite_filter": "Ultra Bass",
                "joined_date": "Mar 19, 2026",
                "last_active": "1 hour ago",
                "device_model": "Galaxy S25 Ultra",
                "recent_jobs": [
                    "SciFi Teaser Narration.wav (-16.0 LUFS · Theatrical)",
                    "Documentary Episode 1.wav (-16.0 LUFS · Ultra Bass)",
                ],
                "created_at": time.time() - 86400 * 30,
            },
            {
                "id": "USR-1044",
                "name": "Elena Rostova",
                "email": "elena@streamcast.gg",
                "password_hash": _hash_pw("studio123"),
                "role": "Streamer",
                "plan_name": "Creator Starter",
                "status": "deactivated",
                "masters_count": 19,
                "minutes_processed": 64,
                "storage_used_mb": 112.0,
                "total_spent_usd": 0.0,
                "favorite_filter": "Crystal Treble",
                "joined_date": "May 08, 2026",
                "last_active": "5 days ago",
                "device_model": "OnePlus 13",
                "recent_jobs": [
                    "Stream Highlight Voice.wav (-16.0 LUFS · Crystal Treble)",
                ],
                "created_at": time.time() - 86400 * 20,
            },
            {
                "id": "USR-1045",
                "name": "Devon Brooks",
                "email": "devon@indiepods.fm",
                "password_hash": _hash_pw("studio123"),
                "role": "Podcaster",
                "plan_name": "Studio AI Pro",
                "status": "active",
                "masters_count": 205,
                "minutes_processed": 1190,
                "storage_used_mb": 1845.0,
                "total_spent_usd": 149.90,
                "favorite_filter": "Studio Booth",
                "joined_date": "Jun 22, 2026",
                "last_active": "Just now",
                "device_model": "Nothing Phone (3)",
                "recent_jobs": [
                    "Roundtable Interview Ep 18.wav (-16.0 LUFS · Studio Booth)",
                    "Solo Commentary.wav (-16.0 LUFS · General + Bass)",
                ],
                "created_at": time.time() - 86400 * 10,
            },
            {
                "id": "USR-1046",
                "name": "Kiran Patel",
                "email": "kiran@audiobookmaster.in",
                "password_hash": _hash_pw("studio123"),
                "role": "Voiceover",
                "plan_name": "Broadcast Master Suite",
                "status": "active",
                "masters_count": 428,
                "minutes_processed": 2940,
                "storage_used_mb": 4120.8,
                "total_spent_usd": 539.70,
                "favorite_filter": "General + Bass",
                "joined_date": "Dec 01, 2025",
                "last_active": "8 mins ago",
                "device_model": "Samsung S24+",
                "recent_jobs": [
                    "Chapter 14 Final Master.wav (-16.0 LUFS · General + Bass)",
                    "Chapter 15 Final Master.wav (-16.0 LUFS · Theatrical)",
                ],
                "created_at": time.time() - 86400 * 90,
            },
        ])

    if db.plans.count_documents({}) == 0:
        db.plans.insert_many([
            {
                "id": "plan_starter",
                "name": "Creator Starter",
                "badge": "FREE",
                "monthly_price": 0.0,
                "yearly_price": 0.0,
                "description": "On-device voice clean & standard mono export up to 3 mins.",
                "perks": [
                    "Standard Spectral Denoise",
                    "General + Bass Podcast Filter",
                    "3-minute max recording length",
                ],
                "popular": False,
                "active_subscribers": 1420,
                "enabled": True,
            },
            {
                "id": "plan_pro",
                "name": "Studio AI Pro",
                "badge": "MOST POPULAR",
                "monthly_price": 14.99,
                "yearly_price": 7.99,
                "description": "All 6 Podcast Bass/Treble filters, Theatrical stereo hall & unlimited 48 kHz WAV exports.",
                "perks": [
                    "All 6 Podcast Filters (Theatrical, Ultra Bass, etc.)",
                    "Zero-Noise Pause Gate (-60 dB)",
                    "Speech-Gated Sub-Octave Bass & 16 kHz Treble Air",
                    "Unlimited 48 kHz Lossless WAV Export",
                ],
                "popular": True,
                "active_subscribers": 864,
                "enabled": True,
            },
            {
                "id": "plan_master",
                "name": "Broadcast Master Suite",
                "badge": "TEAMS & STUDIOS",
                "monthly_price": 29.99,
                "yearly_price": 19.99,
                "description": "Priority GPU cloud DSP queue, batch episode mastering & multi-device studio seats.",
                "perks": [
                    "Everything in Studio AI Pro",
                    "Dedicated Cloud GPU Neural Queue",
                    "Batch Multi-Episode LUFS Mastering",
                    "Up to 5 Studio Team Seats",
                ],
                "popular": False,
                "active_subscribers": 218,
                "enabled": True,
            },
        ])

    if db.features.count_documents({}) == 0:
        db.features.insert_many([
            {
                "id": "general_bass",
                "title": "General + Bass",
                "category": "Podcast Filter",
                "description": "Clean studio voice with warm, speaking-driven bass",
                "dsp_params": "bass: 0.55 · treble: 0.25 · warmth: 0.12",
                "bass": 0.55,
                "treble": 0.25,
                "warmth": 0.12,
                "space": "",
                "enabled": True,
                "pro_only": False,
                "usage_count": 18420,
            },
            {
                "id": "theatrical",
                "title": "Theatrical",
                "category": "Podcast Filter",
                "description": "Voice-tuned bass, cinema-hall stereo depth",
                "dsp_params": "bass: 0.85 · treble: 0.20 · space: theatre (1.65s)",
                "bass": 0.85,
                "treble": 0.20,
                "warmth": 0.18,
                "space": "theatre",
                "enabled": True,
                "pro_only": True,
                "usage_count": 24910,
            },
            {
                "id": "bass_treble",
                "title": "Bass + Treble",
                "category": "Podcast Filter",
                "description": "Punchy dynamic bass paired with crisp HD treble",
                "dsp_params": "bass: 0.70 · treble: 0.85 · V-curve EQ",
                "bass": 0.70,
                "treble": 0.85,
                "warmth": 0.15,
                "space": "",
                "enabled": True,
                "pro_only": True,
                "usage_count": 15300,
            },
            {
                "id": "ultra_bass",
                "title": "Ultra Bass",
                "category": "Podcast Filter",
                "description": "Deepest sub-octave chest resonance, dark and heavy",
                "dsp_params": "bass: 1.15 · +9.5 dB @ 75 Hz · warmth: 0.28",
                "bass": 1.15,
                "treble": 0.0,
                "warmth": 0.28,
                "space": "",
                "enabled": True,
                "pro_only": True,
                "usage_count": 11280,
            },
            {
                "id": "crystal_treble",
                "title": "Crystal Treble",
                "category": "Podcast Filter",
                "description": "Ultra-crisp treble, articulation and condenser air",
                "dsp_params": "treble: 1.0 · +9.0 dB @ 12.5 kHz · low-cut",
                "bass": 0.0,
                "treble": 1.0,
                "warmth": 0.0,
                "space": "",
                "enabled": True,
                "pro_only": True,
                "usage_count": 9640,
            },
            {
                "id": "studio_booth",
                "title": "Studio Booth",
                "category": "Podcast Filter",
                "description": "Wide stereo acoustic booth with warm bass & treble",
                "dsp_params": "bass: 0.50 · treble: 0.55 · space: booth (0.42s)",
                "bass": 0.50,
                "treble": 0.55,
                "warmth": 0.25,
                "space": "booth",
                "enabled": True,
                "pro_only": True,
                "usage_count": 12850,
            },
            {
                "id": "feat_zero_gate",
                "title": "Zero-Noise Pause Gate (-60 dB)",
                "category": "DSP Engine",
                "description": "Adaptive lookahead speech gate that silences pauses to pitch-black.",
                "dsp_params": "floor: -60 dB · hold: 130 ms · lookahead: 15 ms",
                "bass": 0.0,
                "treble": 0.0,
                "warmth": 0.0,
                "space": "",
                "enabled": True,
                "pro_only": False,
                "usage_count": 42100,
            },
            {
                "id": "feat_pin_suppressor",
                "title": "Transient Pin/Click Suppressor",
                "category": "DSP Engine",
                "description": "Median-filter impulse detector removing mouth clicks and mic pops.",
                "dsp_params": "window: 1.5 ms · threshold: 4.5 sigma",
                "bass": 0.0,
                "treble": 0.0,
                "warmth": 0.0,
                "space": "",
                "enabled": True,
                "pro_only": False,
                "usage_count": 42100,
            },
        ])

    if db.transactions.count_documents({}) == 0:
        db.transactions.insert_many([
            {
                "id": "TXN-9921",
                "user_name": "Kiran Patel",
                "user_email": "kiran@audiobookmaster.in",
                "plan_name": "Broadcast Master Suite",
                "amount_usd": 239.88,
                "billing_cycle": "Yearly",
                "timestamp": "Today · 12:42 PM",
                "method": "Apple Pay",
                "created_at": time.time() - 3600,
            },
            {
                "id": "TXN-9920",
                "user_name": "Alex Rivera",
                "user_email": "alex@podcaststudio.io",
                "plan_name": "Studio AI Pro",
                "amount_usd": 95.88,
                "billing_cycle": "Yearly",
                "timestamp": "Today · 11:18 AM",
                "method": "Google Play",
                "created_at": time.time() - 7200,
            },
            {
                "id": "TXN-9919",
                "user_name": "Devon Brooks",
                "user_email": "devon@indiepods.fm",
                "plan_name": "Studio AI Pro",
                "amount_usd": 14.99,
                "billing_cycle": "Monthly",
                "timestamp": "Yesterday · 08:15 PM",
                "method": "Stripe Card •••• 4242",
                "created_at": time.time() - 86400,
            },
            {
                "id": "TXN-9918",
                "user_name": "Maya Lin",
                "user_email": "maya.vocals@soundlab.co",
                "plan_name": "Broadcast Master Suite",
                "amount_usd": 239.88,
                "billing_cycle": "Yearly",
                "timestamp": "Oct 18 · 04:30 PM",
                "method": "Google Play",
                "created_at": time.time() - 86400 * 2,
            },
            {
                "id": "TXN-9917",
                "user_name": "Marcus Vance",
                "user_email": "mvance@trailervoice.tv",
                "plan_name": "Studio AI Pro",
                "amount_usd": 95.88,
                "billing_cycle": "Yearly",
                "timestamp": "Oct 17 · 02:12 PM",
                "method": "Stripe Card •••• 8819",
                "created_at": time.time() - 86400 * 3,
            },
        ])

    if db.settings.count_documents({}) == 0:
        db.settings.insert_one({
            "key": "global",
            "maintenance_mode": False,
            "cloud_gpu_acceleration": True,
            "allow_free_exports": True,
            "broadcast_announcement": "AI Engine v2.5: Theatrical Sub-Bass & Crystal Treble now live!",
            "monthly_revenue": [
                {"month": "May", "revenue_k": 8.4},
                {"month": "Jun", "revenue_k": 11.2},
                {"month": "Jul", "revenue_k": 14.8},
                {"month": "Aug", "revenue_k": 17.5},
                {"month": "Sep", "revenue_k": 21.9},
                {"month": "Oct", "revenue_k": 26.4},
            ],
        })


def _sync_dynamic_presets(db: Database) -> None:
    """Register any custom Podcast filters created by Admin in MongoDB into PODCAST_TONES for DSP processing."""
    for doc in db.features.find({"category": "Podcast Filter"}):
        fid = doc["id"]
        if fid not in PODCAST_TONES:
            bass = float(doc.get("bass", 0.5))
            treble = float(doc.get("treble", 0.4))
            warmth = float(doc.get("warmth", 0.15))
            space = str(doc.get("space", ""))
            PODCAST_TONES[fid] = {
                "label": doc["title"],
                "blurb": doc["description"],
                "curve": [
                    (50, 2.5 * bass),
                    (100, 6.0 * bass),
                    (160, 4.0 * bass),
                    (320, -3.5),
                    (1000, 0.5),
                    (3200, 4.0 * max(0.3, treble)),
                    (6500, 5.0 * treble),
                    (12000, 6.0 * treble),
                ],
                "bass": bass,
                "treble": treble,
                "warmth": warmth,
                "space": space,
                "theatre": space == "theatre",
            }


def strip_oid(doc: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    if not doc:
        return {}
    out = dict(doc)
    out.pop("_id", None)
    out.pop("password_hash", None)
    return out


def list_all_state() -> Dict[str, Any]:
    db = get_db()
    _sync_dynamic_presets(db)
    users = [strip_oid(u) for u in db.users.find().sort("created_at", -1)]
    plans = [strip_oid(p) for p in db.plans.find()]
    features = [strip_oid(f) for f in db.features.find()]
    txs = [strip_oid(t) for t in db.transactions.find().sort("created_at", -1).limit(30)]
    cfg = strip_oid(db.settings.find_one({"key": "global"}))

    # Calculate dynamic revenue & usage totals
    plan_rev = 0.0
    mrr = 0.0
    total_subs = 0
    for p in plans:
        subs = int(p.get("active_subscribers", 0))
        total_subs += subs
        yp = float(p.get("yearly_price", 0.0))
        mp = float(p.get("monthly_price", 0.0))
        plan_rev += subs * (yp * 12 if yp > 0 else mp * 12)
        mrr += subs * (yp if yp > 0 else mp)

    tx_sum = sum(float(t.get("amount_usd", 0.0)) for t in txs)
    total_masters = sum(int(u.get("masters_count", 0)) for u in users)
    total_minutes = sum(int(u.get("minutes_processed", 0)) for u in users)

    return {
        "database": DB_NAME,
        "users": users,
        "plans": plans,
        "features": features,
        "transactions": txs,
        "settings": cfg,
        "metrics": {
            "total_revenue_usd": round(plan_rev + tx_sum, 2),
            "mrr_usd": round(mrr, 2),
            "total_subscribers": total_subs,
            "total_users": len(users),
            "active_users": sum(1 for u in users if u.get("status") == "active"),
            "deactivated_users": sum(1 for u in users if u.get("status") != "active"),
            "total_masters": total_masters,
            "total_minutes": total_minutes,
        },
    }


def record_audio_job(user_email: Optional[str], mode: str, eq: str, duration_sec: float, report: Dict[str, Any]) -> None:
    """Called automatically when the DSP server finishes enhancing an audio file."""
    db = get_db()
    mins = max(1, int(round(duration_sec / 60.0)))
    mb = round((duration_sec * 48000 * 2) / (1024 * 1024), 2)
    lufs = report.get("lufs_out", -16.0)
    summary = f"{mode.capitalize()} Master ({lufs} LUFS · {eq}) · {_now_str()}"

    # Increment feature usage counter in MongoDB
    db.features.update_one({"id": eq}, {"$inc": {"usage_count": 1}})

    # Update user profile in MongoDB
    target_query = {"email": user_email.lower().strip()} if user_email else {"status": "active"}
    user = db.users.find_one(target_query)
    if user:
        jobs: List[str] = list(user.get("recent_jobs", []))
        jobs.insert(0, summary)
        db.users.update_one(
            {"id": user["id"]},
            {
                "$inc": {
                    "masters_count": 1,
                    "minutes_processed": mins,
                    "storage_used_mb": mb,
                },
                "$set": {
                    "last_active": "Just now",
                    "favorite_filter": eq.replace("_", " ").title(),
                    "recent_jobs": jobs[:15],
                },
            },
        )
