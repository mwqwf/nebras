<!--
  تدقيق المحتوى — واجهة المالك لمراجعة المحتوى غير المُتحقَّق من مصدره/
  ترخيصه (رفع يدويّ بلا ضمان آليّ، أو روابط أرشيف) وحذف المخالف منه.
-->
<script>
	import { onMount } from 'svelte';
	import { runContentAudit, deleteAuditContent } from '$lib/api/moderation.js';

	let items = $state([]);
	let scanned = $state(0);
	let flaggedCount = $state(0);
	let loading = $state(true);
	let error = $state('');
	let busyId = $state('');

	const FLAGS = {
		terrorism: { label: 'إصدار/تنظيم متطرّف', color: '#7f1d1d', bg: '#fee2e2' },
		copyright: { label: 'علامة تجاريّة/حقوق نشر', color: '#92400e', bg: '#fef3c7' },
		sexual: { label: 'ألفاظ جنسيّة صريحة', color: '#9d174d', bg: '#fce7f3' },
		archive_link: { label: 'رابط Archive.org', color: '#374151', bg: '#f3f4f6' }
	};

	function flagMeta(code) {
		return FLAGS[code] || { label: code, color: '#374151', bg: '#f3f4f6' };
	}

	// ترتيب عرض التصنيفات (الأخطر أولاً).
	const CATEGORY_ORDER = ['terrorism', 'sexual', 'copyright', 'archive_link'];

	// تجميع العناصر حسب التصنيف — يظهر كلّ محتوًى تحت كلّ تصنيف يطابقه.
	let groups = $derived(
		CATEGORY_ORDER.map((cat) => ({
			cat,
			meta: flagMeta(cat),
			items: items.filter((it) => (it.flags || []).includes(cat))
		})).filter((g) => g.items.length > 0)
	);

	async function loadAudit() {
		loading = true;
		error = '';
		try {
			const data = await runContentAudit();
			items = data.items || [];
			scanned = data.scanned || 0;
			flaggedCount = data.flaggedCount || 0;
		} catch (e) {
			error = e?.status === 403 ? 'هذه الصفحة للمالك فقط.' : (e?.message || 'تعذّر تشغيل التدقيق.');
			items = [];
		} finally {
			loading = false;
		}
	}

	async function del(item) {
		const ok = confirm(
			`حذف هذا المحتوى نهائيّاً؟\n\n"${item.title || item.contentId}"\n\nلا يمكن التراجع.`
		);
		if (!ok) return;
		busyId = item.contentId;
		try {
			await deleteAuditContent({ contentId: item.contentId, contentType: item.contentType });
			items = items.filter((x) => x.contentId !== item.contentId);
			flaggedCount = Math.max(0, flaggedCount - 1);
		} catch (e) {
			alert(e?.message || 'فشل الحذف. حاول مجدّداً.');
		} finally {
			busyId = '';
		}
	}

	onMount(loadAudit);
</script>

<div class="audit-page">
	<header class="head">
		<h1>تدقيق المحتوى</h1>
		<button class="refresh" onclick={loadAudit} disabled={loading}>إعادة الفحص</button>
	</header>
	<p class="hint">
		مراجعة المحتوى الذي يحتاج تحقّقاً من الملكية الفكرية / المصدر. احذف المخالف منه فقط.
	</p>

	{#if loading}
		<p class="state">جارٍ الفحص…</p>
	{:else if error}
		<p class="state err">{error}</p>
	{:else}
		<p class="summary">فُحص {scanned} عنصراً · مُعلَّم: {flaggedCount}</p>
		{#if groups.length === 0}
			<p class="state">لا يوجد محتوى مُعلَّم. ✅</p>
		{:else}
			{#each groups as g (g.cat)}
				<section class="group">
					<h2 class="group-head" style="color:{g.meta.color};border-color:{g.meta.color}">
						<span class="dot" style="background:{g.meta.bg}"></span>
						{g.meta.label}
						<span class="count">{g.items.length}</span>
					</h2>
					<ul class="list">
						{#each g.items as it (g.cat + '|' + it.contentId)}
							<li class="card">
								<div class="flags">
									{#each it.flags as f}
										{@const m = flagMeta(f)}
										<span class="badge" style="color:{m.color};background:{m.bg}">{m.label}</span>
									{/each}
									<span class="type">{it.contentType}</span>
								</div>
								<h3 class="title">{it.title || '(بدون عنوان)'}</h3>
								{#if it.matched && it.matched.length}
									<p class="matched">الكلمات المُطابِقة: <strong>{it.matched.join('، ')}</strong></p>
								{/if}
								<p class="cid">المعرّف: <code>{it.contentId}</code></p>
								{#if it.sourceUrl}
									<p class="src"><a href={it.sourceUrl} target="_blank" rel="noreferrer">عرض المصدر ↗</a></p>
								{/if}
								<div class="actions">
									<button class="del" onclick={() => del(it)} disabled={busyId === it.contentId}>
										{busyId === it.contentId ? '…' : 'حذف المحتوى'}
									</button>
								</div>
							</li>
						{/each}
					</ul>
				</section>
			{/each}
		{/if}
	{/if}
</div>

<style>
	.audit-page {
		max-width: 880px;
		margin: 0 auto;
		padding: 24px 16px;
	}
	.head {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}
	.head h1 {
		font-size: 1.5rem;
		font-weight: 700;
	}
	.refresh {
		border: 1px solid #d1d5db;
		border-radius: 8px;
		padding: 6px 14px;
		background: #fff;
		cursor: pointer;
	}
	.hint {
		color: #6b7280;
		margin: 6px 0 12px;
	}
	.summary {
		color: #374151;
		font-weight: 600;
		margin-bottom: 12px;
	}
	.group {
		margin-bottom: 28px;
	}
	.group-head {
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: 1.15rem;
		font-weight: 800;
		padding-bottom: 8px;
		margin-bottom: 14px;
		border-bottom: 2px solid;
	}
	.group-head .dot {
		width: 14px;
		height: 14px;
		border-radius: 50%;
		display: inline-block;
	}
	.group-head .count {
		margin-inline-start: auto;
		font-size: 0.85rem;
		background: #f3f4f6;
		color: #374151;
		border-radius: 999px;
		padding: 2px 10px;
	}
	.state {
		padding: 32px;
		text-align: center;
		color: #6b7280;
	}
	.state.err {
		color: #b91c1c;
	}
	.list {
		display: flex;
		flex-direction: column;
		gap: 12px;
		list-style: none;
		padding: 0;
		margin: 0;
	}
	.card {
		border: 1px solid #e5e7eb;
		border-radius: 14px;
		padding: 16px;
		background: #fff;
	}
	.flags {
		display: flex;
		gap: 8px;
		flex-wrap: wrap;
		align-items: center;
		margin-bottom: 8px;
	}
	.badge {
		font-size: 0.78rem;
		font-weight: 700;
		padding: 3px 10px;
		border-radius: 999px;
	}
	.type {
		font-size: 0.78rem;
		color: #6b7280;
		text-transform: uppercase;
		margin-inline-start: auto;
	}
	.title {
		font-size: 1.05rem;
		font-weight: 700;
		margin: 4px 0;
	}
	.cid,
	.src,
	.matched {
		font-size: 0.85rem;
		color: #4b5563;
		margin: 2px 0;
	}
	.matched strong {
		color: #b91c1c;
	}
	.actions {
		margin-top: 12px;
	}
	.del {
		background: #dc2626;
		color: #fff;
		border: none;
		border-radius: 8px;
		padding: 8px 18px;
		font-weight: 600;
		cursor: pointer;
	}
	.del:disabled {
		opacity: 0.6;
		cursor: default;
	}
</style>
