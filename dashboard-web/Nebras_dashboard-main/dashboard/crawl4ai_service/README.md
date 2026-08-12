# Nebras — Crawl4AI sidecar

Python service that runs [Crawl4AI](https://github.com/unclecode/crawl4ai) and exposes a small HTTP API. The Nebras dashboard talks to it from the server side only (Owner-only routes under `/api/admin/crawl4ai/*`).

## Quick start (Windows, recommended)

The repo ships with a Crawl4AI install at `C:\nbcr` to avoid Windows `MAX_PATH` problems with the bundled `litellm` files. If that venv already exists, the start script reuses it; otherwise it creates a local `.venv` inside this folder.

```powershell
cd Nebras_dashboard-main\dashboard\crawl4ai_service
.\start.ps1
```

## Quick start (Linux / macOS)

```bash
cd Nebras_dashboard-main/dashboard/crawl4ai_service
./start.sh
```

## Configuration

Copy `.env.example` → `.env` if you want to change the bind host/port or set a shared secret:

```env
CRAWL4AI_BIND_HOST=127.0.0.1
CRAWL4AI_BIND_PORT=8790
CRAWL4AI_SERVICE_SECRET=
```

In the dashboard `.env` (the SvelteKit app), set:

```env
CRAWL4AI_SERVICE_URL=http://127.0.0.1:8790
CRAWL4AI_SERVICE_SECRET=
```

## HTTP API

| Method | Path        | Purpose                                                            |
| ------ | ----------- | ------------------------------------------------------------------ |
| GET    | `/health`   | Liveness ping                                                      |
| GET    | `/status`   | Worker on/off, stats, current job                                  |
| POST   | `/control`  | `{ "action": "start" \| "stop" }`                                  |
| POST   | `/crawl`    | `{ "url" }` enqueue an async job (stats only)                      |
| GET    | `/jobs`     | Recent / queued / running jobs                                     |
| POST   | `/fetch`    | `{ "url", "timeout_ms" }` → **returns rendered HTML** synchronously |
| POST   | `/download` | `{ "url", "referer", "timeout_ms" }` → file bytes as base64        |

`/fetch` and `/download` are what the Nebras **Noor Library engine** uses: a
real Chromium (Playwright) renders JS and clears Cloudflare, then `/download`
pulls the file through the same browser context (cookies + Referer) so
Cloudflare-protected PDFs come through. Both run synchronously and do **not**
depend on the queue worker.

All non-health endpoints accept the `X-Crawl4AI-Secret` header when a secret is configured.

## Deploy with the dashboard (Cloud Run, same Firebase project)

The dashboard runs on **Firebase App Hosting** (Cloud Run under the hood). App
Hosting only builds the SvelteKit app, so this Python + Chromium service ships
as its own Cloud Run service **in the same GCP project** (`nebras-9118c`):

```bash
cd Nebras_dashboard-main/dashboard/crawl4ai_service
CRAWL4AI_SERVICE_SECRET=your-shared-secret ./deploy-cloudrun.sh
```

Then set on the dashboard side (`apphosting.yaml` value + Secret Manager):

```env
CRAWL4AI_SERVICE_URL=https://nebras-crawl4ai-xxxxx-uc.a.run.app
CRAWL4AI_SERVICE_SECRET=your-shared-secret
```

The deploy script uses `--allow-unauthenticated` guarded by a **mandatory**
strong `CRAWL4AI_SERVICE_SECRET` (the dashboard client authenticates with the
`X-Crawl4AI-Secret` header, not a Google ID token). Generate one with
`openssl rand -hex 24`. If you prefer a fully private `--no-allow-unauthenticated`
service, you must add Google ID-token minting to `crawl4aiClient.js`.
