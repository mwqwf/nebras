<!--
  Login Page — يُطابق شاشة الترحيب + شاشة تسجيل الدخول في تطبيق نبراس،
  مع إضافة مرحلة "رمز المالك" عند إنشاء حساب جديد فقط.

  تدفّق الشاشات:
   1) welcome  : شعار + تحيّة + زرّان (إنشاء حساب / تسجيل دخول).
   2) signin   : زر Google Sign-In + عنوان مختلف حسب المصدر.
   3) owner_code : يظهر بعد دخول Google بنجاح لمستخدم جديد.

  ملاحظة هامّة: لا نعرض بريد المالك أبداً — النصّ يذكر فقط أنّ الرمز
  أُرسِل إلى المالك.
-->

<script>
	import { onDestroy, onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { getAuthState, takeRedirectSignInError } from '$lib/stores/auth.svelte.js';
	import {
		signInWithGoogle,
		requestOwnerCode,
		verifyOwnerCode,
		logout,
		checkCurrentAuth,
		authErrorTranslationKey
	} from '$lib/api/auth.js';
	import { getLanguage, toggleLanguage, t, getDir } from '$lib/i18n/store.svelte.js';

	const authState = getAuthState();

	// رسالة تعليق الوصول (عند قدوم المستخدم بعد طرده من الجدار).
	let blockedNotice = $state('');
	onMount(() => {
		const params = page.url?.searchParams;
		if (params?.get('blocked') === '1') {
			blockedNotice = 'تم تعليق وصولك من قبل الإدارة';
		}
		const redirErr = takeRedirectSignInError();
		if (redirErr) {
			errorKey = authErrorTranslationKey(redirErr);
		}
		// اكتمال signInWithRedirect يُنفَّذ في +layout.svelte قبل startAuthListener
		// حتى لا يُحجب بشاشة التحميل ولا يُستهلك redirect متأخراً.
	});

	/** @type {'welcome'|'signin'|'owner_code'} */
	let step = $state('welcome');
	/** @type {'signin'|'signup'} */
	let signInMode = $state('signin');

	let busy = $state(false);
	let errorKey = $state('');
	let infoKey = $state('');
	let deliveredHint = $state('');

	let code = $state('');
	let resendCooldown = $state(0);
	let cooldownTimer = null;

	let dir = $derived(getDir());
	let lang = $derived(getLanguage());

	// لو كان المستخدم مصرّحاً له بالفعل → ادفعه مباشرةً للوحة التحكّم.
	// ولو سُجِّل دخوله بـ Google لكن لم يُوافَق بعد → اذهب لمرحلة الرمز.
	$effect(() => {
		if (authState.isLoading) return;
		if (authState.authorized) {
			goto('/moderator/content/files');
			return;
		}
		if (authState.user && authState.needsOwnerCode && step !== 'owner_code') {
			step = 'owner_code';
		}
	});

	onDestroy(() => {
		if (cooldownTimer) clearInterval(cooldownTimer);
	});

	function startCooldown(seconds) {
		resendCooldown = Math.max(0, Math.floor(seconds));
		if (cooldownTimer) clearInterval(cooldownTimer);
		cooldownTimer = setInterval(() => {
			resendCooldown -= 1;
			if (resendCooldown <= 0) {
				clearInterval(cooldownTimer);
				cooldownTimer = null;
			}
		}, 1000);
	}

	function goToSignIn(mode) {
		signInMode = mode;
		step = 'signin';
		errorKey = '';
		infoKey = '';
	}

	async function handleGoogle() {
		if (busy) return;
		busy = true;
		errorKey = '';
		infoKey = '';
		try {
			const result = await signInWithGoogle();
			if (!result.ok) {
				if (result.error === 'cancelled') {
					// إلغاء طبيعي من المستخدم — لا نُظهر خطأ صاخبًا.
					return;
				}
				// نستعمل المفتاح الدقيق المُستخرَج من رمز خطأ Firebase (مثل
				// `auth/unauthorized-domain`) كي يُرى السبب الحقيقيّ في الواجهة.
				errorKey = authErrorTranslationKey(result.error);
				return;
			}
			if (result.pendingRedirect) {
				// تحويل خارجيّ — لا نعرض خطأ ولا نتابع.
				return;
			}
			if (result.authorized) {
				await goto('/moderator/content/files');
				return;
			}
			if (result.needsOwnerCode) {
				if (signInMode === 'signin') {
					// المستخدم اختار "تسجيل دخول" لكن حسابه غير معروف → أخبره
					// بوضوح أنّ عليه إنشاء حساب (يتطلّب رمز المالك).
					infoKey = 'auth.hint.account_not_found';
				}
				step = 'owner_code';
				// نطلب الرمز تلقائيًا عند الوصول لشاشة الرمز (أوّل مرة فقط).
				// هنا تكون handleGoogle قد رفعت busy=true بالفعل، لذا نتجاوز
				// الحارس حتى لا يُلغى الطلب صامتاً ولا يصل أي بريد إلى المالك.
				await sendFreshCode({ silent: true, force: true });
				return;
			}
			// حالة غير متوقّعة — لا authorized ولا needsOwnerCode.
			errorKey = 'auth.error.unexpected';
		} catch (err) {
			console.error('[login] Google sign-in failed:', err);
			errorKey = 'auth.error.google_failed';
		} finally {
			busy = false;
		}
	}

	async function sendFreshCode({ silent = false, force = false } = {}) {
		if (busy && !force) return;
		busy = true;
		errorKey = '';
		if (!silent) infoKey = '';
		deliveredHint = '';
		try {
			const res = await requestOwnerCode();
			if (!res.ok) {
				if (res.reason === 'rate_limited') {
					startCooldown(res.retryAfterSec || 60);
					if (!silent) errorKey = 'auth.error.rate_limited';
				} else if (res.reason === 'already_authorized') {
					// المستخدم أصبح مصرّحاً بينما كنّا نفكّر — أعد التحقّق.
					await checkCurrentAuth();
				} else {
					if (!silent) {
						errorKey = 'auth.error.send_failed';
					}
				}
				return;
			}
			startCooldown(60);
			if (res.delivered) {
				deliveredHint = 'auth.code.sent';
			} else {
				// لم يُرسَل بالبريد (SMTP غير مضبوط). لا نفضح التفاصيل للمستخدم،
				// نعرض نفس رسالة الإرسال لأنّ الرمز سيكون في console الخادم للتطوير.
				deliveredHint = 'auth.code.sent_fallback';
			}
		} catch (err) {
			console.error('[login] requestOwnerCode failed:', err);
			errorKey = 'auth.error.send_failed';
		} finally {
			busy = false;
		}
	}

	async function handleVerify() {
		if (busy) return;
		const trimmed = (code || '').trim();
		if (!/^\d{6}$/.test(trimmed)) {
			errorKey = 'auth.error.invalid_code_format';
			return;
		}
		busy = true;
		errorKey = '';
		try {
			const res = await verifyOwnerCode(trimmed);
			if (res.ok) {
				await goto('/moderator/content/files');
				return;
			}
			switch (res.reason) {
				case 'expired':
					errorKey = 'auth.error.code_expired';
					break;
				case 'too_many_attempts':
					errorKey = 'auth.error.too_many_attempts';
					code = '';
					break;
				case 'no_code':
					errorKey = 'auth.error.no_code';
					break;
				case 'invalid':
				default:
					errorKey = 'auth.error.invalid_code';
					break;
			}
		} catch (err) {
			console.error('[login] verifyOwnerCode failed:', err);
			errorKey = 'auth.error.server';
		} finally {
			busy = false;
		}
	}

	async function handleCancel() {
		code = '';
		errorKey = '';
		infoKey = '';
		deliveredHint = '';
		step = 'welcome';
		await logout();
	}

	function onCodeInput(e) {
		const cleaned = e.target.value.replace(/[^\d]/g, '').slice(0, 6);
		code = cleaned;
		e.target.value = cleaned;
	}
</script>

<svelte:head>
	<title>Nebras — {t('auth.login_title')}</title>
</svelte:head>

<div class="login-shell" {dir}>
	<!-- Language toggle (top-end) -->
	<button type="button" class="lang-pill" onclick={toggleLanguage}>
		{lang === 'ar' ? 'EN' : 'عربي'}
	</button>

	<div class="card">
		{#if blockedNotice}
			<div class="blocked-banner" role="alert">
				<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
					<circle cx="12" cy="12" r="10" />
					<line x1="15" y1="9" x2="9" y2="15" />
					<line x1="9" y1="9" x2="15" y2="15" />
				</svg>
				<span>{blockedNotice}</span>
			</div>
		{/if}
		{#if step === 'welcome'}
			<div class="logo-wrap">
				<div class="logo">
					<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4"
						stroke-linecap="round" stroke-linejoin="round">
						<path d="M12 3L2 12h3v8h6v-6h2v6h6v-8h3L12 3z" />
					</svg>
				</div>
			</div>

			<h1 class="greeting">{t('auth.greeting')}</h1>
			<h2 class="title">{t('auth.welcome_title')}</h2>
			<p class="subtitle">{t('auth.welcome_subtitle')}</p>

			<div class="actions">
				<button type="button" class="btn btn-primary" onclick={() => goToSignIn('signup')}>
					<svg class="btn-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
						stroke-linecap="round" stroke-linejoin="round">
						<path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
						<circle cx="8.5" cy="7" r="4" />
						<line x1="20" y1="8" x2="20" y2="14" />
						<line x1="23" y1="11" x2="17" y2="11" />
					</svg>
					<span>{t('auth.create_account')}</span>
				</button>
				<button type="button" class="btn btn-secondary" onclick={() => goToSignIn('signin')}>
					<svg class="btn-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
						stroke-linecap="round" stroke-linejoin="round">
						<path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4" />
						<polyline points="10 17 15 12 10 7" />
						<line x1="15" y1="12" x2="3" y2="12" />
					</svg>
					<span>{t('auth.sign_in')}</span>
				</button>
			</div>

			<p class="footer-note">{t('auth.google_hint')}</p>

		{:else if step === 'signin'}
			<button type="button" class="back-btn" onclick={() => { step = 'welcome'; errorKey = ''; infoKey = ''; }}>
				<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
					stroke-linecap="round" stroke-linejoin="round">
					<polyline points="15 18 9 12 15 6" />
				</svg>
				{t('common.back')}
			</button>

			<h2 class="title title-left">
				{signInMode === 'signup' ? t('auth.signup_title') : t('auth.signin_title')}
			</h2>
			<p class="subtitle subtitle-left">
				{signInMode === 'signup' ? t('auth.signup_subtitle') : t('auth.signin_subtitle')}
			</p>

			<button
				type="button"
				class="btn btn-google"
				onclick={handleGoogle}
				disabled={busy}
			>
				{#if busy}
					<span class="spinner"></span>
				{:else}
					<span class="google-logo" aria-hidden="true">
						<svg viewBox="0 0 48 48" width="20" height="20">
							<path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3c-1.6 4.7-6 8-11.3 8-6.6 0-12-5.4-12-12s5.4-12 12-12c3 0 5.8 1.1 7.9 3l5.7-5.7C34.1 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.2-.1-2.4-.4-3.5z"/>
							<path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.6 16 19 13 24 13c3 0 5.8 1.1 7.9 3l5.7-5.7C34.1 6.1 29.3 4 24 4c-7.7 0-14.3 4.4-17.7 10.7z"/>
							<path fill="#4CAF50" d="M24 44c5.2 0 10-2 13.6-5.2l-6.3-5.3C29.2 35.1 26.7 36 24 36c-5.3 0-9.7-3.3-11.3-8l-6.5 5C9.7 39.6 16.3 44 24 44z"/>
							<path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.7 2.2-2.1 4-3.9 5.3l6.3 5.3C37.4 36.3 44 31 44 24c0-1.2-.1-2.4-.4-3.5z"/>
						</svg>
					</span>
					<span>
						{signInMode === 'signup' ? t('auth.google_signup') : t('auth.google_signin')}
					</span>
				{/if}
			</button>

			{#if errorKey}
				<div class="alert alert-error">{t(errorKey)}</div>
			{/if}

			<p class="privacy-note">{t('auth.privacy_note')}</p>

		{:else if step === 'owner_code'}
			<h2 class="title title-left">{t('auth.owner_code_title')}</h2>
			<p class="subtitle subtitle-left">{t('auth.owner_code_subtitle')}</p>

			{#if infoKey}
				<div class="alert alert-info">{t(infoKey)}</div>
			{/if}
			{#if deliveredHint}
				<div class="alert alert-success">{t(deliveredHint)}</div>
			{/if}

			<label class="code-label" for="owner-code-input">{t('auth.owner_code_label')}</label>
			<input
				id="owner-code-input"
				class="code-input"
				type="text"
				inputmode="numeric"
				autocomplete="one-time-code"
				maxlength="6"
				placeholder="••••••"
				value={code}
				oninput={onCodeInput}
				disabled={busy}
			/>

			{#if errorKey}
				<div class="alert alert-error">{t(errorKey)}</div>
			{/if}

			<div class="row-buttons">
				<button
					type="button"
					class="btn btn-primary"
					onclick={handleVerify}
					disabled={busy || code.length !== 6}
				>
					{#if busy}
						<span class="spinner"></span>
					{:else}
						<span>{t('auth.verify')}</span>
					{/if}
				</button>

				<button
					type="button"
					class="btn btn-ghost"
					onclick={() => sendFreshCode()}
					disabled={busy || resendCooldown > 0}
				>
					{#if resendCooldown > 0}
						{t('auth.resend_in')} {resendCooldown}s
					{:else}
						{t('auth.resend')}
					{/if}
				</button>
			</div>

			<button type="button" class="cancel-link" onclick={handleCancel} disabled={busy}>
				{t('auth.cancel_and_signout')}
			</button>
		{/if}
	</div>
</div>

<style>
	.login-shell {
		position: relative;
		min-height: 100vh;
		background:
			radial-gradient(1000px 600px at 20% -10%, rgba(5, 150, 105, 0.18), transparent 60%),
			radial-gradient(800px 500px at 110% 110%, rgba(4, 120, 87, 0.18), transparent 60%),
			var(--color-surface-950, #0b1020);
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 24px 16px;
	}

	.lang-pill {
		position: absolute;
		top: 18px;
		inset-inline-end: 18px;
		height: 36px;
		min-width: 56px;
		padding: 0 12px;
		border-radius: 999px;
		border: 1px solid var(--color-surface-700, #1f2937);
		background: rgba(17, 24, 39, 0.7);
		color: var(--color-surface-200, #e5e7eb);
		font-weight: 700;
		font-size: 12px;
		cursor: pointer;
		backdrop-filter: blur(6px);
	}
	.lang-pill:hover {
		background: rgba(31, 41, 55, 0.9);
	}

	.card {
		width: 100%;
		max-width: 440px;
		background: rgba(17, 24, 39, 0.75);
		border: 1px solid var(--color-surface-700, #1f2937);
		border-radius: 18px;
		padding: 28px 28px 24px;
		box-shadow: 0 30px 80px rgba(0, 0, 0, 0.45);
		backdrop-filter: blur(10px);
		color: var(--color-surface-100, #f3f4f6);
	}

	.blocked-banner {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.75rem 1rem;
		margin-bottom: 1rem;
		border-radius: 10px;
		background: rgba(244, 63, 94, 0.1);
		border: 1px solid rgba(244, 63, 94, 0.28);
		color: #fecaca;
		font-size: 0.8125rem;
		font-weight: 500;
	}
	.blocked-banner svg {
		width: 18px;
		height: 18px;
		flex-shrink: 0;
	}

	.logo-wrap {
		display: flex;
		justify-content: center;
		margin-bottom: 16px;
	}
	.logo {
		width: 96px;
		height: 96px;
		border-radius: 50%;
		background: linear-gradient(135deg, rgba(5, 150, 105, 0.22), rgba(4, 120, 87, 0.18));
		display: flex;
		align-items: center;
		justify-content: center;
		color: #34d399;
		box-shadow: 0 10px 30px rgba(5, 150, 105, 0.3);
	}
	.logo svg {
		width: 44px;
		height: 44px;
	}

	.greeting {
		text-align: center;
		color: #34d399;
		font-size: 17px;
		line-height: 1.7;
		margin: 0 0 10px;
		font-weight: 700;
	}
	.title {
		text-align: center;
		font-size: 22px;
		margin: 0 0 8px;
		font-weight: 800;
		color: var(--color-surface-100, #f3f4f6);
	}
	.title-left {
		text-align: start;
	}
	.subtitle {
		text-align: center;
		color: var(--color-surface-400, #9ca3af);
		line-height: 1.7;
		margin: 0 0 22px;
		font-size: 14px;
	}
	.subtitle-left {
		text-align: start;
	}

	.actions {
		display: flex;
		flex-direction: column;
		gap: 10px;
		margin-top: 12px;
	}

	.btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 10px;
		height: 48px;
		padding: 0 16px;
		border-radius: 12px;
		border: 1px solid transparent;
		font-weight: 700;
		font-size: 14px;
		cursor: pointer;
		transition: transform 0.08s ease, background 0.15s ease, border-color 0.15s ease;
	}
	.btn:active { transform: translateY(1px); }
	.btn:disabled { opacity: 0.6; cursor: not-allowed; }

	.btn-primary {
		background: linear-gradient(135deg, #059669, #047857);
		color: #fff;
		box-shadow: 0 8px 22px rgba(5, 150, 105, 0.35);
	}
	.btn-primary:hover:not(:disabled) {
		background: linear-gradient(135deg, #10b981, #059669);
	}

	.btn-secondary {
		background: transparent;
		color: #34d399;
		border-color: rgba(52, 211, 153, 0.45);
	}
	.btn-secondary:hover:not(:disabled) {
		background: rgba(52, 211, 153, 0.08);
	}

	.btn-ghost {
		background: transparent;
		color: var(--color-surface-300, #d1d5db);
		border-color: var(--color-surface-700, #1f2937);
	}
	.btn-ghost:hover:not(:disabled) {
		background: rgba(255, 255, 255, 0.04);
	}

	.btn-google {
		background: #fff;
		color: #1f2937;
		border: 1px solid #e5e7eb;
		box-shadow: 0 1px 2px rgba(0,0,0,0.06);
		margin-top: 6px;
	}
	.btn-google:hover:not(:disabled) {
		background: #f9fafb;
	}

	.btn-icon {
		width: 18px;
		height: 18px;
	}

	.google-logo {
		display: inline-flex;
		align-items: center;
	}

	.spinner {
		width: 18px;
		height: 18px;
		border: 2px solid rgba(255,255,255,0.35);
		border-top-color: #fff;
		border-radius: 50%;
		animation: spin 0.7s linear infinite;
	}
	.btn-google .spinner {
		border-color: rgba(31,41,55,0.25);
		border-top-color: #1f2937;
	}
	@keyframes spin { to { transform: rotate(360deg); } }

	.footer-note {
		text-align: center;
		margin: 18px 0 0;
		color: var(--color-surface-500, #6b7280);
		font-size: 12.5px;
	}

	.back-btn {
		background: none;
		border: none;
		color: var(--color-surface-400, #9ca3af);
		display: inline-flex;
		align-items: center;
		gap: 6px;
		cursor: pointer;
		font-size: 13px;
		padding: 4px 0;
		margin-bottom: 10px;
	}
	.back-btn svg { width: 16px; height: 16px; }
	.back-btn:hover { color: #fff; }

	.privacy-note {
		text-align: center;
		color: var(--color-surface-500, #6b7280);
		font-size: 12px;
		margin-top: 18px;
		line-height: 1.7;
	}

	.alert {
		padding: 10px 12px;
		border-radius: 10px;
		font-size: 13px;
		margin: 10px 0 2px;
		line-height: 1.7;
	}
	.alert-error {
		background: rgba(220, 38, 38, 0.12);
		border: 1px solid rgba(220, 38, 38, 0.4);
		color: #fecaca;
	}
	.alert-info {
		background: rgba(59, 130, 246, 0.12);
		border: 1px solid rgba(59, 130, 246, 0.4);
		color: #bfdbfe;
	}
	.alert-success {
		background: rgba(16, 185, 129, 0.12);
		border: 1px solid rgba(16, 185, 129, 0.4);
		color: #a7f3d0;
	}

	.code-label {
		display: block;
		margin: 14px 0 8px;
		font-size: 13px;
		color: var(--color-surface-300, #d1d5db);
	}
	.code-input {
		width: 100%;
		height: 58px;
		background: rgba(17, 24, 39, 0.6);
		border: 1px solid var(--color-surface-700, #1f2937);
		border-radius: 12px;
		color: #fff;
		text-align: center;
		font-size: 28px;
		letter-spacing: 12px;
		font-weight: 700;
		outline: none;
		transition: border-color 0.15s ease, box-shadow 0.15s ease;
	}
	.code-input:focus {
		border-color: #10b981;
		box-shadow: 0 0 0 3px rgba(16, 185, 129, 0.18);
	}

	.row-buttons {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 10px;
		margin-top: 14px;
	}

	.cancel-link {
		display: block;
		width: 100%;
		margin-top: 14px;
		background: none;
		border: none;
		color: var(--color-surface-500, #6b7280);
		cursor: pointer;
		font-size: 13px;
		text-align: center;
	}
	.cancel-link:hover { color: #fca5a5; }

	@media (max-width: 480px) {
		.card { padding: 22px 18px; }
		.title { font-size: 20px; }
		.code-input { font-size: 24px; letter-spacing: 8px; }
	}
</style>
