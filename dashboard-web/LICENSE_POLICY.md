# Nebras — Content License & Compliance Policy

> **Audience**: Google Play store review · Rights-holder takedown requests · Internal compliance
> **Last updated**: 2026-05
> **App package**: `com.nebras.mobile`

---

## 0. Product positioning (please read first)

Nebras (نبراس) is a **general-knowledge** content platform — science, history,
literature, philosophy, language, the arts, and culture. It is **not** a
religious or sectarian app, and is not targeted at any single faith, school,
or political movement. Where religious or philosophical works appear, they
do so as part of the wider general-knowledge canon, never as the editorial
focus of the product.

The mobile app is a **native consumer**, not a web wrapper: PDF, audio, and
video are rendered by built-in, fully-licensed native players (Syncfusion
PDF, just_audio, video_player). It does not embed a generic browser view to
display third-party content.

---

## 1. Content sources

Nebras Mobile is **read-only**. All content is mediated through the Nebras
Dashboard, which writes to Cloud Firestore (metadata) and Firebase Storage
(binaries) under our own Firebase project (`nebras-9118c`). The mobile app
reads exclusively from those collections and plays files with its own
native players. It never reaches out to a third-party host at runtime.

| Channel | Who/what | License gate |
|---|---|---|
| **Exclusive owned content** | Uploaded manually by the owner/supervisors via the Dashboard | We own the rights or have explicit permission from the rights holder |
| **Manual upload (other)** | Authenticated moderators/supervisors upload PD/CC content via the Dashboard | Uploader confirms rights at upload time |
| **Automated ingestion — Internet Archive** | Server-side engine (`dashboard/src/lib/server/internetArchive/`) | Multi-layer license + bytestream + playability filter (see §2) |
| **Automated ingestion — Hindawi Foundation** | Server-side engine (`dashboard/src/lib/server/hindawi/`) | Hindawi publishes its catalogue under Creative Commons (CC BY-NC-ND for Arabic literature) — only items the engine identifies as CC are imported |

No client-side fetching of third-party content occurs. Legacy "bridge"
files for IslamHouse, Mshcat, and OldApp are **disabled stubs**. The Noor
Library automated engine exists in full but is **hard-disabled** — a
build-time kill switch (`NOOR_ENGINE_HARD_DISABLED` in
`noorLibrary/engine.js`) blocks every fetch path (cron, background loop,
manual start, and the manual import/preview endpoints), and the engine is
removed from the cron schedule (`.github/workflows/library-engines-cron.yml`).
It ingests **nothing** — automatically or manually — until re-enabled under
a strict PD/CC license gate.

---

## 2. Internet Archive ingestion pipeline

> **Delivery model (accuracy note):** Internet Archive items are served
> **metadata-only + reverse proxy** — Nebras does **not** download or
> re-host IA bytes to Firebase Storage. The mobile app receives an internal
> proxy URL (`/api/proxy/ia/{id}`) and the dashboard streams the file from
> archive.org on demand (see `internetArchive/metadataRegister.js`,
> `__delivery: "proxy_stream"`). The "download → verify-after-download →
> Storage upload" language in §2.4 below describes the **manual-upload and
> Hindawi** paths; for IA, byte verification is a ranged probe (first/last
> bytes), not a full download. Hindawi books **are** downloaded and
> re-hosted to Storage.

### 2.1 Pre-fetch query (Scrape API)

The Scrape query targets only items tagged as publicly uploaded to
curated collections, restricted by language and media type:

- `mediatype:(texts | audio | movies)`
- `collection:(<seed collections>)` — see `engine.js` `DEFAULT_SEEDS`
- `language:(Arabic | English | French)` — the languages the app
  ships UI for

### 2.2 Per-item license filter (server, before download)

File: `dashboard/src/lib/server/internetArchive/licenseFilter.js`

A **HARD GATE** rejects any item whose `license` / `licenseurl` / `rights`
field carries a copyright signal — independent of the item's collection:

```
COPYRIGHT_DENY_PATTERNS = [
  /all\s*rights?\s*reserved/i,
  /©\s*\d{4}/, /\(c\)\s*\d{4}/i,
  /copyright(ed)?\s*(?:©|\(c\)|\bby\b|\d{4})/i,
  /proprietary/i,
  /non\s*commercial/i,   // CC-BY-NC rejected
  /no\s*derivatives/i,   // CC-BY-ND rejected
  /-nc-/i, /-nd-/i, /-nc$/i, /-nd$/i,
  /^\s*cr\s*$/i          // IA shorthand for "copyrighted"
]
```

An item is **accepted** only if:

1. `licenseurl`, `license`, or `rights` explicitly matches an allowed
   Public Domain / Creative Commons pattern (`publicdomain`, `cc0`,
   `cc-by`, `cc-by-sa`) AND does not hit `COPYRIGHT_DENY_PATTERNS`; **or**
2. The item carries no license field at all AND is in one of the
   **curated public-domain collections** below. These are closed,
   curated lists — not community uploaders — so collection membership is
   itself a PD signal.

   ```
   PD_TRUSTED_COLLECTIONS = [
     'gutenberg',        // Project Gutenberg (PD texts)
     'librivoxaudio',    // LibriVox (PD audiobooks)
     'librivox',
     'prelinger'         // Prelinger Archives (PD films)
   ]
   ```

   Items accepted under this fallback are tagged
   `__license_status: "community_collection"` in Firestore for traceability.

Community-uploadable buckets that anyone can post to
(`booksbylanguage_arabic`, `folkscanomy*`, `audio_islamic`, `opensource*`,
…) were **removed** from the trusted list. Items in those buckets are
imported only when they carry a PD/CC license field of their own.

The `readConfig` step also performs an allowlist **intersection** — even
if a stored RTDB configuration tries to add a non-PD collection back to
`trustedCollections`, it is filtered out before reaching the license
filter. The PD-only gate is therefore enforceable from a single point in
the code (`engine.js` → `PD_TRUSTED_COLLECTIONS`).

### 2.3 Playability filter (server, before download)

File: `dashboard/src/lib/server/internetArchive/playabilityFilter.js`

Rejects items not playable on the mobile app's native players. Accepted
extensions/MIMEs: `.pdf`, `.mp3 / .m4a / .aac / .wav / .ogg / .opus /
.flac`, `.mp4`. Derivatives like `_bw.pdf`, `_text.pdf`, `_djvu.xml`,
`_jp2.zip` are explicitly blocked.

### 2.4 Bytestream verification (server, after download)

Magic bytes are verified to match the declared file type (e.g., `%PDF-`
for PDFs, `ID3` / `fLaC` / `OggS` for audio, `ftyp` for video). Size
limits enforced before storage (see `playabilityFilter.js`
`MAX_SIZE_BYTES`):

- Documents: **100 MB** max
- Audio: **150 MB** max
- Video: **200 MB** max

Firebase Storage rules cap any single upload at 200 MB regardless of the
client.

### 2.5 Compliance metadata stored per document

Every document the IA pipeline creates carries:

```jsonc
{
  "__provider": "internet_archive",
  "__iaIdentifier": "<archive.org id>",
  "__iaSourceUrl": "https://archive.org/details/<id>",
  "__license_status": "verified_open_license" | "community_collection",
  "__license_url": "<licenseurl from IA>",
  "__license_collection": "<collection name>",
  "__attribution_url": "https://archive.org/details/<id>",
  "__source_provider": "archive.org",
  "__compliance_version": "2026.05",
  "__verified_at": "<ISO timestamp>"
}
```

These fields are internal — the mobile app does not surface
`__iaIdentifier`/`__attribution_url` as tappable destinations (we never
link the user out to `archive.org`). The only metadata-derived value the
app renders is the human-readable license name and, when present, the
canonical CC/public-domain `license_url` (see §4.1.b).

---

## 3. Takedown / DMCA procedure

### 3.1 In-app report (primary channel — available to everyone)

Every content card in the mobile app has a **Report** button (no account
required — also available to guests). Reports land in the
`content_reports` Firestore collection with reason code and optional
note. When the reason is `copyright`, the app **also** writes to
`content_takedown_pending/{contentId}`, which is read by every client on
session start and hides the item from all users immediately — before
human review.

### 3.2 Server-side endpoint (rights holders, authenticated admin)

`POST /api/admin/internet-archive/dmca` (authenticated, admin role).

Body:

```json
{
  "fileId": "fb_<...>",
  "reason": "<DMCA case # / rights holder>",
  "reporter": "<email or org>"
}
```

Action:

1. Deletes the document from `content_unified_files` and `dashboard_uploads`.
2. Deletes the binary from Firebase Storage (PDF/MP3/MP4 + thumbnail).
3. Adds the IA identifier to `ia_library_dmca_blacklist` — preventing
   re-import indefinitely.
4. Writes an audit-log entry to `ia_library_engine/log` (reason, reporter,
   timestamp).

### 3.3 Public takedown contact

Rights holders who cannot use the in-app report can email the maintainer
directly at **cloudenarymarwano@gmail.com** — the same monitored address
published on the app's Google Play "Developer contact" page. The
maintainer will acknowledge within 72 hours and remove infringing content
within 24 hours of verification.

(No `dmca@…` domain alias is advertised, because no such mailbox exists; a
real, monitored personal address is published instead so takedown requests
are never lost.)

### 3.4 Re-import protection

The IA engine's `partitionKnownItems` (`registry.js`) reads
`ia_library_dmca_blacklist` on every tick and excludes any identifier
present. Takedowns are therefore permanent — even if the same item
appears in a future scrape.

---

## 4. Mobile app guards

### 4.1 Read-time filter

`search_datasource.dart` and `home_datasource.dart` apply
`_isPlayableAndCompliant` before returning content to the UI. An item is
filtered out if:

- `sourceUrl` is null, empty, or not `http(s)://`
- `license_status` / `__license_status` equals `rejected` (**live** — soft
  takedown without deleting the document)
- the current user reported it (`HiddenContentService`, local Hive box
  `hidden_content`; works for guests too)
- the item appears in `content_takedown_pending` (global hide after a
  copyright report by anyone — live, before human review)

### 4.1.b Attribution display (live)

The detail screens render a **curated** subset of compliance metadata
through the `ContentAttribution` widget: source name, license name, and a
tappable license URL when present.

- `source_name` / `__source_provider` / `__provider` → friendly source
  ("Internet Archive", "مؤسسة هنداوي", "مكتبة نور").
- `license_name` / `license` / `__license` → friendly license name.
- `license_url` / `__license_url` → opened in the external browser.

⚠️ The app never makes `__attribution_url` (`archive.org/details/<id>`)
tappable. Only the canonical CC/public-domain `license_url` is exposed.

### 4.1.c Report → review SLA (live)

When a user reports content the app shows a notice that the item will be
permanently removed within **24 hours** if the claim is verified, and
hides it from that user immediately regardless of outcome. Copyright
reports trigger the global hide described in §4.1.

### 4.2 Source-of-truth boundary

The mobile app never talks to `archive.org`, `hindawi.org`, or any other
third-party content host at runtime. It reads only from our Firebase
Storage bucket (`firebasestorage.googleapis.com/v0/b/nebras-9118c.firebasestorage.app/...`),
populated by the verified pipeline above. Native players consume the
files directly from Firebase Storage; no embedded browser view is used.

### 4.3 No user-uploaded content

The mobile app has **no upload capability**. End users can only consume
content moderated and ingested through the Dashboard.

---

## 5. Advertising policy

Nebras Mobile currently shows **no advertising of any kind** — no banner
ads, no interstitials, no rewarded video, no native ads, and no SDKs that
deliver advertising at runtime.

If advertising is introduced in a future release it will be served **only
against the Exclusive Owned Content channel** (§1, row 1) — content we
ourselves own or have licensed for monetisation. We will **not** serve ads
against, or alongside, items ingested from Internet Archive, Hindawi, or
any other third-party PD/CC source, in respect of those sources' authors
and licences.

---

## 6. Audit trail (for Google Play / takedown reviewers)

| What | Where | Retention |
|---|---|---|
| Successful imports | `ia_library_registry` (RTDB) | Indefinite |
| Failed imports + reason | `ia_library_failures` (RTDB) | Indefinite |
| Takedowns | `ia_library_dmca_blacklist` (RTDB) | Indefinite |
| In-app copyright reports (global) | `content_takedown_pending` (Firestore) | Until reviewer dismisses or deletes |
| In-app reports (per-content) | `content_reports` (Firestore) | Indefinite, owner-only read |
| Per-tick engine log (60 most recent) | `ia_library_engine/log` (RTDB) | Rolling |
| Document license metadata | `content_unified_files/{id}.__*` | Lifetime of document |
| Firebase Storage audit | Google Cloud Audit Logs | 400 days |

---

## 7. Code references

- **License filter**: `Nebras_dashboard-main/dashboard/src/lib/server/internetArchive/licenseFilter.js`
- **Playability filter**: `Nebras_dashboard-main/dashboard/src/lib/server/internetArchive/playabilityFilter.js`
- **Metadata registrar**: `Nebras_dashboard-main/dashboard/src/lib/server/internetArchive/metadataRegister.js`
- **Engine entrypoint**: `Nebras_dashboard-main/dashboard/src/lib/server/internetArchive/engine.js`
- **DMCA endpoint**: `Nebras_dashboard-main/dashboard/src/routes/api/admin/internet-archive/dmca/+server.js`
- **Orphan cleanup**: `Nebras_dashboard-main/dashboard/src/routes/api/admin/internet-archive/cleanup-orphans/+server.js`
- **Cron entrypoints**: `Nebras_dashboard-main/dashboard/src/routes/api/cron/{internet-archive,noor-library,hindawi-library}-tick/+server.js` (secure-by-configuration: strict `Bearer $CRON_SECRET` enforcement when the secret is set; allowed otherwise so first-run ingestion is not blocked)
- **Mobile read-time guard**: `archive_mobileapp-master/lib/features/{search,home}/data/*_datasource.dart`
- **Mobile reporting + global hide**: `archive_mobileapp-master/lib/features/content/`

---

## 8. Version history

| Date | Change |
|---|---|
| 2026-05 | Initial policy (multi-layer copyright guard; DMCA endpoint live; mobile read-time filter live). |
| 2026-05 | Acceptance hardening: trusted-collections allowlist tightened to **PD-only** (`gutenberg / librivoxaudio / librivox / prelinger`); community-uploadable buckets removed and intersection-filtered in `readConfig` so RTDB cannot re-add them. Cron endpoints hardened to **secure-by-configuration** on `CRON_SECRET` (strict when the secret is set; allowed otherwise so production ingestion is never silently blocked). Storage rules' hardcoded-email fallback removed (custom-claim `role` is now the only path). Advertising policy committed (none today; future ads on exclusive owned content only). Product positioning clarified as **general knowledge** (not religious). Fake `dmca@nebras.app` alias removed; public takedown contact replaced with a real, monitored address. |
