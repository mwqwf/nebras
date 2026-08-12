/**
 * GET /api/build-info — للتحقّق من أنّ النشر الحاليّ يحتوي ميزات Internet Archive.
 * عامّ (لا يحتاج تسجيل دخول).
 */
import { json } from '@sveltejs/kit';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { isAdminConfigured, getNebrasAdminApp } from '$lib/server/firebaseAdmin.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET() {
	let version = null;
	try {
		const p = join(process.cwd(), '.vercel', 'output', 'static', '_app', 'version.json');
		version = JSON.parse(readFileSync(p, 'utf8'))?.version ?? null;
	} catch {
		/* غير متاح محلياً */
	}

	let storageBucket = null;
	let projectId = null;
	if (isAdminConfigured()) {
		try {
			const app = getNebrasAdminApp();
			projectId = app.options?.projectId || null;
			storageBucket = app.options?.storageBucket || null;
		} catch {
			/* ignore */
		}
	}

	return json({
		ok: true,
		deployedAt: new Date().toISOString(),
		version,
		features: {
			internetArchiveBackgroundPipeline: true,
			internetArchiveCronTick: true,
			internetArchiveSearchRotation: true
		},
		firebase: {
			adminConfigured: isAdminConfigured(),
			projectId,
			storageBucket
		}
	});
}
