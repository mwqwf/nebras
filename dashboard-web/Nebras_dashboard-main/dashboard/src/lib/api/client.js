/**
 * API Client — Fetch wrapper (legacy Django backend).
 *
 * المصادقة الجديدة في لوحة التحكّم تعتمد على Firebase بشكل مباشر؛
 * هذا الملفّ يبقى كـ wrapper لأيّ مسارات قديمة في الخلفيّة (user/chat/
 * admin/moderator) لكنّها غير فعّالة حاليًا. نرفق Firebase ID token
 * كـ Bearer header إن توفّر، وإلّا نُرسل الطلب بلا Authorization.
 *
 * إن فشل الطلب بـ 401 فنحن لا نمتلك مسار refresh مخصّصاً — Firebase
 * يتكفّل بتجديد توكناته تلقائياً، وإن انتهت الجلسة فسيتولّى حارس
 * +layout.svelte إعادة المستخدم إلى /login.
 */

import { getFirebaseAuth } from '$lib/firebase/client.js';
import { getIdToken } from 'firebase/auth';

const API_BASE = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000';

async function getAuthHeaderValue() {
    try {
        const auth = getFirebaseAuth();
        if (!auth?.currentUser) return null;
        const token = await getIdToken(auth.currentUser, false);
        return token ? `Bearer ${token}` : null;
    } catch {
        return null;
    }
}

/**
 * Make an authenticated API request.
 * @param {string} endpoint - API path (e.g. '/api/users/me/')
 * @param {RequestInit} options - Fetch options
 * @returns {Promise<Response>}
 */
export async function apiRequest(endpoint, options = {}) {
    const url = `${API_BASE}${endpoint}`;
    const isFormData = options.body instanceof FormData;

    const headers = {
        ...(isFormData ? {} : { 'Content-Type': 'application/json' }),
        ...options.headers
    };

    const authHeader = await getAuthHeaderValue();
    if (authHeader) headers['Authorization'] = authHeader;

    return fetch(url, { ...options, headers, credentials: 'include' });
}

/**
 * Convenience GET request.
 */
export async function apiGet(endpoint) {
    return apiRequest(endpoint, { method: 'GET' });
}

/**
 * Convenience POST request with JSON body.
 */
export async function apiPost(endpoint, body) {
    return apiRequest(endpoint, {
        method: 'POST',
        body: JSON.stringify(body)
    });
}

/**
 * Convenience PATCH request with JSON body.
 */
export async function apiPatch(endpoint, body) {
    return apiRequest(endpoint, {
        method: 'PATCH',
        body: JSON.stringify(body)
    });
}

/**
 * Convenience DELETE request.
 */
export async function apiDelete(endpoint) {
    return apiRequest(endpoint, { method: 'DELETE' });
}

/**
 * Convenience PUT request with JSON body.
 */
export async function apiPut(endpoint, body) {
    return apiRequest(endpoint, {
        method: 'PUT',
        body: JSON.stringify(body)
    });
}

/**
 * Convenience POST request with FormData (multipart/form-data).
 * Used for file uploads. Do NOT stringify — pass a FormData object.
 */
export async function apiPostForm(endpoint, formData) {
    return apiRequest(endpoint, {
        method: 'POST',
        body: formData
    });
}

/**
 * Convenience PATCH request with FormData (multipart/form-data).
 * Used for file uploads. Do NOT stringify — pass a FormData object.
 */
export async function apiPatchForm(endpoint, formData) {
    return apiRequest(endpoint, {
        method: 'PATCH',
        body: formData
    });
}
