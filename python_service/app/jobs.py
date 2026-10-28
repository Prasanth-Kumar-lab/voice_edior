from __future__ import annotations

import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Any, Dict, Optional

from .audio_io import read_audio, write_wav
from .config import settings
from .db import get_db, record_audio_job
from .pipelines import clean_stage_cache, enhance, style_from_cache


@dataclass
class Job:
    id: str
    mode: str
    eq: str = "natural"
    space: str = "dry"
    level: str = "enhanced"
    strength: float = 1.0
    voice_isolation: bool = False
    preview_seconds: Optional[float] = None
    user_email: Optional[str] = None
    status: str = "queued"
    progress: float = 0.0
    stage: str = "Queued"
    error: Optional[str] = None
    cancelled: bool = False
    created: float = field(default_factory=time.time)
    audio: bytes = b""
    result: bytes = b""
    report: Dict[str, Any] = field(default_factory=dict)
    clean_cache: Optional[Dict[str, Any]] = None


class JobCancelError(Exception):
    """Raised internally when a job is cancelled by the user."""


class JobStore:
    def __init__(self) -> None:
        self._jobs: Dict[str, Job] = {}
        self._lock = threading.Lock()
        # One neural job at a time keeps latency predictable on a single CPU worker.
        self._pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="enhance")

    def submit(
        self,
        audio: bytes,
        mode: str,
        eq: str = "natural",
        space: str = "dry",
        level: str = "enhanced",
        user_email: Optional[str] = None,
        strength: float = 1.0,
        voice_isolation: bool = False,
        preview_seconds: Optional[float] = None,
    ) -> Job:
        self._gc()
        job = Job(
            id=uuid.uuid4().hex,
            mode=mode,
            eq=eq,
            space=space,
            level=level,
            strength=strength,
            voice_isolation=voice_isolation,
            preview_seconds=preview_seconds,
            user_email=user_email,
            audio=audio,
        )
        with self._lock:
            self._jobs[job.id] = job
        self._persist_job_meta(job)
        self._pool.submit(self._run, job)
        return job

    def get(self, job_id: str) -> Optional[Job]:
        with self._lock:
            job = self._jobs.get(job_id)
        if job is not None:
            return job
        # Check persistent MongoDB job metadata if worker restarted
        try:
            doc = get_db().jobs.find_one({"id": job_id})
            if doc:
                return Job(
                    id=str(doc["id"]),
                    mode=str(doc.get("mode", "podcast")),
                    eq=str(doc.get("eq", "natural")),
                    space=str(doc.get("space", "dry")),
                    level=str(doc.get("level", "enhanced")),
                    status=str(doc.get("status", "failed")),
                    progress=float(doc.get("progress", 0.0)),
                    stage=str(doc.get("stage", "Worker restarted")),
                    error=doc.get("error"),
                    report=doc.get("report") or {},
                )
        except Exception:
            pass
        return None

    def cancel(self, job_id: str) -> bool:
        with self._lock:
            job = self._jobs.get(job_id)
            if job is None:
                return False
            job.cancelled = True
            if job.status in ("queued", "processing"):
                job.status = "cancelled"
                job.stage = "Cancelled"
                job.audio = b""
                self._persist_job_meta(job)
            return True

    def restyle(
        self,
        job_id: str,
        eq: Optional[str] = None,
        space: Optional[str] = None,
        level: Optional[str] = None,
        strength: Optional[float] = None,
    ) -> Optional[Job]:
        """Re-run only Stage 2 (Style) on a completed job's cached Stage 1 (Clean) stem in <1s."""
        with self._lock:
            job = self._jobs.get(job_id)
        if job is None or job.clean_cache is None:
            return None

        if eq is not None:
            job.eq = eq
        if space is not None:
            job.space = space
        if level is not None:
            job.level = level
        if strength is not None:
            job.strength = float(strength)

        y, report = style_from_cache(
            job.clean_cache,
            eq=job.eq,
            space=job.space,
            level=job.level,
            strength=job.strength,
        )
        job.result = write_wav(y, 48000, bits=16)
        job.report = report
        job.status = "complete"
        job.progress = 1.0
        job.stage = "Done (Cached Restyle)"
        self._persist_job_meta(job)
        return job

    def _persist_job_meta(self, job: Job) -> None:
        try:
            get_db().jobs.update_one(
                {"id": job.id},
                {
                    "$set": {
                        "id": job.id,
                        "mode": job.mode,
                        "eq": job.eq,
                        "space": job.space,
                        "level": job.level,
                        "status": job.status,
                        "progress": round(job.progress, 3),
                        "stage": job.stage,
                        "error": job.error,
                        "report": job.report,
                        "updated_at": time.time(),
                    }
                },
                upsert=True,
            )
        except Exception:
            pass

    def _gc(self) -> None:
        cutoff = time.time() - settings.job_ttl_s
        with self._lock:
            for k in [k for k, j in self._jobs.items() if j.created < cutoff]:
                del self._jobs[k]

    def _run(self, job: Job) -> None:
        if job.cancelled:
            job.status = "cancelled"
            self._persist_job_meta(job)
            return

        job.status = "processing"
        self._persist_job_meta(job)

        def cb(stage: str, frac: float) -> None:
            if job.cancelled:
                raise JobCancelError("Job cancelled by user")
            job.stage = stage
            job.progress = min(0.99, float(frac))

        try:
            x, sr = read_audio(job.audio)
            job.audio = b""
            if len(x) < sr * 0.3:
                raise ValueError("Recording is too short")

            if job.preview_seconds is not None and job.preview_seconds > 0:
                max_samples = int(job.preview_seconds * sr)
                if len(x) > max_samples:
                    x = x[:max_samples]

            # Cache Stage 1 (Clean) so subsequent preset switches on Result screen take <1s
            job.clean_cache = clean_stage_cache(
                job.mode, x, sr, cb, voice_isolation=job.voice_isolation
            )
            y, report = enhance(
                job.mode,
                x,
                sr,
                cb,
                eq=job.eq,
                space=job.space,
                level=job.level,
                strength=job.strength,
                voice_isolation=job.voice_isolation,
            )
            if job.cancelled:
                raise JobCancelError("Job cancelled by user")

            job.result = write_wav(y, 48000, bits=16)
            job.report = report
            try:
                record_audio_job(job.user_email, job.mode, job.eq, len(x) / float(sr), report)
            except Exception:
                pass
            job.progress, job.stage, job.status = 1.0, "Done", "complete"
            self._persist_job_meta(job)
        except JobCancelError:
            job.status = "cancelled"
            job.stage = "Cancelled"
            self._persist_job_meta(job)
        except Exception as exc:  # noqa: BLE001 - surface any failure to the client
            job.error, job.status = str(exc), "failed"
            self._persist_job_meta(job)


store = JobStore()
