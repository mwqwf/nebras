import { sveltekit } from '@sveltejs/kit/vite';
import tailwindcss from '@tailwindcss/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [tailwindcss(), sveltekit()],
	// حزم Puppeteer ثقيلة وتجرّ تبعاتًا اختياريّة (supports-color، bufferutil، …) — إبقاؤها خارج حزمة SSR
	// يقلّل تحذيرات Vite ويُسرّع البناء دون لمس سلوك التشغيل في Node.
	ssr: {
		external: [
			'puppeteer',
			'puppeteer-core',
			'@puppeteer/browsers',
			'puppeteer-extra',
			'puppeteer-extra-plugin-stealth',
			'puppeteer-extra-plugin',
			'puppeteer-extra-plugin-user-preferences',
			'puppeteer-extra-plugin-user-data-dir'
		]
	},
	server: {
		// يسمح بفتح التطبيق من الهاتف على نفس شبكة Wi‑Fi عبر عنوان الـ LAN
		host: true
	}
});
