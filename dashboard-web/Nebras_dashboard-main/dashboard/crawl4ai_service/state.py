"""In-process stats and job queue for the Crawl4AI sidecar."""

from __future__ import annotations

import asyncio
import time
import uuid
from collections import deque
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class JobStatus(str, Enum):
    queued = "queued"
    running = "running"
    done = "done"
    failed = "failed"
    cancelled = "cancelled"


@dataclass
class JobRecord:
    id: str
    url: str
    status: JobStatus = JobStatus.queued
    created_at: float = field(default_factory=time.time)
    started_at: float | None = None
    finished_at: float | None = None
    error: str | None = None
    markdown_chars: int | None = None
    html_chars: int | None = None


class ServiceState:
    def __init__(self, max_completed: int = 100) -> None:
        self._lock = asyncio.Lock()
        self.worker_enabled = False
        self.worker_task: asyncio.Task | None = None
        self.queue: asyncio.Queue[tuple[str, str]] = asyncio.Queue()
        self.jobs: dict[str, JobRecord] = {}
        self.completed_order: deque[str] = deque(maxlen=max_completed)
        self.urls_crawled_ok = 0
        self.urls_crawled_fail = 0
        self.worker_started_at: float | None = None
        self.last_worker_error: str | None = None

    def snapshot(self) -> dict[str, Any]:
        pending = sum(1 for j in self.jobs.values() if j.status == JobStatus.queued)
        running = next((j for j in self.jobs.values() if j.status == JobStatus.running), None)
        return {
            "worker_enabled": self.worker_enabled,
            "worker_running": self.worker_task is not None and not self.worker_task.done(),
            "queue_depth": self.queue.qsize(),
            "pending_jobs": pending,
            "current_job": (
                {"id": running.id, "url": running.url} if running else None
            ),
            "stats": {
                "urls_ok": self.urls_crawled_ok,
                "urls_failed": self.urls_crawled_fail,
                "jobs_total": len(self.jobs),
            },
            "worker_started_at": self.worker_started_at,
            "last_worker_error": self.last_worker_error,
        }

    def recent_jobs(self, limit: int = 50) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        for jid in list(self.completed_order)[-limit:][::-1]:
            j = self.jobs.get(jid)
            if not j:
                continue
            out.append(self._job_public(j))
        return out

    def _job_public(self, j: JobRecord) -> dict[str, Any]:
        return {
            "id": j.id,
            "url": j.url,
            "status": j.status.value,
            "created_at": j.created_at,
            "started_at": j.started_at,
            "finished_at": j.finished_at,
            "error": j.error,
            "markdown_chars": j.markdown_chars,
            "html_chars": j.html_chars,
        }

    async def enqueue(self, url: str) -> JobRecord:
        jid = str(uuid.uuid4())
        rec = JobRecord(id=jid, url=url)
        async with self._lock:
            self.jobs[jid] = rec
        await self.queue.put((jid, url))
        return rec

    async def mark_running(self, jid: str) -> None:
        async with self._lock:
            j = self.jobs.get(jid)
            if j:
                j.status = JobStatus.running
                j.started_at = time.time()

    async def mark_done(
        self,
        jid: str,
        *,
        markdown: str | None,
        html: str | None,
        error: str | None,
    ) -> None:
        async with self._lock:
            j = self.jobs.get(jid)
            if not j:
                return
            j.finished_at = time.time()
            if error:
                j.status = JobStatus.failed
                j.error = error
                self.urls_crawled_fail += 1
            else:
                j.status = JobStatus.done
                j.markdown_chars = len(markdown or "")
                j.html_chars = len(html or "")
                self.urls_crawled_ok += 1
            self.completed_order.append(jid)
