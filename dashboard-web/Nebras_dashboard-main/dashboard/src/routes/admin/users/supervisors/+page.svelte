<!--
  إدارة المشرفين — /admin/users/supervisors

  صفحة مخصّصة للمالك (Owner) فقط. تعرض كلّ الحسابات الموجودة في قائمة
  admins (`dashboard_users`) مع أزرار:
    • حظر مؤقّت / حظر نهائي (تعيين isBlocked = true مع وسم blockMode).
    • إلغاء الحظر (isBlocked = false).
    • حذف نهائي (إزالة السجلّ من الـ admins).

  لا يُسمح بتعديل سجلّ بدور 'owner' أو المالك نفسه — الأزرار تُعطَّل.

  الحماية:
    • واجهة: لا تظهر الصفحة إن لم يكن المستخدم role === 'owner'.
    • خادم: hooks.server.js + requireOwner على كلّ نقاط /api/admin/supervisors.
-->
<script>
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { getAuthState } from '$lib/stores/auth.svelte.js';
	import {
		listSupervisors,
		setSupervisorBlocked,
		removeSupervisor
	} from '$lib/api/supervisors.js';

	const authState = getAuthState();
	let isOwner = $derived(authState.role === 'owner');

	/** @type {Array<any>} */
	let rows = $state([]);
	let loading = $state(true);
	let errorMsg = $state('');

	let busyUid = $state('');

	/** @type {null | { type: 'block'|'permanent'|'unblock'|'delete', sup: any }} */
	let confirm = $state(null);

	// حماية عملاء عاديين — لو دخل مشرف عن طريق الخطأ، نعيده للوحة.
	$effect(() => {
		if (authState.isLoading) return;
		if (!authState.user || !authState.authorized) return;
		if (authState.role !== 'owner') goto('/moderator/content/files');
	});

	async function refresh() {
		loading = true;
		errorMsg = '';
		try {
			const data = await listSupervisors();
			rows = Array.isArray(data?.supervisors) ? data.supervisors : [];
		} catch (err) {
			errorMsg = err?.message || 'فشل جلب قائمة المشرفين.';
			rows = [];
		} finally {
			loading = false;
		}
	}

	onMount(() => {
		refresh();
	});

	function canActOn(sup) {
		if (!sup) return false;
		if (sup.role === 'owner') return false;
		if (sup.uid === authState.user?.uid) return false;
		return true;
	}

	function ask(type, sup) {
		if (!canActOn(sup)) return;
		confirm = { type, sup };
	}

	async function applyConfirm() {
		if (!confirm) return;
		const { type, sup } = confirm;
		confirm = null;
		if (!canActOn(sup)) return;

		busyUid = sup.uid;
		try {
			if (type === 'block') {
				await setSupervisorBlocked(sup.uid, true, 'temporary');
			} else if (type === 'permanent') {
				await setSupervisorBlocked(sup.uid, true, 'permanent');
			} else if (type === 'unblock') {
				await setSupervisorBlocked(sup.uid, false);
			} else if (type === 'delete') {
				await removeSupervisor(sup.uid);
			}
			await refresh();
		} catch (err) {
			errorMsg = err?.message || 'فشل تنفيذ العمليّة.';
		} finally {
			busyUid = '';
		}
	}

	function fmtDate(ms) {
		if (!ms || typeof ms !== 'number') return '—';
		try {
			return new Date(ms).toLocaleString('ar-EG', {
				dateStyle: 'medium',
				timeStyle: 'short'
			});
		} catch {
			return '—';
		}
	}

	function roleLabel(role) {
		if (role === 'owner') return 'المالك';
		return 'مشرف';
	}
</script>

<svelte:head>
	<title>إدارة المشرفين — Nebras Admin</title>
</svelte:head>

{#if !isOwner}
	<!-- حارس واجهة إضافي: لا يظهر شيء لغير المالك. -->
	<div class="page">
		<div class="empty">
			<h2>غير متاح</h2>
			<p>هذه الصفحة متاحة للمالك فقط.</p>
		</div>
	</div>
{:else}
	<div class="page">
		<div class="page-header">
			<div class="header-info">
				<h1 class="page-title">إدارة المشرفين</h1>
				<p class="page-desc">
					قائمة بالحسابات المصرّح لها بدخول لوحة التحكّم. يمكنك حظر/إلغاء
					الحظر أو الإزالة النهائيّة. لا يمكن التعديل على المالك أو على حسابك.
				</p>
			</div>
			<button class="btn btn-secondary" onclick={refresh} disabled={loading}>
				{loading ? 'جاري التحديث…' : 'تحديث'}
			</button>
		</div>

		{#if errorMsg}
			<div class="alert alert-error">{errorMsg}</div>
		{/if}

		<div class="table-card">
			{#if loading}
				<div class="table-loading">
					<div class="spinner"></div>
					<span>جاري جلب المشرفين…</span>
				</div>
			{:else if rows.length === 0}
				<div class="table-empty">
					<p>لا يوجد مشرفون بعد.</p>
				</div>
			{:else}
				<div class="table-responsive">
					<table class="data-table">
						<thead>
							<tr>
								<th>المشرف</th>
								<th>البريد</th>
								<th>الدور</th>
								<th>الحالة</th>
								<th>آخر دخول</th>
								<th class="th-actions">إجراءات</th>
							</tr>
						</thead>
						<tbody>
							{#each rows as sup (sup.uid)}
								{@const locked = !canActOn(sup)}
								<tr class:row-blocked={sup.isBlocked}>
									<td>
										<div class="user-cell">
											<div class="user-avatar">
												{#if sup.photoURL}
													<img src={sup.photoURL} alt="" referrerpolicy="no-referrer" />
												{:else}
													<span>{(sup.displayName || sup.email || '?').charAt(0).toUpperCase()}</span>
												{/if}
											</div>
											<div class="user-info">
												<span class="user-name">{sup.displayName || '—'}</span>
												<span class="user-id">#{sup.uid.slice(0, 8)}…</span>
											</div>
										</div>
									</td>
									<td><span class="text-secondary">{sup.email}</span></td>
									<td>
										<span class="role-badge" class:role-owner={sup.role === 'owner'}>
											{roleLabel(sup.role)}
										</span>
									</td>
									<td>
										{#if sup.isBlocked}
											<span class="status-badge blocked">
												<span class="status-dot"></span>
												محظور{sup.blockMode === 'permanent' ? ' (نهائي)' : ''}
											</span>
										{:else}
											<span class="status-badge active">
												<span class="status-dot"></span>
												نشِط
											</span>
										{/if}
									</td>
									<td class="text-secondary">{fmtDate(sup.lastSignedInAt || sup.createdAt)}</td>
									<td>
										<div class="action-btns">
											{#if sup.isBlocked}
												<button
													class="action-btn unblock"
													disabled={locked || busyUid === sup.uid}
													onclick={() => ask('unblock', sup)}
													title="إلغاء الحظر"
												>
													إلغاء الحظر
												</button>
											{:else}
												<button
													class="action-btn warn"
													disabled={locked || busyUid === sup.uid}
													onclick={() => ask('block', sup)}
													title="حظر مؤقّت"
												>
													حظر مؤقّت
												</button>
												<button
													class="action-btn danger"
													disabled={locked || busyUid === sup.uid}
													onclick={() => ask('permanent', sup)}
													title="حظر نهائي"
												>
													حظر نهائي
												</button>
											{/if}
											<button
												class="action-btn delete"
												disabled={locked || busyUid === sup.uid}
												onclick={() => ask('delete', sup)}
												title="إزالة نهائيّة من قائمة المشرفين"
											>
												حذف
											</button>
										</div>
									</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			{/if}
		</div>
	</div>
{/if}

{#if confirm}
	<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
	<div
		class="modal-overlay"
		role="dialog"
		tabindex="-1"
		onkeydown={(e) => e.key === 'Escape' && (confirm = null)}
		onclick={(e) => {
			if (e.target === e.currentTarget) confirm = null;
		}}
	>
		<div class="modal">
			<div class="modal-header">
				<h2 class="modal-title">
					{#if confirm.type === 'block'}حظر مؤقّت{:else if confirm.type === 'permanent'}حظر نهائي{:else if confirm.type === 'unblock'}إلغاء الحظر{:else}حذف نهائي{/if}
				</h2>
			</div>
			<p class="modal-body">
				{#if confirm.type === 'block'}
					سيتم تعليق وصول <strong>{confirm.sup.displayName || confirm.sup.email}</strong>
					فوراً. يمكنك إلغاء الحظر لاحقاً.
				{:else if confirm.type === 'permanent'}
					سيتم حظر <strong>{confirm.sup.displayName || confirm.sup.email}</strong>
					بشكل نهائي. يمكنك إلغاء الحظر لاحقاً إن رغبت.
				{:else if confirm.type === 'unblock'}
					سيتم إعادة صلاحيّة الدخول لـ
					<strong>{confirm.sup.displayName || confirm.sup.email}</strong>.
				{:else}
					سيتم <strong>حذف</strong>
					<strong>{confirm.sup.displayName || confirm.sup.email}</strong>
					من قائمة المشرفين نهائيّاً. لا يمكن التراجع إلّا بإعادة اعتماده عبر رمز المالك.
				{/if}
			</p>
			<div class="modal-actions">
				<button class="btn btn-secondary" onclick={() => (confirm = null)}>إلغاء</button>
				<button class="btn btn-primary" onclick={applyConfirm}>تأكيد</button>
			</div>
		</div>
	</div>
{/if}

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: 1.25rem;
		min-width: 0;
	}
	.page-header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 1rem;
		flex-wrap: wrap;
	}
	.page-title {
		font-size: 1.5rem;
		font-weight: 700;
		color: var(--color-surface-100);
		letter-spacing: -0.02em;
	}
	.page-desc {
		font-size: 0.8125rem;
		color: var(--color-surface-400);
		margin-top: 0.25rem;
		max-width: 680px;
	}

	.alert {
		padding: 0.75rem 1rem;
		border-radius: 10px;
		font-size: 0.8125rem;
	}
	.alert-error {
		background: rgba(244, 63, 94, 0.1);
		border: 1px solid rgba(244, 63, 94, 0.2);
		color: var(--color-danger-400);
	}

	.table-card {
		background: var(--color-surface-800);
		border: 1px solid var(--color-surface-700);
		border-radius: 14px;
		overflow: hidden;
	}
	.table-responsive {
		width: 100%;
		overflow-x: auto;
	}
	.table-loading,
	.table-empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		padding: 3rem;
		gap: 0.75rem;
		color: var(--color-surface-500);
		font-size: 0.875rem;
	}
	.spinner {
		width: 24px;
		height: 24px;
		border: 3px solid var(--color-surface-700);
		border-top-color: var(--color-primary-500);
		border-radius: 50%;
		animation: spin 0.6s linear infinite;
	}
	@keyframes spin {
		to {
			transform: rotate(360deg);
		}
	}

	.data-table {
		width: 100%;
		border-collapse: collapse;
	}
	.data-table th {
		text-align: start;
		padding: 0.75rem 1rem;
		font-size: 0.6875rem;
		font-weight: 600;
		color: var(--color-surface-400);
		text-transform: uppercase;
		letter-spacing: 0.05em;
		border-bottom: 1px solid var(--color-surface-700);
		white-space: nowrap;
	}
	.th-actions {
		text-align: end;
	}
	.data-table td {
		padding: 0.75rem 1rem;
		font-size: 0.8125rem;
		border-bottom: 1px solid var(--color-surface-700);
		vertical-align: middle;
		white-space: nowrap;
	}
	.data-table tbody tr:last-child td {
		border-bottom: none;
	}
	.data-table tbody tr:hover {
		background: var(--color-surface-700);
	}
	.row-blocked td {
		background: rgba(244, 63, 94, 0.04);
	}

	.user-cell {
		display: flex;
		align-items: center;
		gap: 0.75rem;
	}
	.user-avatar {
		width: 34px;
		height: 34px;
		border-radius: 50%;
		overflow: hidden;
		background: linear-gradient(135deg, var(--color-primary-700), var(--color-primary-500));
		display: flex;
		align-items: center;
		justify-content: center;
		color: white;
		font-weight: 700;
		font-size: 0.8125rem;
		flex-shrink: 0;
	}
	.user-avatar img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}
	.user-info {
		display: flex;
		flex-direction: column;
	}
	.user-name {
		font-weight: 600;
		color: var(--color-surface-100);
	}
	.user-id {
		font-size: 0.6875rem;
		color: var(--color-surface-500);
	}
	.text-secondary {
		color: var(--color-surface-400);
	}

	.role-badge {
		display: inline-flex;
		align-items: center;
		padding: 0.2rem 0.6rem;
		border-radius: 100px;
		font-size: 0.7rem;
		font-weight: 600;
		background: var(--color-surface-700);
		color: var(--color-surface-300);
	}
	.role-owner {
		background: rgba(251, 191, 36, 0.12);
		color: #fcd34d;
		border: 1px solid rgba(251, 191, 36, 0.28);
	}

	.status-badge {
		display: inline-flex;
		align-items: center;
		gap: 0.375rem;
		padding: 0.25rem 0.625rem;
		border-radius: 100px;
		font-size: 0.75rem;
		font-weight: 500;
	}
	.status-badge.active {
		background: rgba(16, 185, 129, 0.1);
		color: var(--color-primary-400);
	}
	.status-badge.blocked {
		background: rgba(244, 63, 94, 0.12);
		color: var(--color-danger-400);
	}
	.status-dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background: currentColor;
	}

	.action-btns {
		display: flex;
		gap: 0.375rem;
		justify-content: flex-end;
		flex-wrap: wrap;
	}
	.action-btn {
		padding: 0.375rem 0.75rem;
		font-size: 0.75rem;
		border-radius: 8px;
		border: 1px solid var(--color-surface-600);
		background: transparent;
		color: var(--color-surface-300);
		cursor: pointer;
		font-family: inherit;
		transition: all 0.15s;
	}
	.action-btn:hover:not(:disabled) {
		background: var(--color-surface-700);
	}
	.action-btn:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}
	.action-btn.warn {
		border-color: rgba(251, 191, 36, 0.4);
		color: #fcd34d;
	}
	.action-btn.warn:hover:not(:disabled) {
		background: rgba(251, 191, 36, 0.1);
	}
	.action-btn.danger {
		border-color: rgba(244, 63, 94, 0.4);
		color: var(--color-danger-400);
	}
	.action-btn.danger:hover:not(:disabled) {
		background: rgba(244, 63, 94, 0.1);
	}
	.action-btn.delete {
		border-color: rgba(244, 63, 94, 0.25);
		color: var(--color-danger-400);
	}
	.action-btn.delete:hover:not(:disabled) {
		background: rgba(244, 63, 94, 0.08);
	}
	.action-btn.unblock {
		border-color: rgba(16, 185, 129, 0.4);
		color: var(--color-primary-400);
	}
	.action-btn.unblock:hover:not(:disabled) {
		background: rgba(16, 185, 129, 0.08);
	}

	.btn {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.55rem 1rem;
		border-radius: 10px;
		font-size: 0.8125rem;
		font-weight: 600;
		font-family: inherit;
		cursor: pointer;
		border: none;
	}
	.btn-primary {
		background: linear-gradient(135deg, var(--color-primary-700), var(--color-primary-600));
		color: white;
	}
	.btn-secondary {
		background: var(--color-surface-700);
		color: var(--color-surface-300);
		border: 1px solid var(--color-surface-600);
	}
	.btn-secondary:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.modal-overlay {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.6);
		backdrop-filter: blur(4px);
		display: flex;
		align-items: center;
		justify-content: center;
		z-index: 100;
		padding: 1rem;
	}
	.modal {
		width: 100%;
		max-width: 420px;
		background: var(--color-surface-800);
		border: 1px solid var(--color-surface-700);
		border-radius: 14px;
	}
	.modal-header {
		padding: 1.1rem 1.3rem;
		border-bottom: 1px solid var(--color-surface-700);
	}
	.modal-title {
		font-size: 1.05rem;
		font-weight: 700;
		color: var(--color-surface-100);
	}
	.modal-body {
		padding: 1.1rem 1.3rem;
		color: var(--color-surface-300);
		font-size: 0.875rem;
		line-height: 1.7;
	}
	.modal-actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
		padding: 0.75rem 1rem 1rem;
	}

	.empty {
		padding: 3rem;
		text-align: center;
		color: var(--color-surface-400);
	}
</style>
