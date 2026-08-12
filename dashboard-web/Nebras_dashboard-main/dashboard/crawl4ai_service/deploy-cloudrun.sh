#!/usr/bin/env bash
# نشر خدمة crawl4ai على Cloud Run داخل نفس مشروع Firebase الذي تستضيف فيه
# App Hosting لوحة نبراس. يبني الصورة من Dockerfile في هذا المجلد.
#
# الاستعمال (من مجلد crawl4ai_service/):
#   CRAWL4AI_SERVICE_SECRET=your-shared-secret ./deploy-cloudrun.sh
#
# المتطلّبات: gcloud CLI مُصادَق عليه (gcloud auth login) ومشروع مضبوط.
set -euo pipefail
cd "$(dirname "$0")"

PROJECT="${GCLOUD_PROJECT:-nebras-9118c}"
REGION="${CLOUD_RUN_REGION:-us-central1}"
SERVICE="${CLOUD_RUN_SERVICE:-nebras-crawl4ai}"
SECRET="${CRAWL4AI_SERVICE_SECRET:-}"

# السرّ المشترك إلزاميّ: الخدمة ستكون متاحة عبر الإنترنت (allow-unauthenticated)
# لأنّ عميل اللوحة يصادق بترويسة X-Crawl4AI-Secret لا بـ ID token. السرّ القويّ
# هو حاجز الحماية الوحيد، فلا تنشر بدونه.
if [[ -z "$SECRET" ]]; then
  echo "❌ CRAWL4AI_SERVICE_SECRET مطلوب. مثال:"
  echo "   CRAWL4AI_SERVICE_SECRET=\$(openssl rand -hex 24) ./deploy-cloudrun.sh"
  exit 1
fi

echo "نشر $SERVICE إلى مشروع $PROJECT في $REGION ..."

# allow-unauthenticated + سرّ مشترك إلزاميّ (يطابق ما يرسله crawl4aiClient.js).
# concurrency منخفض لأنّ كلّ طلب يفتح متصفّح Chromium (ذاكرة مرتفعة).
gcloud run deploy "$SERVICE" \
  --source . \
  --project "$PROJECT" \
  --region "$REGION" \
  --allow-unauthenticated \
  --memory 2Gi \
  --cpu 2 \
  --timeout 300 \
  --concurrency 4 \
  --max-instances 3 \
  --set-env-vars "CRAWL4AI_SERVICE_SECRET=$SECRET"

URL="$(gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" --format='value(status.url)')"
echo ""
echo "✅ تمّ النشر: $URL"
echo "اضبط في App Hosting (apphosting.yaml أو Secret Manager):"
echo "  CRAWL4AI_SERVICE_URL=$URL"
echo "  CRAWL4AI_SERVICE_SECRET=<نفس السرّ أعلاه>"
echo ""
echo "ملاحظة: امنح حساب خدمة App Hosting دور roles/run.invoker على $SERVICE"
echo "ليستطيع استدعاءها (خدمة داخليّة)، أو اجعلها allow-unauthenticated إن لزم."
