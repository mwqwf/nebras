/**
 * POST /api/admin/internet-archive/engine/diagnose
 *
 * endpoint تشخيصي شامل — ينفّذ tick متزامن **مع** إرجاع كل التفاصيل
 * عن البيئة والإعدادات حتى نكشف بدقّة لماذا لا يظهر محتوى:
 *
 *   1) Env vars (مُستترة) — هل CRON_SECRET / NEBRAS_STORAGE_BUCKET موجودة؟
 *   2) Firebase Admin — هل مهيّأ؟
 *   3) RTDB config — هل ia_library_engine موجود؟
 *   4) Cache يكتب أوّل دفعة نتائج من IA.
 *   5) ينفّذ runEngineTick متزامناً ويُرجع النتيجة الكاملة + stack trace
 *      الكامل لأيّ خطأ.
 *
 * الاستخدام: المسؤول يفتح صفحة /admin/internet-archive ويضغط "فحص النظام"،
 * ثمّ يرسل لنا JSON الكامل.
 */
import { json } from '@sveltejs/kit';
import { env } from '$env/dynamic/private';
import {
	getAdminDatabase,
	isAdminConfigured,
	getNebrasAdminApp
} from '$lib/server/firebaseAdmin.js';
import { requireAdminRole, requireAdminSdk } from '$lib/server/adminApiAuth.js';
import { autoBootIfNeeded, runEngineTick } from '$lib/server/internetArchive/engine.js';
import { scrapeOnePage, buildLuceneQuery } from '$lib/server/internetArchive/search.js';

function masked(value) {
	const s = String(value || '');
	if (!s) return null;
	if (s.length <= 6) return '***';
	return `${s.slice(0, 4)}…${s.slice(-2)} (len=${s.length})`;
}

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const gate = requireAdminRole(event);
	if (!gate.ok) return gate.response;
	const sdk = requireAdminSdk();
	if (!sdk.ok) return sdk.response;

	const report = {
		ok: true,
		ts: new Date().toISOString(),
		env: {
			CRON_SECRET: masked(env.CRON_SECRET),
			NEBRAS_STORAGE_BUCKET: env.NEBRAS_STORAGE_BUCKET || env.FIREBASE_STORAGE_BUCKET || null,
			FCM_BROADCAST_TOPIC: env.FCM_BROADCAST_TOPIC || null,
			NODE_ENV: env.NODE_ENV || null
		},
		firebase: {
			adminConfigured: isAdminConfigured(),
			projectId: null,
			storageBucket: null
		},
		rtdb: {
			ia_library_engine_config_exists: false,
			ia_library_engine_enabled: null,
			ia_library_engine_seeds_count: 0,
			ia_library_registry_count: 0,
			ia_library_failures_count: 0
		},
		ia_api: {
			sample_query: null,
			sample_total: null,
			sample_first_identifier: null,
			error: null
		},
		autoBoot: null,
		tickResult: null,
		tickError: null
	};

	// Firebase Admin meta
	try {
		const app = getNebrasAdminApp();
		report.firebase.projectId = app?.options?.projectId || null;
		report.firebase.storageBucket = app?.options?.storageBucket || null;
	} catch (err) {
		report.firebase.error = err?.message || String(err);
	}

	// RTDB state
	try {
		const db = getAdminDatabase();
		const [cfg, reg, fail] = await Promise.all([
			db.ref('ia_library_engine/config').get(),
			db.ref('ia_library_registry').get(),
			db.ref('ia_library_failures').get()
		]);
		report.rtdb.ia_library_engine_config_exists = cfg.exists();
		if (cfg.exists()) {
			const v = cfg.val() || {};
			report.rtdb.ia_library_engine_enabled = v.enabled === undefined ? null : Boolean(v.enabled);
			report.rtdb.ia_library_engine_seeds_count = Array.isArray(v.seeds) ? v.seeds.length : 0;
		}
		if (reg.exists()) {
			report.rtdb.ia_library_registry_count = Object.keys(reg.val() || {}).length;
		}
		if (fail.exists()) {
			report.rtdb.ia_library_failures_count = Object.keys(fail.val() || {}).length;
		}
	} catch (err) {
		report.rtdb.error = err?.message || String(err);
	}

	// IA API reachability — نطاق صغير سريع للتحقّق أنّ archive.org يستجيب
	try {
		const q = buildLuceneQuery({
			q: 'language:Arabic',
			nebrasTypes: ['document'],
			collections: ['opensource_arabic']
		});
		report.ia_api.sample_query = q;
		const page = await scrapeOnePage({ query: q, count: 3 });
		report.ia_api.sample_total = page.total;
		report.ia_api.sample_first_identifier = page.items?.[0]?.identifier || null;
	} catch (err) {
		report.ia_api.error = {
			message: err?.message || String(err),
			reason: err?.reason || null,
			status: err?.status || null
		};
	}

	// autoBoot (يكتب DEFAULT_CONFIG لو لا يوجد)
	try {
		report.autoBoot = await autoBootIfNeeded({ runInlineTick: false });
	} catch (err) {
		report.autoBoot = { error: err?.message || String(err), reason: err?.reason };
	}

	// tick متزامن — هذا يكشف الخطأ الفعلي إن وُجد
	try {
		report.tickResult = await runEngineTick();
	} catch (err) {
		report.tickError = {
			message: err?.message || String(err),
			reason: err?.reason || null,
			status: err?.status || null,
			stack: String(err?.stack || '').split('\n').slice(0, 6).join('\n')
		};
		report.ok = false;
	}

	return json(report);
}
