/**
 * Owner Code — توليد/تجزئة/تحقّق من رمز التحقّق الخاصّ بإنشاء الحسابات.
 *
 * كلّ الحالة تُخزَّن في Realtime DB على المسار التالي:
 *   dashboard_owner_codes/current = {
 *     codeHash,   // HMAC-SHA256(code + salt, secret)
 *     salt,
 *     expiresAt,  // epoch ms
 *     createdAt,  // epoch ms
 *     attempts,   // 0..5
 *     lastRequestedAt // epoch ms — لمنع الإغراق
 *   }
 *
 * قواعد تصميم صارمة:
 *   • الرمز لا يُخزَّن بصورته الخام أبدًا — HMAC فقط.
 *   • صلاحيّة 10 دقائق، بعدها يصبح الرمز لا يُقبل حتى لو كان صحيحًا.
 *   • 5 محاولات فاشلة متتالية تُبطِل الرمز الحالي وتُجبر على طلب رمز جديد.
 *   • حدّ معدّل الطلب: لا يُسمح بطلب رمز جديد قبل مرور 60 ثانية على الأخير.
 */

import crypto from 'node:crypto';
import { env } from '$env/dynamic/private';
import { getAdminDatabase } from './firebaseAdmin.js';

const DB_PATH = 'dashboard_owner_codes/current';
const CODE_TTL_MS = 10 * 60 * 1000;
const MIN_REQUEST_INTERVAL_MS = 60 * 1000;
const MAX_ATTEMPTS = 5;

function getSecret() {
	const secret = (env.OWNER_CODE_SECRET || process.env.OWNER_CODE_SECRET || '').trim();
	if (!secret) {
		throw new Error(
			'OWNER_CODE_SECRET is required and must be configured in environment variables.'
		);
	}
	return secret;
}

function hashCode(code, salt) {
	return crypto
		.createHmac('sha256', getSecret())
		.update(String(code) + '::' + String(salt))
		.digest('hex');
}

function generateSixDigitCode() {
	const n = crypto.randomInt(0, 1_000_000);
	return String(n).padStart(6, '0');
}

function generateSalt() {
	return crypto.randomBytes(16).toString('hex');
}

async function readCurrent() {
	const snap = await getAdminDatabase().ref(DB_PATH).get();
	return snap.exists() ? snap.val() : null;
}

async function writeCurrent(data) {
	await getAdminDatabase().ref(DB_PATH).set(data);
}

async function clearCurrent() {
	await getAdminDatabase().ref(DB_PATH).remove();
}

/**
 * يُولِّد رمزاً جديداً ويُخزِّن تجزئته.
 * يرفض الطلب إن مضى أقلّ من 60 ثانية على آخر طلب (حدّ معدّل).
 *
 * @returns {Promise<{ ok: true, code: string } | { ok: false, reason: 'rate_limited', retryAfterMs: number }>}
 */
export async function issueNewCode() {
	const now = Date.now();
	const current = await readCurrent();

	if (current?.lastRequestedAt && now - current.lastRequestedAt < MIN_REQUEST_INTERVAL_MS) {
		return {
			ok: false,
			reason: 'rate_limited',
			retryAfterMs: MIN_REQUEST_INTERVAL_MS - (now - current.lastRequestedAt)
		};
	}

	const code = generateSixDigitCode();
	const salt = generateSalt();

	await writeCurrent({
		codeHash: hashCode(code, salt),
		salt,
		expiresAt: now + CODE_TTL_MS,
		createdAt: now,
		attempts: 0,
		lastRequestedAt: now
	});

	return { ok: true, code };
}

/**
 * يتحقّق من صحّة الرمز الذي أدخله المستخدم.
 * عند النجاح: يُزيل الرمز من القاعدة (use-once).
 * عند الفشل: يزيد عدّاد المحاولات ويُبطل الرمز بعد MAX_ATTEMPTS.
 *
 * @param {string} code
 * @returns {Promise<{ ok: true } | { ok: false, reason: 'no_code'|'expired'|'invalid'|'too_many_attempts' }>}
 */
export async function verifyCode(code) {
	const trimmed = String(code || '').trim();
	if (!/^\d{6}$/.test(trimmed)) {
		return { ok: false, reason: 'invalid' };
	}

	const current = await readCurrent();
	if (!current) {
		return { ok: false, reason: 'no_code' };
	}

	const now = Date.now();
	if (now > current.expiresAt) {
		await clearCurrent();
		return { ok: false, reason: 'expired' };
	}

	const attempts = Number(current.attempts || 0);
	if (attempts >= MAX_ATTEMPTS) {
		await clearCurrent();
		return { ok: false, reason: 'too_many_attempts' };
	}

	const expected = current.codeHash;
	const actual = hashCode(trimmed, current.salt);

	const expectedBuf = Buffer.from(expected, 'hex');
	const actualBuf = Buffer.from(actual, 'hex');
	const match =
		expectedBuf.length === actualBuf.length && crypto.timingSafeEqual(expectedBuf, actualBuf);

	if (!match) {
		const nextAttempts = attempts + 1;
		if (nextAttempts >= MAX_ATTEMPTS) {
			await clearCurrent();
			return { ok: false, reason: 'too_many_attempts' };
		}
		await getAdminDatabase().ref(DB_PATH).update({ attempts: nextAttempts });
		return { ok: false, reason: 'invalid' };
	}

	await clearCurrent();
	return { ok: true };
}
