/**
 * Crawl4AI admin API — same-origin `/api/admin/crawl4ai/*` (Owner only on server).
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

/**
 * @param {string} path
 * @param {{ method?: string, body?: any }} [opts]
 */
async function request(path, opts = {}) {
	const method = opts.method || 'GET';
	const headers = { 'Content-Type': 'application/json' };
	const auth = await bearer();
	if (auth) headers['Authorization'] = auth;

	const res = await fetch(path, {
		method,
		headers,
		body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined
	});

	let data = null;
	try {
		data = await res.json();
	} catch {
		/* non-json */
	}

	if (!res.ok) {
		const err = new Error(data?.message || data?.error || data?.detail || `http_${res.status}`);
		/** @type {any} */ (err).status = res.status;
		/** @type {any} */ (err).payload = data;
		throw err;
	}
	return data;
}

/** @returns {Promise<any>} */
export function getCrawl4aiStatus() {
	return request('/api/admin/crawl4ai/status');
}

/** @returns {Promise<any>} */
export function crawl4aiControl(action) {
	return request('/api/admin/crawl4ai/control', { method: 'POST', body: { action } });
}

/** @returns {Promise<any>} */
export function enqueueCrawl4aiUrl(url) {
	return request('/api/admin/crawl4ai/crawl', { method: 'POST', body: { url } });
}

/** @returns {Promise<any>} */
export function getCrawl4aiJobs(limit = 50) {
	const q = new URLSearchParams();
	if (limit) q.set('limit', String(limit));
	return request(`/api/admin/crawl4ai/jobs?${q.toString()}`);
}
