#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  نبراس — نشر كل شيء بأمر واحد (Bootstrap موحَّد)                 ║
# ╠══════════════════════════════════════════════════════════════════╣
# ║  يُؤتمت كل ما يمكن أتمتته:                                        ║
# ║   1) تسجيل الدخول (تفاعليّ لمرّة واحدة — هويّتك، لا تُؤتمت).       ║
# ║   2) تفعيل APIs على GCP.                                          ║
# ║   3) توليد الأسرار تلقائياً.                                       ║
# ║   4) نشر crawl4ai على Cloud Run + التقاط الرابط.                  ║
# ║   5) ضبط أسرار GitHub (CRON_SECRET / VERCEL_URL).                 ║
# ║   6) ضبط متغيّرات Vercel (CRAWL4AI_SERVICE_URL/SECRET/CRON).       ║
# ║   7) دفع فارغ لإعادة نشر Vercel بالقيم الجديدة.                   ║
# ║                                                                  ║
# ║  الاستعمال (من مجلد dashboard/):  bash deploy-all.sh             ║
# ║  يقبل تجاوزات بيئيّة: GCLOUD_PROJECT, CLOUD_RUN_REGION,           ║
# ║  GH_REPO, VERCEL_SCOPE.                                          ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail
cd "$(dirname "$0")"

PROJECT="${GCLOUD_PROJECT:-nebras-9118c}"
REGION="${CLOUD_RUN_REGION:-us-central1}"
SERVICE="${CLOUD_RUN_SERVICE:-nebras-crawl4ai}"
GH_REPO="${GH_REPO:-mwqwf/Nebras_dashboard-main}"

say() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m  ✅ %s\033[0m\n' "$*"; }
warn(){ printf '\033[1;33m  ⚠ %s\033[0m\n' "$*"; }

gen_secret() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -hex 24
  else head -c 24 /dev/urandom | xxd -p | tr -d '\n'; fi
}

# ── 0) أدوات مطلوبة ─────────────────────────────────────────────────
say "فحص الأدوات"
command -v gcloud >/dev/null 2>&1 || { echo "❌ gcloud غير مثبّت: https://cloud.google.com/sdk/docs/install"; exit 1; }
command -v gh     >/dev/null 2>&1 || { echo "❌ gh (GitHub CLI) غير مثبّت: https://cli.github.com"; exit 1; }
command -v npx    >/dev/null 2>&1 || { echo "❌ Node/npx مطلوب لـ Vercel CLI"; exit 1; }
ok "الأدوات حاضرة"

# ── 1) تسجيل الدخول (الخطوة التفاعليّة الوحيدة) ─────────────────────
say "تسجيل الدخول (لمرّة واحدة)"
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
  warn "لا حساب gcloud نشط — سيُفتح المتصفّح."
  gcloud auth login
fi
gcloud config set project "$PROJECT" >/dev/null
ok "gcloud: $(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1) → مشروع $PROJECT"

if ! gh auth status >/dev/null 2>&1; then
  warn "لم تُسجّل دخول GitHub — اتّبع التعليمات."
  gh auth login
fi
ok "gh: $(gh api user --jq .login 2>/dev/null || echo 'مسجَّل')"

# ── 2) تفعيل APIs ───────────────────────────────────────────────────
say "تفعيل APIs على GCP"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com --project "$PROJECT"
ok "Cloud Run + Cloud Build + Artifact Registry مفعّلة"

# ── 3) توليد الأسرار ───────────────────────────────────────────────
say "توليد الأسرار"
CRAWL4AI_SERVICE_SECRET="${CRAWL4AI_SERVICE_SECRET:-$(gen_secret)}"
CRON_SECRET="${CRON_SECRET:-$(gen_secret)}"
ok "secrets جاهزة"

# ── 4) نشر crawl4ai على Cloud Run ──────────────────────────────────
say "نشر crawl4ai (قد يستغرق عدّة دقائق لبناء Chromium)"
gcloud run deploy "$SERVICE" \
  --source ./crawl4ai_service \
  --project "$PROJECT" --region "$REGION" \
  --allow-unauthenticated \
  --memory 2Gi --cpu 2 --timeout 300 --concurrency 4 --max-instances 3 \
  --set-env-vars "CRAWL4AI_SERVICE_SECRET=$CRAWL4AI_SERVICE_SECRET"
CRAWL_URL="$(gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" --format='value(status.url)')"
ok "crawl4ai منشورة: $CRAWL_URL"

# ── 5) أسرار GitHub (للـ workflows) ────────────────────────────────
say "ضبط أسرار GitHub على $GH_REPO"
printf '%s' "$CRON_SECRET" | gh secret set CRON_SECRET --repo "$GH_REPO" --body -
ok "CRON_SECRET مضبوط على GitHub"
# VERCEL_URL يُضبط بعد معرفة رابط Vercel أدناه.

# ── 6) متغيّرات Vercel ──────────────────────────────────────────────
say "ضبط متغيّرات Vercel (production)"
set_vercel_env() {
  local name="$1" val="$2"
  # نحذف القديم إن وُجد (تجاهل الفشل) ثم نضيف الجديد.
  npx --yes vercel env rm "$name" production --yes >/dev/null 2>&1 || true
  printf '%s' "$val" | npx --yes vercel env add "$name" production >/dev/null 2>&1 \
    && ok "$name مضبوط على Vercel" \
    || warn "تعذّر ضبط $name تلقائياً على Vercel — أضِفه يدوياً (انظر الملخّص)."
}
if npx --yes vercel whoami >/dev/null 2>&1 || [ -n "${VERCEL_TOKEN:-}" ]; then
  # اربط المشروع إن لم يكن مربوطاً (تفاعليّ أوّل مرّة).
  npx --yes vercel link >/dev/null 2>&1 || true
  set_vercel_env CRAWL4AI_SERVICE_URL "$CRAWL_URL"
  set_vercel_env CRAWL4AI_SERVICE_SECRET "$CRAWL4AI_SERVICE_SECRET"
  set_vercel_env CRON_SECRET "$CRON_SECRET"
  VERCEL_DEPLOY_URL="$(npx --yes vercel deploy --prod --yes 2>/dev/null | tail -1 || true)"
  [ -n "$VERCEL_DEPLOY_URL" ] && ok "أُعيد نشر Vercel: $VERCEL_DEPLOY_URL"
  if [ -n "${VERCEL_DEPLOY_URL:-}" ]; then
    printf '%s' "$VERCEL_DEPLOY_URL" | gh secret set VERCEL_URL --repo "$GH_REPO" --body - && ok "VERCEL_URL مضبوط على GitHub"
  fi
else
  warn "Vercel غير مسجّل دخول. سجّل: npx vercel login ثم أعد تشغيل السكربت،"
  warn "أو أضِف هذه المتغيّرات يدوياً في Vercel → Settings → Environment Variables."
fi

# ── 7) ملخّص ────────────────────────────────────────────────────────
say "تمّ ✅ — ملخّص القيم (احفظها)"
cat <<SUMMARY

  CRAWL4AI_SERVICE_URL    = $CRAWL_URL
  CRAWL4AI_SERVICE_SECRET = $CRAWL4AI_SERVICE_SECRET
  CRON_SECRET             = $CRON_SECRET

  • GitHub secrets:  CRON_SECRET (✔)  VERCEL_URL (إن نُشر Vercel)
  • Vercel env (production): CRAWL4AI_SERVICE_URL / CRAWL4AI_SERVICE_SECRET / CRON_SECRET
  • المحرّكات الثلاثة (الأرشيف/نور/هنداوي) ستبدأ تلقائياً عبر GitHub Actions.
  • فعّل هنداوي فوراً (اختياري):
      curl -X POST "<vercel-url>/api/admin/hindawi-library/engine/start" -H "Authorization: Bearer <owner-id-token>"

SUMMARY
