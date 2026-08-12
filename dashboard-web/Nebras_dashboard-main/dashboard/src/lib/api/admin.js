/**
 * Admin API — Moderator CRUD + Ban Management
 *
 * All list endpoints return paginated responses:
 * { count, next, previous, results: [] }
 */

import { apiGet, apiPost, apiPatch, apiPut, apiDelete } from '$lib/api/client.js';
import { authedJson } from '$lib/api/_authedFetch.js';

/**
 * إحصائيات عامة حقيقية من Firestore (أقسام رئيسي/فرعي/ثانوي + المحتوى +
 * توزيع الأنواع + أعلى الأقسام). تعكس ما في التطبيق فعلاً.
 * @returns {Promise<Object>}
 */
export async function getDashboardOverview() {
	return authedJson('/api/admin/aggregates/overview');
}

/**
 * إحصاءات حقيقية لكلّ مصدر محتوى (الأرشيف/نور/هنداوي/يدويّ): عدد الكتب،
 * الأقسام التي وُضعت فيها (رئيسي/فرعي/ثانوي)، وأعلى الأقسام لكلّ مصدر.
 * @returns {Promise<Object>}
 */
export async function getLibrarySourceStats() {
	return authedJson('/api/admin/aggregates/by-source');
}

// ─── Moderator Management ──────────────────────────────

/**
 * List moderators with optional search and pagination.
 * @param {Object} params - { search?, page? }
 * @returns {Promise<{ count, next, previous, results }>}
 */
export async function listModerators({ search = '', page = 1, is_active, is_staff } = {}) {
    const params = new URLSearchParams();
    if (search) params.set('search', search);
    if (page > 1) params.set('page', String(page));
    if (is_active !== undefined && is_active !== '') params.set('is_active', String(is_active));
    if (is_staff !== undefined && is_staff !== '') params.set('is_staff', String(is_staff));

    const query = params.toString();
    const endpoint = `/api/admin/moderators/${query ? `?${query}` : ''}`;

    const res = await apiGet(endpoint);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || 'Failed to fetch moderators');
    }
    return res.json();
}

/**
 * Create a new moderator.
 * @param {Object} data - { username, email, password, first_name, last_name }
 */
export async function createModerator(data) {
    const res = await apiPost('/api/admin/moderators/', data);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(JSON.stringify(err));
    }
    return res.json();
}

/**
 * Update a moderator (partial).
 * @param {number} id
 * @param {Object} data - Partial fields to update
 */
export async function updateModerator(id, data) {
    const res = await apiPatch(`/api/admin/moderators/${id}/`, data);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(JSON.stringify(err));
    }
    return res.json();
}

/**
 * Delete a moderator.
 * @param {number} id
 */
export async function deleteModerator(id) {
    const res = await apiDelete(`/api/admin/moderators/${id}/`);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || 'Failed to delete moderator');
    }
    return true;
}

// ─── Ban Management ────────────────────────────────────

/**
 * List bans with filters and pagination.
 * @param {Object} params - { user?, is_banned?, search?, page? }
 * @returns {Promise<{ count, next, previous, results }>}
 */
export async function listBans({ user, is_banned, search = '', page = 1 } = {}) {
    const params = new URLSearchParams();
    if (user !== undefined && user !== '') params.set('user', String(user));
    if (is_banned !== undefined && is_banned !== '') params.set('is_banned', String(is_banned));
    if (search) params.set('search', search);
    if (page > 1) params.set('page', String(page));

    const query = params.toString();
    const endpoint = `/api/admin/bans/${query ? `?${query}` : ''}`;

    const res = await apiGet(endpoint);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || 'Failed to fetch bans');
    }
    return res.json();
}

/**
 * Apply a ban to a user.
 * @param {Object} data - { user, reason, banned_end, is_banned: true }
 */
export async function applyBan(data) {
    const res = await apiPost('/api/admin/bans/', {
        ...data,
        is_banned: true
    });
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(JSON.stringify(err));
    }
    return res.json();
}

/**
 * Lift an existing ban.
 * @param {number} banId
 */
export async function liftBan(banId) {
    const res = await apiPatch(`/api/admin/bans/${banId}/`, { is_banned: false });
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || 'Failed to lift ban');
    }
    return res.json();
}

// ─── Main Sections Management ──────────────────────────

/**
 * List main sections with optional search, created_by filter, and pagination.
 * @param {Object} params - { search?, created_by?, page? }
 * @returns {Promise<{ count, next, previous, results }>}
 */
export async function listMainSections({ search = '', created_by, page = 1 } = {}) {
    const params = new URLSearchParams();
    if (search) params.set('search', search);
    if (page > 1) params.set('page', String(page));
    if (created_by !== undefined && created_by !== '') params.set('created_by', String(created_by));

    const query = params.toString();
    const endpoint = `/api/admin/sections/main/${query ? `?${query}` : ''}`;

    const res = await apiGet(endpoint);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || 'Failed to fetch sections');
    }
    return res.json();
}

/**
 * Retrieve a single main section.
 * @param {number} id
 */
export async function getMainSection(id) {
    const res = await apiGet(`/api/admin/sections/main/${id}/`);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || 'Failed to fetch section');
    }
    return res.json();
}

/**
 * Full update a main section (PUT).
 * @param {number} id
 * @param {Object} data - Full section object
 */
export async function putMainSection(id, data) {
    const res = await apiPut(`/api/admin/sections/main/${id}/`, data);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(JSON.stringify(err));
    }
    return res.json();
}

/**
 * Partial update a main section (PATCH).
 * @param {number} id
 * @param {Object} data - Partial fields to update
 */
export async function patchMainSection(id, data) {
    const res = await apiPatch(`/api/admin/sections/main/${id}/`, data);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(JSON.stringify(err));
    }
    return res.json();
}

/**
 * Delete a main section.
 * @param {number} id
 */
export async function deleteMainSection(id) {
    const res = await apiDelete(`/api/admin/sections/main/${id}/`);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || 'Failed to delete section');
    }
    return true;
}

// ─── Sub Sections Management ───────────────────────────

/**
 * List sub sections filtered by main_section, with search and pagination.
 * @param {Object} params - { main_section?, search?, created_by?, page? }
 */
export async function listSubSections({ main_section, search = '', created_by, page = 1 } = {}) {
    const params = new URLSearchParams();
    if (main_section !== undefined && main_section !== '') params.set('main_section', String(main_section));
    if (search) params.set('search', search);
    if (page > 1) params.set('page', String(page));
    if (created_by !== undefined && created_by !== '') params.set('created_by', String(created_by));

    const query = params.toString();
    const endpoint = `/api/admin/sections/sub/${query ? `?${query}` : ''}`;

    const res = await apiGet(endpoint);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || 'Failed to fetch sub sections');
    }
    return res.json();
}

/**
 * Partial update a sub section (PATCH).
 * @param {number} id
 * @param {Object} data
 */
export async function patchSubSection(id, data) {
    const res = await apiPatch(`/api/admin/sections/sub/${id}/`, data);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(JSON.stringify(err));
    }
    return res.json();
}

/**
 * Delete a sub section.
 * @param {number} id
 */
export async function deleteSubSection(id) {
    const res = await apiDelete(`/api/admin/sections/sub/${id}/`);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || 'Failed to delete sub section');
    }
    return true;
}

// ─── Secondary Sub Sections Management ─────────────────

/**
 * List secondary sub sections filtered by sub_section, with search and pagination.
 * @param {Object} params - { sub_section?, search?, created_by?, page? }
 */
export async function listSecondarySections({ sub_section, search = '', created_by, page = 1 } = {}) {
    const params = new URLSearchParams();
    if (sub_section !== undefined && sub_section !== '') params.set('sub_section', String(sub_section));
    if (search) params.set('search', search);
    if (page > 1) params.set('page', String(page));
    if (created_by !== undefined && created_by !== '') params.set('created_by', String(created_by));

    const query = params.toString();
    const endpoint = `/api/admin/sections/secondary/${query ? `?${query}` : ''}`;

    const res = await apiGet(endpoint);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || 'Failed to fetch secondary sections');
    }
    return res.json();
}

/**
 * Partial update a secondary sub section (PATCH).
 * @param {number} id
 * @param {Object} data
 */
export async function patchSecondarySection(id, data) {
    const res = await apiPatch(`/api/admin/sections/secondary/${id}/`, data);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(JSON.stringify(err));
    }
    return res.json();
}

/**
 * Delete a secondary sub section.
 * @param {number} id
 */
export async function deleteSecondarySection(id) {
    const res = await apiDelete(`/api/admin/sections/secondary/${id}/`);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || 'Failed to delete secondary section');
    }
    return true;
}

// ─── R2 File Management (Admin) ────────────────────────

/**
 * List all R2 files (admin).
 */
export async function listAllFiles({
    search = '', created_by, subsection, main_section,
    content_type, upload_type, page = 1
} = {}) {
    const qp = new URLSearchParams();
    if (search) qp.set('search', search);
    if (created_by) qp.set('metadata__created_by', String(created_by));
    if (subsection) qp.set('metadata__subsection', String(subsection));
    if (main_section) qp.set('metadata__subsection__main_section', String(main_section));
    if (content_type) qp.set('metadata__content_type', content_type);
    if (upload_type) qp.set('upload_type', upload_type);
    if (page > 1) qp.set('page', String(page));
    const query = qp.toString();
    const res = await apiGet(`/api/admin/content/files/${query ? `?${query}` : ''}`);
    if (!res.ok) { const err = await res.json().catch(() => ({})); throw new Error(err.detail || 'Failed to fetch files'); }
    return res.json();
}

/** Update an R2 file as admin (PATCH). */
export async function patchAdminFile(id, data) {
    const res = await apiPatch(`/api/admin/content/files/${id}/`, data);
    if (!res.ok) { const err = await res.json().catch(() => ({})); throw new Error(JSON.stringify(err)); }
    return res.json();
}

/** Delete an R2 file as admin. */
export async function deleteAdminFile(id) {
    const res = await apiDelete(`/api/admin/content/files/${id}/`);
    if (!res.ok) { const err = await res.json().catch(() => ({})); throw new Error(err.detail || 'Failed to delete file'); }
    return true;
}

// ─── Statistics Management ─────────────────────────────

/**
 * Get overall platforms totals (Moderators, Content, Sections, Chat).
 * @returns {Promise<Object>}
 */
export async function getAdminTotals() {
    const res = await apiGet('/api/admin/statistics/totals/');
    if (!res.ok) throw new Error('Failed to fetch admin totals');
    return res.json();
}

/**
 * Get content distribution (Video, Audio, Document, Youtube).
 * @returns {Promise<Object>}
 */
export async function getAdminContentDistribution() {
    const res = await apiGet('/api/admin/statistics/content-distribution/');
    if (!res.ok) throw new Error('Failed to fetch admin content distribution');
    return res.json();
}

/**
 * Get top main sections by content count.
 * @returns {Promise<Array>}
 */
export async function getAdminTopSections() {
    const res = await apiGet('/api/admin/statistics/top-sections/');
    if (!res.ok) throw new Error('Failed to fetch admin top sections');
    return res.json();
}

/**
 * Get registration timeline for last 30 days.
 * @returns {Promise<{data: Array}>}
 */
export async function getAdminRegistrationsChart() {
    const res = await apiGet('/api/admin/statistics/registrations-chart/');
    if (!res.ok) throw new Error('Failed to fetch admin registrations chart');
    return res.json();
}

/**
 * Get content added timeline for last 30 days.
 * @returns {Promise<{data: Array}>}
 */
export async function getAdminContentAddedChart() {
    const res = await apiGet('/api/admin/statistics/content-added-chart/');
    if (!res.ok) throw new Error('Failed to fetch admin content added chart');
    return res.json();
}
