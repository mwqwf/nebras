/**
 * يحمّل متغيّرات dashboard/.env إلى process.env (بدون طباعة القيم).
 */
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const __dirname = path.dirname(url.fileURLToPath(import.meta.url));
const ENV_FILE = path.resolve(__dirname, '..', '.env');

/** @returns {boolean} */
export function loadDashboardEnv() {
	if (!fs.existsSync(ENV_FILE)) return false;
	for (const line of fs.readFileSync(ENV_FILE, 'utf8').split(/\r?\n/)) {
		const trimmed = line.trim();
		if (!trimmed || trimmed.startsWith('#')) continue;
		const m = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
		if (!m) continue;
		let val = m[2].trim();
		if (
			(val.startsWith('"') && val.endsWith('"')) ||
			(val.startsWith("'") && val.endsWith("'"))
		) {
			val = val.slice(1, -1);
		}
		if (!(m[1] in process.env)) process.env[m[1]] = val;
	}
	return true;
}

export function getEnvFilePath() {
	return ENV_FILE;
}
