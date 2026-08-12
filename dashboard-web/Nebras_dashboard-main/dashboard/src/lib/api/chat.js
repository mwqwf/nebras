/**
 * Chat API — WebSocket connection + REST file upload + admin moderation.
 */

import { apiPostForm, apiGet, apiDelete } from '$lib/api/client.js';
import { getAuthState } from '$lib/stores/auth.svelte.js';

const API_BASE = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000';

/**
 * Create a WebSocket connection for the chat.
 * @param {Object} callbacks - { onHistory, onMessage, onOpen, onClose, onError }
 * @returns {{ send: (data: object) => void, close: () => void }}
 */
export function createChatSocket({ onHistory, onMessage, onOpen, onClose, onError } = {}) {
    const state = getAuthState();
    const token = state.accessToken;

    // Build WS URL: replace http(s) with ws(s)
    const wsBase = API_BASE.replace(/^http/, 'ws');
    const wsUrl = `${wsBase}/ws/chat/?token=${token}`;

    let socket = null;
    let intentionalClose = false;

    function connect() {
        socket = new WebSocket(wsUrl);

        socket.onopen = () => {
            onOpen?.();
        };

        socket.onmessage = (event) => {
            try {
                const data = JSON.parse(event.data);
                if (data.type === 'history') {
                    onHistory?.(data.messages || []);
                } else if (data.type === 'message') {
                    onMessage?.(data);
                }
            } catch (err) {
                console.error('Chat WS parse error:', err);
            }
        };

        socket.onclose = (event) => {
            onClose?.(event);
            // Auto-reconnect after 3s unless intentionally closed
            if (!intentionalClose) {
                setTimeout(() => connect(), 3000);
            }
        };

        socket.onerror = (err) => {
            onError?.(err);
        };
    }

    connect();

    return {
        send(data) {
            if (socket?.readyState === WebSocket.OPEN) {
                socket.send(JSON.stringify(data));
            }
        },
        close() {
            intentionalClose = true;
            socket?.close();
        }
    };
}

/**
 * Upload a file for chat attachment.
 * POST /api/chat/files/ with multipart/form-data
 * @param {File} file
 * @returns {Promise<{ id: number, file: string, user: number }>}
 */
export async function uploadChatFile(file) {
    const fd = new FormData();
    fd.append('file', file);
    const res = await apiPostForm('/api/chat/files/', fd);
    if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || err.file?.[0] || 'File upload failed');
    }
    return res.json();
}

/**
 * List all chat messages (admin only).
 * GET /api/admin/chat/messages/?page=N
 */
export async function listAdminMessages({ page = 1 } = {}) {
    const params = new URLSearchParams();
    if (page) params.set('page', page);
    const res = await apiGet(`/api/admin/chat/messages/?${params}`);
    if (!res.ok) throw new Error('Failed to load messages');
    return res.json();
}

/**
 * Delete a chat message (admin only).
 * DELETE /api/admin/chat/messages/<id>/
 */
export async function deleteAdminMessage(id) {
    const res = await apiDelete(`/api/admin/chat/messages/${id}/`);
    if (!res.ok) throw new Error('Failed to delete message');
    return true;
}
