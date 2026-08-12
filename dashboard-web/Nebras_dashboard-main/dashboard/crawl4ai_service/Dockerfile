# Nebras — Crawl4AI sidecar (Cloud Run container)
#
# يُنشر كخدمة Cloud Run داخل نفس مشروع Firebase الذي تستضيف فيه App Hosting
# لوحة نبراس (نفس البنية التحتية). اللوحة (SvelteKit) تتصل به server-side
# عبر CRAWL4AI_SERVICE_URL. يحوي Chromium عبر Playwright لتجاوز Cloudflare.
#
# البناء والنشر: استخدم ./deploy-cloudrun.sh (يضبط الذاكرة/المهلة/السرّ).
#   CRAWL4AI_SERVICE_SECRET=$(openssl rand -hex 24) ./deploy-cloudrun.sh

FROM python:3.11-slim

# تبعيات نظام يحتاجها Chromium بالإضافة إلى أدوات البناء.
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget gnupg ca-certificates fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

WORKDIR /app

COPY requirements.txt ./
RUN pip install --upgrade pip && pip install -r requirements.txt

# تثبيت Chromium مع كل تبعيات النظام (‎--with-deps‎) داخل الصورة.
RUN python -m playwright install --with-deps chromium \
    && (crawl4ai-setup || true)

COPY . ./

# Cloud Run يحقن المنفذ عبر $PORT (افتراضي 8080). نربط على 0.0.0.0.
ENV CRAWL4AI_BIND_HOST=0.0.0.0
EXPOSE 8080
CMD ["sh", "-c", "uvicorn service:app --host 0.0.0.0 --port ${PORT:-8080}"]
