#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -x .venv/bin/python ]]; then
  python3.11 -m venv .venv || python3 -m venv .venv
fi

.venv/bin/pip install -r requirements.txt
.venv/bin/python -m playwright install chromium

export CRAWL4AI_BIND_HOST="${CRAWL4AI_BIND_HOST:-127.0.0.1}"
export CRAWL4AI_BIND_PORT="${CRAWL4AI_BIND_PORT:-8790}"

echo "Starting Crawl4AI sidecar on http://${CRAWL4AI_BIND_HOST}:${CRAWL4AI_BIND_PORT}"
exec .venv/bin/uvicorn service:app --host "$CRAWL4AI_BIND_HOST" --port "$CRAWL4AI_BIND_PORT"
