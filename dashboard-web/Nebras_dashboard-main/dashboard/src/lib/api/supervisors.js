/**
 * Supervisors API — يخدم صفحة إدارة المشرفين (المالك فقط).
 *
 * يُضيف Firebase ID token كـ Bearer تلقائيّاً، لأنّ `hooks.server.js`
 * يفرضه على أيّ مسار يبدأ بـ `/api/admin/*`.
 */

import { getFirebaseAuth } from '$lib/firebase/client.js';
import { getIdToken } from 'firebase/auth';

async function bearer() {
	try {
		const auth = getFirebaseAuth();
		if (!auth?.currentUser) return null;
		const t = await getIdToken(auth.currentUser, false);
		return t ? `Bearer ${t}` : null;
	} catch {
		return null;
	}
}

async function request(path, { method = 'GET', body } = {}) {
	const headers = { 'Content-Type': 'application/json' };
	const auth = await bearer();
	if (auth) headers['Authorization'] = auth;

	const res = await fetch(path, {
		method,
		headers,
		body: body ? JSON.stringify(body) : undefined
	});

	let data = null;
	try {
		data = await res.json();
	} catch {
		/* non-json */
	}

	if (!res.ok) {
		const err = new Error(data?.message || data?.error || `http_${res.status}`);
		/** @type {any} */ (err).status = res.status;
		/** @type {any} */ (err).payload = data;
		throw err;
	}
	return data;
}

/** GET list */
export async function listSupervisors() {
	return request('/api/admin/supervisors');
}

/** PATCH block/unblock */
export async function setSupervisorBlocked(uid, isBlocked, mode = 'temporary') {
	return request(`/api/admin/supervisors/${encodeURIComponent(uid)}`, {
		method: 'PATCH',
		body: { isBlocked: Boolean(isBlocked), mode }
	});
}

/** DELETE permanent removal */
export async function removeSupervisor(uid) {
	return request(`/api/admin/supervisors/${encodeURIComponent(uid)}`, {
		method: 'DELETE'
	});
}
