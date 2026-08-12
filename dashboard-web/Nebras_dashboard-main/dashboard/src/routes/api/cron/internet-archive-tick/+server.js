/**
 * GET /api/cron/internet-archive-tick
 *
 * Vercel Cron entrypoint للمحرّك الآلي. السلوك:
 *   1) يتحقّق من Bearer $CRON_SECRET.
 *   2) يستدعي autoBootIfNeeded() — يضمن أنّ DEFAULT_CONFIG مكتوب في RTDB.
 *   3) ينفّذ runEngineTick() مباشرة — لا يتوقّف عند enabled=false إلا إن
 *      كان المستخدم أوقفه يدوياً عبر stopEngine (الذي يضع enabled=false).
 *      وإن غاب enabled كاملاً، autoBoot يضعه true ⇒ Cron يستمرّ.
 *
 * هذا يضمن: حتى بدون أيّ طلب admin، Vercel Cron وحده كافٍ لإطعام التطبيق.
 */
import { json } from '@sveltejs/kit';
import { env } from '$env/dynamic/private';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';
import { autoBootIfNeeded, runEngineTick } from '$lib/server/internetArchive/engine.js';
import { INGEST_FROZEN, FROZEN_RESPONSE } from '$lib/server/ingestFreeze.js';

/** Vercel Pro: حتى 300s؛ Hobby: 10s — نطلب 60 حيث يُسمح. */
export const config = {
	maxDuration: 60
};

// تسريع: ننفّذ عدّة دورات في نداء cron واحد ضمن ميزانية زمنيّة آمنة بدل
// دورة واحدة. يضاعف الإنتاجيّة دون تجاوز مهلة Vercel ودون لمس المجلوب سابقاً
// (الـ registry يمنع التكرار + تحقّق magic bytes يمنع التلف).
// ميزانية محافظة (25s) لهامش أمان واسع تحت maxDuration=60s: مع مهلة تنزيل
// 12s وdownload متوازٍ، أسوأ دورة ≈ 24s، فآخر دورة تبدأ قبل 25s وتنتهي
// قبل ~49s — لا 504. (التوسعة العامّة جلبت ملفّات أبطأ فاحتجنا الهامش.)
const CRON_TIME_BUDGET_MS = 25_000;
const CRON_MAX_TICKS = 8;

function authorizeCron(event) {
	const secret = String(env.CRON_SECRET || '').trim();
	// 🔐 secure-by-configuration: إن ضُبط CRON_SECRET نفرضه بصرامة (يُرفض أيّ
	// نداء بلا توكن مطابق). إن لم يُضبط بعد، نسمح بالنبضة كي لا يتوقّف إطعام
	// التطبيق — هذه هي الحالة الافتراضيّة قبل ضبط السرّ، وتُقوّى لاحقاً بمجرّد
	// إضافة المتغيّر في Vercel env + GitHub secret دون أيّ تعديل كود. المخاطرة
	// عند عدم الضبط تشغيليّة (تكلفة/قصف Internet Archive) لا أمنيّة على البيانات:
	// المحرّك يجلب محتوى PD/CC مُصفّى فقط، وregistry يمنع التكرار وratelimit يحدّ.
	if (!secret) {
		console.warn(
			'[cron/internet-archive-tick] CRON_SECRET غير مضبوط — يُسمح بالنبضة. اضبطه في Vercel env + GitHub secret للتقوية (fail-closed).'
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
	if (!auth.ok) {
		return json({ error: 'unauthorized', reason: auth.reason }, { status: 401 });
	}
	if (!isAdminConfigured()) {
		return json({ error: 'not_configured' }, { status: 501 });
	}

	try {
		// 1) نضمن وجود الإعدادات (enabled/seeds) بلا دورة inline.
		//    إن كان booted=false فالمستخدم أوقف المحرّك صراحةً → نحترم القرار.
		const boot = await autoBootIfNeeded({ runInlineTick: false });
		if (!boot.booted) {
			return json({ ok: true, skipped: true, reason: boot.reason || 'engine_disabled' });
		}

		// 2) حلقة دورات ضمن الميزانية الزمنيّة — تسريع آمن.
		const startedAt = Date.now();
		let ticks = 0;
		let processed = 0;
		let skipped = 0;
		let failed = 0;
		let lastError = null;
		const samples = [];
		while (ticks < CRON_MAX_TICKS && Date.now() - startedAt < CRON_TIME_BUDGET_MS) {
			try {
				const t = await runEngineTick();
				ticks += 1;
				processed += Number(t?.processed || 0);
				skipped += Number(t?.skipped || 0);
				failed += Number(t?.failed || 0);
				if (Array.isArray(t?.failureSamples) && samples.length < 6) {
					samples.push(...t.failureSamples.slice(0, 6 - samples.length));
				}
			} catch (e) {
				lastError = e?.message || String(e);
				break; // خطأ دورة → نتوقّف بهدوء (الـ cron التالي يعيد).
			}
		}
		return json({
			ok: true,
			cron: true,
			ticks,
			processed,
			skipped,
			failed,
			elapsedMs: Date.now() - startedAt,
			lastError,
			failureSamples: samples
		});
	} catch (err) {
		console.error('[cron/internet-archive-tick]', err);
		return json(
			{
				error: 'tick_failed',
				reason: err?.reason || 'unknown',
				message: err?.message || String(err)
			},
			{ status: err?.status || 500 }
		);
	}
}
