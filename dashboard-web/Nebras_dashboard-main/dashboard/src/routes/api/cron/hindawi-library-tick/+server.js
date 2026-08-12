/**
 * GET /api/cron/hindawi-library-tick
 *
 * نقطة دخول Cron لمحرّك مؤسسة هنداوي — مطابقة لنمط internet-archive-tick.
 * تُستدعى من GitHub Action دورياً. تجلب كتب PDF حرّة الترخيص (CC) فقط.
 */
import { json } from '@sveltejs/kit';
import { env } from '$env/dynamic/private';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';
import { runCronTick } from '$lib/server/hindawi/engine.js';
import { INGEST_FROZEN, FROZEN_RESPONSE } from '$lib/server/ingestFreeze.js';

export const config = { maxDuration: 60 };

// ⚡ تسريع: ننفّذ عدّة دورات في نداء cron واحد ضمن ميزانية زمنيّة آمنة
// (نفس نمط internet-archive-tick المُثبَت). كل دورة تتقدّم لتصنيف/صفحة
// تالية وتجلب دفعة كتب CC جديدة، فتمتلئ الأقسام بسرعة أكبر بكثير دون
// تجاوز مهلة Vercel ودون لمس المجلوب سابقاً (الـ registry يمنع التكرار).
const CRON_TIME_BUDGET_MS = 45_000;
const CRON_MAX_TICKS = 8;

function authorizeCron(event) {
	const secret = String(env.CRON_SECRET || '').trim();
	// 🔐 secure-by-configuration: صارم إن ضُبط CRON_SECRET، ويسمح بالنبضة إن لم
	// يُضبط بعد (يعيد السلوك الافتراضي قبل ضبط السرّ فلا يتوقّف المحرّك). التقوية
	// لاحقاً بإضافة المتغيّر فقط. هنداوي يجلب كتب CC فقط عبر بوّابة الترخيص.
	if (!secret) {
		console.warn(
			'[cron/hindawi-library-tick] CRON_SECRET غير مضبوط — يُسمح بالنبضة. اضبطه للتقوية (fail-closed).'
		);
		return { ok: true, unauthenticated: true };
	}
	const header =
		event.request.headers.get('authorization') ||
		event.request.headers.get('Authorization') ||
		'';
	const m = /^Bearer\s+(.+)$/i.exec(header.trim());
	const token = m ? m[1].trim() : '';
	if (!token || token !== secret) return { ok: false, reason: 'invalid_cron_secret' };
	return { ok: true };
}

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET(event) {
	// ❄️ الجلب مُجمّد بطلب المالك — لا ننفّذ أيّ دورة (2026-07-23).
	if (INGEST_FROZEN) return json(FROZEN_RESPONSE, { status: 200 });
	const auth = authorizeCron(event);
	if (!auth.ok) return json({ error: 'unauthorized', reason: auth.reason }, { status: 401 });
	if (!isAdminConfigured()) return json({ error: 'not_configured' }, { status: 501 });
	try {
		// حلقة دورات ضمن الميزانية الزمنيّة — تسريع آمن (مطابق لـ IA).
		const startedAt = Date.now();
		let ticks = 0;
		let processed = 0;
		let created = 0;
		let skipped = 0;
		let failed = 0;
		let lastError = null;
		let lastCategory = null;
		let lastCursor = null;
		const sample = [];
		while (ticks < CRON_MAX_TICKS && Date.now() - startedAt < CRON_TIME_BUDGET_MS) {
			let r;
			try {
				r = await runCronTick();
			} catch (e) {
				lastError = e?.message || String(e);
				break; // خطأ دورة → نتوقّف بهدوء (الـ cron التالي يعيد).
			}
			ticks += 1;
			processed += Number(r?.processed || 0);
			created += Number(r?.created || 0);
			skipped += Number(r?.skipped || 0);
			failed += Number(r?.failed || 0);
			if (r?.category) lastCategory = r.category;
			if (r?.cursor) lastCursor = r.cursor;
			if (Array.isArray(r?.sample) && sample.length < 6) {
				sample.push(...r.sample.slice(0, 6 - sample.length));
			}
			// لا جديد في هذه الدورة (created=0 و processed=0) ⇒ غالباً وصلنا
			// حدّ التصنيف الحاليّ؛ نكمل لأنّ الدورة التالية تتقدّم للتصنيف التالي،
			// لكن إن تكرّر الفراغ سيتكفّل backoff داخل المحرّك بإبطائه.
		}
		return json(
			{
				ok: true,
				cron: true,
				ticks,
				processed,
				created,
				skipped,
				failed,
				category: lastCategory,
				cursor: lastCursor,
				elapsedMs: Date.now() - startedAt,
				lastError,
				sample
			},
			{ status: 200 }
		);
	} catch (err) {
		console.error('[cron/hindawi-library-tick]', err);
		return json(
			{ error: 'tick_failed', reason: err?.reason || 'unknown', message: err?.message || String(err) },
			{ status: err?.status || 500 }
		);
	}
}
