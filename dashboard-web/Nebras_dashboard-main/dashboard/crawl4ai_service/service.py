"""
Crawl4AI sidecar HTTP API.

Run locally (from this directory):

  python -m venv .venv
  .\\.venv\\Scripts\\activate
  pip install -r requirements.txt
  playwright install
  uvicorn service:app --host 127.0.0.1 --port 8790

The Nebras dashboard (SvelteKit) calls this service using server-side env:
  CRAWL4AI_SERVICE_URL=http://127.0.0.1:8790
  CRAWL4AI_SERVICE_SECRET=optional-shared-secret
"""

from __future__ import annotations

import os
import sys
import time
from contextlib import asynccontextmanager
from typing import Any

# Crawl4AI prints unicode glyphs (e.g. "→") that crash the default Windows
# console encoding (cp1252). Force UTF-8 on stdout/stderr before any import.
for stream in (sys.stdout, sys.stderr):
    try:
        stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except Exception:
        pass

from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from state import JobStatus, ServiceState
from worker import start_worker, stop_worker, crawl_html_now, download_now

load_dotenv()

BIND_HOST = os.getenv("CRAWL4AI_BIND_HOST", "127.0.0.1")
BIND_PORT = int(os.getenv("CRAWL4AI_BIND_PORT", "8790"))
EXPECTED_SECRET = (os.getenv("CRAWL4AI_SERVICE_SECRET") or "").strip()

state = ServiceState()


def _auth(secret: str | None) -> None:
    if not EXPECTED_SECRET:
        return
    if (secret or "").strip() != EXPECTED_SECRET:
        raise HTTPException(status_code=401, detail="invalid_secret")


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    await stop_worker(state)


app = FastAPI(title="Nebras Crawl4AI Sidecar", lifespan=lifespan)


class ControlBody(BaseModel):
    action: str = Field(..., description="start | stop")


class CrawlBody(BaseModel):
    url: str = Field(..., min_length=4, description="https://...")


class FetchBody(BaseModel):
    url: str = Field(..., min_length=4, description="https://...")
    timeout_ms: int = Field(default=60000, ge=5000, le=180000)


class DownloadBody(BaseModel):
    url: str = Field(..., min_length=4, description="https://... file URL")
    referer: str | None = Field(default=None, description="page URL to establish session/clearance")
    timeout_ms: int = Field(default=90000, ge=5000, le=180000)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "nebras-crawl4ai"}


@app.get("/status")
def status(x_crawl4ai_secret: str | None = Header(default=None, alias="X-Crawl4AI-Secret")) -> dict[str, Any]:
    _auth(x_crawl4ai_secret)
    snap = state.snapshot()
    snap["bind"] = {"host": BIND_HOST, "port": BIND_PORT}
    return snap


@app.post("/control")
async def control(
    body: ControlBody,
    x_crawl4ai_secret: str | None = Header(default=None, alias="X-Crawl4AI-Secret"),
) -> dict[str, Any]:
    _auth(x_crawl4ai_secret)
    act = (body.action or "").strip().lower()
    if act == "start":
        state.worker_enabled = True
        state.last_worker_error = None
        state.worker_started_at = time.time()
        start_worker(state)
        return {"ok": True, "action": "start", **state.snapshot()}
    if act == "stop":
        await stop_worker(state)
        return {"ok": True, "action": "stop", **state.snapshot()}
    raise HTTPException(status_code=400, detail="unknown_action")


@app.post("/crawl")
async def crawl(
    body: CrawlBody,
    x_crawl4ai_secret: str | None = Header(default=None, alias="X-Crawl4AI-Secret"),
) -> dict[str, Any]:
    _auth(x_crawl4ai_secret)
    if not state.worker_enabled:
        raise HTTPException(status_code=409, detail="worker_stopped")
    url = body.url.strip()
    if not url.startswith(("http://", "https://")):
        raise HTTPException(status_code=400, detail="invalid_url")
    rec = await state.enqueue(url)
    return {"ok": True, "job": {"id": rec.id, "url": rec.url, "status": rec.status.value}}


@app.post("/fetch")
async def fetch(
    body: FetchBody,
    x_crawl4ai_secret: str | None = Header(default=None, alias="X-Crawl4AI-Secret"),
) -> dict[str, Any]:
    """Synchronous crawl that RETURNS rendered HTML (defeats JS/Cloudflare via
    a real browser). Independent of the queue worker."""
    _auth(x_crawl4ai_secret)
    url = body.url.strip()
    if not url.startswith(("http://", "https://")):
        raise HTTPException(status_code=400, detail="invalid_url")
    return await crawl_html_now(url, timeout_ms=body.timeout_ms)


@app.post("/download")
async def download(
    body: DownloadBody,
    x_crawl4ai_secret: str | None = Header(default=None, alias="X-Crawl4AI-Secret"),
) -> dict[str, Any]:
    """Download a binary file (PDF/audio/...) through a real browser context,
    establishing Cloudflare clearance via the referer page first. Returns
    base64 so the Node side can rebuild the Buffer."""
    _auth(x_crawl4ai_secret)
    url = body.url.strip()
    if not url.startswith(("http://", "https://")):
        raise HTTPException(status_code=400, detail="invalid_url")
    return await download_now(url, referer=body.referer, timeout_ms=body.timeout_ms)


@app.get("/jobs")
def jobs(
    x_crawl4ai_secret: str | None = Header(default=None, alias="X-Crawl4AI-Secret"),
    limit: int = 50,
) -> dict[str, Any]:
    _auth(x_crawl4ai_secret)
    lim = max(1, min(limit, 200))
    items = state.recent_jobs(limit=lim)
    queued = [state._job_public(j) for j in state.jobs.values() if j.status == JobStatus.queued]
    running = [state._job_public(j) for j in state.jobs.values() if j.status == JobStatus.running]
    return {"queued": queued, "running": running, "recent": items}
