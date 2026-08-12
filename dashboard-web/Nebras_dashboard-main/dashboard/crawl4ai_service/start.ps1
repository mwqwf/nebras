$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# Crawl4AI prints unicode characters that the default cp1252 console can't encode.
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

# Use the prebuilt short-path venv if it exists (avoids Windows MAX_PATH issues
# with very long site-packages paths inside Crawl4AI's litellm bundle).
$venvPython = "C:\nbcr\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
  if (-not (Test-Path ".venv\Scripts\python.exe")) {
    py -3.11 -m venv .venv
  }
  $venvPython = ".\.venv\Scripts\python.exe"
}

& $venvPython -m pip install -r requirements.txt
& $venvPython -m playwright install chromium

$env:CRAWL4AI_BIND_HOST = if ($env:CRAWL4AI_BIND_HOST) { $env:CRAWL4AI_BIND_HOST } else { "127.0.0.1" }
$port = if ($env:CRAWL4AI_BIND_PORT) { $env:CRAWL4AI_BIND_PORT } else { "8790" }

Write-Host "Starting Crawl4AI sidecar on http://${env:CRAWL4AI_BIND_HOST}:$port"
& $venvPython -m uvicorn service:app --host $env:CRAWL4AI_BIND_HOST --port $port
