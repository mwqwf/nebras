# ╔══════════════════════════════════════════════════════════════════╗
# ║  نبراس — نشر كل شيء بأمر واحد (PowerShell / Windows)            ║
# ║  الاستعمال من مجلد dashboard:   .\deploy-all.ps1                 ║
# ║  يعادل deploy-all.sh: تسجيل دخول لمرّة واحدة ثم أتمتة كل الباقي.   ║
# ╚══════════════════════════════════════════════════════════════════╝
$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

$PROJECT = if ($env:GCLOUD_PROJECT) { $env:GCLOUD_PROJECT } else { 'nebras-9118c' }
$REGION  = if ($env:CLOUD_RUN_REGION) { $env:CLOUD_RUN_REGION } else { 'us-central1' }
$SERVICE = if ($env:CLOUD_RUN_SERVICE) { $env:CLOUD_RUN_SERVICE } else { 'nebras-crawl4ai' }
$GH_REPO = if ($env:GH_REPO) { $env:GH_REPO } else { 'mwqwf/Nebras_dashboard-main' }

function Say($m){ Write-Host "`n▶ $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "  ✅ $m" -ForegroundColor Green }
function Warn($m){ Write-Host "  ⚠ $m" -ForegroundColor Yellow }
function NewSecret(){ -join ((1..48) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) }) }

Say 'فحص الأدوات'
foreach ($t in 'gcloud','gh','npx') {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { throw "$t غير مثبّت." }
}
Ok 'الأدوات حاضرة'

Say 'تسجيل الدخول (لمرّة واحدة)'
$active = (gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>$null)
if (-not $active) { Warn 'لا حساب gcloud نشط — سيُفتح المتصفّح.'; gcloud auth login }
gcloud config set project $PROJECT | Out-Null
Ok "gcloud → مشروع $PROJECT"
gh auth status 2>$null; if ($LASTEXITCODE -ne 0) { Warn 'سجّل دخول GitHub.'; gh auth login }
Ok 'gh مسجَّل'

Say 'تفعيل APIs على GCP'
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com --project $PROJECT
Ok 'APIs مفعّلة'

Say 'توليد الأسرار'
$CRAWL_SECRET = if ($env:CRAWL4AI_SERVICE_SECRET) { $env:CRAWL4AI_SERVICE_SECRET } else { NewSecret }
$CRON_SECRET  = if ($env:CRON_SECRET) { $env:CRON_SECRET } else { NewSecret }
Ok 'secrets جاهزة'

Say 'نشر crawl4ai على Cloud Run (قد يطول لبناء Chromium)'
gcloud run deploy $SERVICE --source ./crawl4ai_service --project $PROJECT --region $REGION `
  --allow-unauthenticated --memory 2Gi --cpu 2 --timeout 300 --concurrency 4 --max-instances 3 `
  --set-env-vars "CRAWL4AI_SERVICE_SECRET=$CRAWL_SECRET"
$CRAWL_URL = (gcloud run services describe $SERVICE --project $PROJECT --region $REGION --format='value(status.url)')
Ok "crawl4ai منشورة: $CRAWL_URL"

Say "ضبط أسرار GitHub على $GH_REPO"
$CRON_SECRET | gh secret set CRON_SECRET --repo $GH_REPO --body -
Ok 'CRON_SECRET مضبوط على GitHub'

Say 'ضبط متغيّرات Vercel (production)'
function SetVercelEnv($name,$val){
  npx --yes vercel env rm $name production --yes 2>$null | Out-Null
  $val | npx --yes vercel env add $name production 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { Ok "$name مضبوط على Vercel" } else { Warn "أضِف $name يدوياً على Vercel." }
}
npx --yes vercel whoami 2>$null | Out-Null
if (($LASTEXITCODE -eq 0) -or $env:VERCEL_TOKEN) {
  npx --yes vercel link 2>$null | Out-Null
  SetVercelEnv 'CRAWL4AI_SERVICE_URL' $CRAWL_URL
  SetVercelEnv 'CRAWL4AI_SERVICE_SECRET' $CRAWL_SECRET
  SetVercelEnv 'CRON_SECRET' $CRON_SECRET
  $deploy = (npx --yes vercel deploy --prod --yes 2>$null | Select-Object -Last 1)
  if ($deploy) { Ok "أُعيد نشر Vercel: $deploy"; $deploy | gh secret set VERCEL_URL --repo $GH_REPO --body -; Ok 'VERCEL_URL مضبوط على GitHub' }
} else {
  Warn 'Vercel غير مسجّل دخول. شغّل: npx vercel login ثم أعد التشغيل، أو أضِف المتغيّرات يدوياً.'
}

Say 'تمّ ✅ — احفظ هذه القيم'
Write-Host ""
Write-Host "  CRAWL4AI_SERVICE_URL    = $CRAWL_URL"
Write-Host "  CRAWL4AI_SERVICE_SECRET = $CRAWL_SECRET"
Write-Host "  CRON_SECRET             = $CRON_SECRET"
Write-Host ""
Write-Host '  المحرّكات الثلاثة ستبدأ تلقائياً عبر GitHub Actions.'
