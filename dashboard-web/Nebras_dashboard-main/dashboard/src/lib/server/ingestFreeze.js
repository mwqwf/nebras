/**
 * ❄️ علم التجميد المركزي لكل محرّكات الجلب (Internet Archive / نور / هنداوي).
 *
 * أُضيف بطلب المالك (2026-07-23): إيقاف كل الجلب الآليّ نهائياً مع الإبقاء على
 * كود المحرّكات سليماً (قد نحتاجه لاحقاً). هذا الحارس هو خطّ الدفاع الأخير:
 * حتى لو شُغِّل منفذ tick/ingest يدوياً (workflow_dispatch أو نداء مباشر)،
 * يعود فوراً دون جلب أيّ شيء.
 *
 * الجداول التلقائية عُطِّلت أيضاً في:
 *   • .github/workflows/ia-cron.yml
 *   • .github/workflows/library-engines-cron.yml
 *   • .github/workflows/noor-browser-ingest.yml
 *   • vercel.json (أُزيل cron الأرشيف)
 *
 * لإعادة تفعيل الجلب مستقبلاً: اجعل INGEST_FROZEN = false + أعِد الجداول أعلاه.
 */
export const INGEST_FROZEN = true;

/** ردّ موحّد لنقاط النهاية حين يكون الجلب مجمّداً (200 كي لا تبدو نبضة cron فاشلة). */
export const FROZEN_RESPONSE = {
	ok: true,
	frozen: true,
	skipped: true,
	reason: 'ingest_frozen'
};
