/** حساب SHA-256 خارج الخيط الرئيسي لتجنّب تجميد الواجهة. */
self.onmessage = async (event) => {
	try {
		const { buffer } = event.data;
		const hash = await crypto.subtle.digest('SHA-256', buffer);
		const hex = Array.from(new Uint8Array(hash))
			.map((b) => b.toString(16).padStart(2, '0'))
			.join('');
		self.postMessage({ ok: true, hash: hex });
	} catch (err) {
		self.postMessage({ ok: false, error: String(err?.message || err) });
	}
};
