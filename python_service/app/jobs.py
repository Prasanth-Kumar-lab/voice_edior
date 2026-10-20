from __future__ import annotations

import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Any, Dict, Optional

from .audio_io import read_audio, write_wav
from .config import settings
from .db import record_audio_job
from .pipelines import enhance


@dataclass
class Job:
    id: str
    mode: str
    eq: str = "natural"
    space: str = "dry"
    level: str = "enhanced"
    user_email: Optional[str] = None
    status: str = "queued"
    progress: float = 0.0
    stage: str = "Queued"
    error: Optional[str] = None
    created: float = field(default_factory=time.time)
    audio: bytes = b""
    result: bytes = b""
    report: Dict[str, Any] = field(default_factory=dict)


class JobStore:
    def __init__(self) -> None:
        self._jobs: Dict[str, Job] = {}
        self._lock = threading.Lock()
        # One neural job at a time keeps latency predictable on a laptop CPU.
        self._pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="enhance")

    def submit(self, audio: bytes, mode: str, eq: str = "natural", space: str = "dry", level: str = "enhanced",
               user_email: Optional[str] = None) -> Job:
        self._gc()
        job = Job(id=uuid.uuid4().hex, mode=mode, eq=eq, space=space, level=level, user_email=user_email, audio=audio)
        with self._lock:
            self._jobs[job.id] = job
        self._pool.submit(self._run, job)
        return job

    def get(self, job_id: str) -> Optional[Job]:
        with self._lock:
            return self._jobs.get(job_id)

    def _gc(self) -> None:
        cutoff = time.time() - settings.job_ttl_s
        with self._lock:
            for k in [k for k, j in self._jobs.items() if j.created < cutoff]:
                del self._jobs[k]

    def _run(self, job: Job) -> None:
        job.status = "processing"

        def cb(stage: str, frac: float) -> None:
            job.stage = stage
            job.progress = min(0.99, float(frac))

        try:
            x, sr = read_audio(job.audio)
            job.audio = b""
            if len(x) < sr * 0.3:
                raise ValueError("Recording is too short")
            y, report = enhance(job.mode, x, sr, cb, eq=job.eq, space=job.space, level=job.level)
            job.result = write_wav(y, 48000, bits=16)
            job.report = report
            try:
                record_audio_job(job.user_email, job.mode, job.eq, len(x) / float(sr), report)
            except Exception:
                pass
            job.progress, job.stage, job.status = 1.0, "Done", "complete"
        except Exception as exc:  # noqa: BLE001 - surface any failure to the client
            job.error, job.status = str(exc), "failed"


store = JobStore()
