/**
 * User API — Profile editing and password management.
 */

import { apiPatchForm, apiPost } from '$lib/api/client.js';

/**
 * Update current user's profile.
 * Uses multipart/form-data because of profile_image (binary).
 * @param {Object} data - { username?, email?, first_name?, last_name?, profile_image? (File) }
 */
export async function updateProfile(data) {
    const fd = new FormData();
    if (data.username !== undefined) fd.append('username', data.username);
    if (data.email !== undefined) fd.append('email', data.email);
    if (data.first_name !== undefined) fd.append('first_name', data.first_name);
    if (data.last_name !== undefined) fd.append('last_name', data.last_name);
    if (data.profile_image instanceof File) fd.append('profile_image', data.profile_image);
    const res = await apiPatchForm('/api/users/me/edit/', fd);
    if (!res.ok) { const err = await res.json().catch(() => ({})); throw new Error(JSON.stringify(err)); }
    return res.json();
}

/**
 * Change current user's password.
 * @param {string} oldPassword
 * @param {string} newPassword
 */
export async function changePassword(oldPassword, newPassword) {
    const res = await apiPost('/api/users/me/password/change/', {
        old_password: oldPassword,
        new_password: newPassword
    });
    if (!res.ok) { const err = await res.json().catch(() => ({})); throw new Error(JSON.stringify(err)); }
    return res.json();
}
