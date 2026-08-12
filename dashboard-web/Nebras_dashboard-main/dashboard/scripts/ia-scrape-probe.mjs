/**
 * node scripts/ia-scrape-probe.mjs
 */
import { buildLuceneQuery, scrapeOnePage } from '../src/lib/server/internetArchive/search.js';
import { filterScrapeItemsByLicense } from '../src/lib/server/internetArchive/licenseFilter.js';

const SEED = {
	q: '(islam OR إسلام OR قرآن OR حديث OR فقه OR تفسير OR سيرة)',
	languages: ['Arabic', 'ara'],
	nebrasTypes: ['document'],
	collections: ['opensource_arabic', 'community_texts', 'arabicliterature']
};

const query = buildLuceneQuery(SEED);
const page = await scrapeOnePage({ query, count: 100 });
const ok = filterScrapeItemsByLicense(page.items, {
	allowMissingLicenseInTrustedCollections: true,
	trustedCollections: [
		'opensource_arabic',
		'community_texts',
		'arabicliterature',
		'islamicbooks_archive',
		'shamela'
	]
});
console.log('query:', query);
console.log('total', page.items.length, 'licenseOk', ok.length);
for (const row of ok.slice(0, 5)) {
	console.log(`- ${row.identifier} | ${String(row.title || '').slice(0, 50)} | ${row.licenseurl || '(trusted)'}`);
}
