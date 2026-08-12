"""Background worker: drains the queue while worker_enabled is true."""

from __future__ import annotations

import asyncio
import logging
import traceback

from state import ServiceState

log = logging.getLogger("crawl4ai_worker")


async def crawl_one_url(url: str) -> tuple[str | None, str | None, str | None]:
    """Returns (markdown, raw_html, error_message)."""
    try:
        from crawl4ai import AsyncWebCrawler  # lazy import
    except ImportError as e:
        return None, None, f"crawl4ai_import_error: {e}"

    try:
        async with AsyncWebCrawler(verbose=False) as crawler:
            result = await crawler.arun(url=url)
            md = (
                getattr(result, "markdown", None)
                or getattr(result, "markdown_v2", None)
                or ""
            )
            html = (
                getattr(result, "html", None)
                or getattr(result, "cleaned_html", None)
                or ""
            )
            if getattr(result, "success", True) is False:
                err = getattr(result, "error_message", None) or "crawl_failed"
                return md, html, err
            return md, html, None
    except Exception as e:
        log.exception("crawl failed for %s", url)
        return None, None, f"{type(e).__name__}: {e}"


async def crawl_html_now(url: str, timeout_ms: int = 60000) -> dict:
    """Synchronous (awaited) crawl that RETURNS the rendered HTML/markdown.

    Unlike the queue worker (which only keeps stats), this returns the actual
    content so the Node engine can parse it. Best-effort Cloudflare bypass via
    crawl4ai's Playwright backend (magic/simulate_user when supported)."""
    try:
        from crawl4ai import AsyncWebCrawler  # lazy import
    except ImportError as e:
        return {"ok": False, "error": f"crawl4ai_import_error: {e}"}

    # crawl4ai's arun signature changed across versions. Try the rich kwargs
    # that help defeat JS challenges, then progressively drop unknown ones.
    attempts = [
        dict(
            url=url,
            magic=True,
            simulate_user=True,
            page_timeout=timeout_ms,
            delay_before_return_html=2.5,
        ),
        dict(url=url, page_timeout=timeout_ms),
        dict(url=url),
    ]
    try:
        async with AsyncWebCrawler(verbose=False) as crawler:
            last_exc: Exception | None = None
            for kwargs in attempts:
                try:
                    result = await crawler.arun(**kwargs)
                    break
                except TypeError as te:
                    last_exc = te
                    continue
            else:
                return {"ok": False, "error": f"arun_signature_error: {last_exc}"}

            md = getattr(result, "markdown", None) or getattr(result, "markdown_v2", None) or ""
            html = getattr(result, "html", None) or getattr(result, "cleaned_html", None) or ""
            final_url = (
                getattr(result, "redirected_url", None)
                or getattr(result, "url", None)
                or url
            )
            if getattr(result, "success", True) is False:
                err = getattr(result, "error_message", None) or "crawl_failed"
                return {"ok": False, "error": err, "html": str(html), "final_url": final_url}
            return {
                "ok": True,
                "html": str(html),
                "markdown": str(md),
                "final_url": final_url,
            }
    except Exception as e:  # noqa: BLE001
        log.exception("crawl_html_now failed for %s", url)
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}


async def download_now(url: str, referer: str | None = None, timeout_ms: int = 90000) -> dict:
    """Download a binary (PDF/audio/...) inside a real browser context.

    Visits the referer page first to obtain Cloudflare's cf_clearance cookie,
    then fetches the file URL through the SAME browser context (cookies +
    correct Referer carry over). Returns base64 so it survives JSON transport.
    This is what lets the engine pull files from Cloudflare-protected sites."""
    try:
        from playwright.async_api import async_playwright  # bundled with crawl4ai
    except ImportError as e:
        return {"ok": False, "error": f"playwright_import_error: {e}"}

    import base64 as _b64

    ua = (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    )
    try:
        async with async_playwright() as p:
            browser = await p.chromium.launch(
                headless=True,
                args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-blink-features=AutomationControlled"],
            )
            try:
                context = await browser.new_context(
                    user_agent=ua,
                    accept_downloads=True,
                    extra_http_headers={"Referer": referer} if referer else {},
                )
                page = await context.new_page()
                # 1) establish session/clearance on the referring page
                if referer:
                    try:
                        await page.goto(referer, wait_until="domcontentloaded", timeout=timeout_ms)
                        await page.wait_for_timeout(2000)
                    except Exception:  # noqa: BLE001
                        pass  # not fatal — try the file fetch anyway

                # 2) fetch the binary through the context (carries cookies)
                resp = await context.request.get(
                    url,
                    headers={"Referer": referer} if referer else None,
                    timeout=timeout_ms,
                )
                if not resp.ok:
                    return {"ok": False, "error": f"http_{resp.status}", "status": resp.status}
                body = await resp.body()
                if not body:
                    return {"ok": False, "error": "empty_body"}

                headers = resp.headers or {}
                content_type = headers.get("content-type", "application/octet-stream")
                filename = ""
                cd = headers.get("content-disposition", "")
                if cd:
                    import re as _re

                    m = _re.search(r"filename\*?=(?:UTF-8'')?[\"']?([^;\"']+)", cd, _re.I)
                    if m:
                        filename = m.group(1)
                return {
                    "ok": True,
                    "base64": _b64.b64encode(body).decode("ascii"),
                    "content_type": content_type,
                    "filename": filename,
                    "size": len(body),
                }
            finally:
                await browser.close()
    except Exception as e:  # noqa: BLE001
        log.exception("download_now failed for %s", url)
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}


async def worker_loop(state: ServiceState) -> None:
    log.info("worker loop started")
    while state.worker_enabled:
        try:
            jid, url = await asyncio.wait_for(state.queue.get(), timeout=0.5)
        except asyncio.TimeoutError:
            continue
        except asyncio.CancelledError:
            break

        await state.mark_running(jid)
        md, html, err = await crawl_one_url(url)
        await state.mark_done(jid, markdown=md, html=html, error=err)
        state.queue.task_done()

    log.info("worker loop exiting")


def start_worker(state: ServiceState) -> None:
    if state.worker_task and not state.worker_task.done():
        return
    state.worker_task = asyncio.create_task(worker_loop(state), name="crawl4ai-worker")


async def stop_worker(state: ServiceState) -> None:
    state.worker_enabled = False
    t = state.worker_task
    state.worker_task = None
    if t and not t.done():
        t.cancel()
        try:
            await t
        except asyncio.CancelledError:
            pass
        except Exception:
            state.last_worker_error = traceback.format_exc()[-4000:]
