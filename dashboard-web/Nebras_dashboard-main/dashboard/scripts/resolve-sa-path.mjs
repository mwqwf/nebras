/**
 * يطبع مسار ملف مفتاح الخدمة فقط (سطر واحد) — لا يطبع محتوى المفتاح.
 *
 *   npm run resolve:sa-path
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = (npm run resolve:sa-path --silent)
 */
import { resolveServiceAccountFilePath } from './load-admin-credential.mjs';

try {
	console.log(resolveServiceAccountFilePath());
} catch (err) {
	console.error(err?.message || err);
	process.exit(1);
}
