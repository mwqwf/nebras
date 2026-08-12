/**
 * DELETE /api/admin/noor-library/engine/reset
 *
 * 🛑 «الزرّ النووي» (Factory Reset) — الحذف الشامل لكلّ ما أحدثه محرّك نور —
 * أُزيل نهائيًّا. لإعادة المؤشّر فقط (غير مدمّر) استعمل
 * DELETE /api/admin/noor-library/engine/seed.
 */
import { json } from '@sveltejs/kit';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function DELETE() {
	return json(
		{ error: 'feature_removed', message: 'خاصيّة الحذف الشامل أُزيلت نهائيًّا.' },
		{ status: 410 }
	);
}
