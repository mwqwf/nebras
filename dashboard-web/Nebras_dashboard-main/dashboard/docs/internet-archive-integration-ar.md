# تكامل Internet Archive في نِبراس — التوثيق الكامل

> هذا التوثيق يصف **محرّك Internet Archive** الذي أضيف إلى لوحة التحكّم.
> الهدف: إثراء كتالوج نبراس بمحتوى مرخّص من `archive.org` **دون أيّ
> اتصال مباشر بين تطبيق Flutter وأرشيف الإنترنت**، وبدون أيّ مؤشّر ظاهر
> للمستخدم النهائي على مصدر المحتوى.

---

## 1. المبدأ الذهبي

| القاعدة | السبب |
|---------|------|
| لا اتصال مباشر بين Flutter و `archive.org` | حماية تجربة المستخدم + متطلّبات Google Play Data Safety. التطبيق نفسه (`content_model.dart` → `_rejectArchiveOrg`) يرفض أيّ رابط يحوي `archive.org`. |
| كلّ شيء يمرّ عبر لوحة التحكّم → Firestore (metadata-only) → بثّ عبر Proxy | كتالوج التطبيق يحوي روابط نبراس فقط (`{NEBRAS_PUBLIC_BASE_URL}/api/proxy/ia/…`). لم يعد يُنزَّل الملفّ ولا يُرفع إلى Firebase Storage. |
| لا يدخل التطبيق إلا محتوى **مرخّص + قابل للتشغيل + مُتحقَّق من سلامته** | لا تظهر عناصر مكسورة أو محظورة قانونياً. |
| كلّ بذرة (تصنيف) تجلب نتائجها **كاملةً** قبل التحوّل للتاليّة | منع جلب جزئي. |
| لا أزرار "Internet Archive" في التطبيق | "trust by default" — المستخدم يرى محتوى نبراس فحسب. |

---

## 2. هيكلة الملفات

### 2.1 الخادم (SvelteKit)

```
dashboard/src/lib/server/internetArchive/
├── playabilityFilter.js   # حارس الصيغ + magic bytes + حدود الحجم + verifyHeadBytes / pdfTailIsEncrypted
├── licenseFilter.js       # PD / CC0 / CC-BY / CC-BY-SA + trusted collections
├── search.js              # IA Scraping API + Lucene builder + URL helpers
├── fetcher.js             # metadata + اختيار أفضل ملف + كائن preview
├── metadataProbe.js       # ★ فحص قابليّة التشغيل بـ HTTP Range (512 بايت) — بلا تنزيل (بديل downloader.js)
├── metadataRegister.js    # ★ كتابة مرآة Firestore بروابط proxy — بلا Storage (بديل adminUploader.js)
├── classifier.js          # تصنيف عربي محلّيّ (heuristic) + قرار إنشاء أقسام
├── sectionsCreator.js     # إنشاء main/sub/secondary فعلياً في sections_unified
├── sectionsTree.js        # بناء شجرة الأقسام + فهارسها
├── registry.js            # ia_library_registry / ia_library_failures
└── engine.js              # tick + start/stop + factoryReset
```

> ملاحظة: `publicBaseUrl.js` يقع في `dashboard/src/lib/server/` (مستوى أعلى)
> ويُستعمل لبناء روابط الـ proxy المطلقة من `NEBRAS_PUBLIC_BASE_URL`.
> الملفّان القديمان `downloader.js` و`adminUploader.js` **حُذفا** بعد التحوّل
> إلى معماريّة Metadata-only + Proxy.

### 2.2 نقاط API

```
dashboard/src/routes/api/admin/internet-archive/
├── sections/+server.js              # GET — شجرة الأقسام للتصنيف
├── search/+server.js                # POST — صفحة بحث Scraping API
├── preview/+server.js               # POST — معاينة عنصر (لا كتابة)
├── import/+server.js                # POST — استيراد يدوي
└── engine/
    ├── status/+server.js            # GET — config + cursor + stats + log
    ├── start/+server.js             # POST owner-only
    ├── stop/+server.js              # POST owner-only
    ├── tick/+server.js              # POST — دورة واحدة
    ├── seeds/+server.js             # PUT  — تحديث البذور
    └── reset/+server.js             # POST — cursor | factory
```

ومسار Cron الخارجي:

```
dashboard/src/routes/api/cron/internet-archive-tick/+server.js
```

ومسار الـ Proxy العامّ (الجسر الفعليّ بين التطبيق و archive.org):

```
dashboard/src/routes/api/proxy/ia/[id]/+server.js   # GET|HEAD — بثّ server-to-server مع تمرير Range + حارس SSRF
```

### 2.3 الواجهة

```
dashboard/src/routes/admin/internet-archive/+page.svelte
dashboard/src/lib/api/internetArchive.js
```

---

## 3. مسار البيانات

### 3.1 الاستيعاب (Ingest) — وقت الاستيراد، بلا تنزيل

```
┌──────────────────────────────────────────────────────────────────────┐
│ Internet Archive                                                     │
│   archive.org/services/search/v1/scrape   ← search.js                │
│   archive.org/metadata/{id}               ← search.js / fetcher.js   │
│   archive.org/download/{id}/{file}        ← metadataProbe.js (Range) │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Internet Archive Engine (server)                                     │
│   1) license filter          (licenseFilter.js)                      │
│   2) playability filter      (playabilityFilter.js)                  │
│   3) probe — أوّل 512 بايت عبر HTTP Range + magic bytes + ذيل PDF     │
│      (metadataProbe.js) — لا تنزيل كامل، الحجم من Content-Range       │
│   4) classify — تصنيف عربي محلّيّ + إنشاء أقسام عند الحاجة            │
│      (classifier.js + sectionsCreator.js)                            │
│   5) register metadata — مرآة Firestore بروابط proxy، بلا Storage     │
│      (metadataRegister.js → adminFsWriteFileMirrorBoth)              │
│   6) registry record         (registry.js)                           │
│   7) FCM notify              (engine.js)                             │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Firebase  (بلا Storage)                                              │
│   Firestore: dashboard_uploads/{fileId}                              │
│             content_unified_files/{fileId}                           │
│             — الروابط العامّة تشير إلى /api/proxy/ia/{fileId}         │
│             — __iaFileUrl/__iaThumbUrl تحفظ رابط archive.org الحقيقي │
│             — __delivery: 'proxy_stream'                              │
│   RTDB:      ia_library_engine/{config,cursor,stats,log}             │
│             ia_library_registry/{identifier}                         │
│             ia_library_failures/{identifier}                         │
└──────────────────────────────────────────────────────────────────────┘
```

### 3.2 التشغيل (Playback) — وقت الطلب، بثّ عبر Proxy

```
┌──────────────────────────────────────────────────────────────────────┐
│ Flutter App                                                          │
│   يقرأ Firestore كالعادة عبر HomeDatasource/SearchDatasource         │
│   ContentModel.fromJson لا يعرف بـ __provider/__iaIdentifier         │
│   يرى رابطاً نبراسيّاً فقط (لا "archive.org" → يمرّ _rejectArchiveOrg) │
└──────────────────────────────────────────────────────────────────────┘
                              │  GET {base}/api/proxy/ia/{fileId}.{ext}
                              │  (Range header للصوت/الفيديو/seek الـ PDF)
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Proxy route (server)  routes/api/proxy/ia/[id]/+server.js            │
│   1) يجرّد الامتداد ويقرأ الوثيقة من content_unified_files (Admin)    │
│   2) يتحقّق __provider==='internet_archive' وأنّ المضيف *.archive.org │
│      (حارس SSRF)                                                     │
│   3) fetch من archive.org server-to-server مع تمرير رأس Range        │
│   4) يمرّر الـ stream مباشرةً (لا buffer كامل، لا تخزين)              │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              archive.org/download/{id}/{file}  (__iaFileUrl)
```

---

## 4. الصيغ المسموحة (متوافقة مع التطبيق)

تستند القائمة إلى ما يستطيع التطبيق فعلاً تشغيله، لا إلى ما يقبله IA:

| النوع في نبراس | المشغّل في التطبيق | الصيغ المقبولة | الحجم الأقصى |
|---|---|---|---|
| `document` | Syncfusion `SfPdfViewer` | `.pdf` فقط | 100 ميغابايت |
| `audio` | `just_audio` | `.mp3`, `.m4a`, `.aac`, `.wav`, `.ogg`, `.opus`, `.flac` | 150 ميغابايت |
| `video` | `video_player` الرسمي | `.mp4` فقط (H.264 + AAC) | 200 ميغابايت |

> الحدود مطابقة لـ `MAX_SIZE_BYTES` في `playabilityFilter.js`. أيّ ملفّ
> أكبر من حدّه يُرفض في مرحلة الـ probe (من `Content-Range`) قبل أن تُكتب
> له وثيقة.

أيّ صيغة خارج هذه القوائم — حتى لو وردتْ في `content_model.dart` كقائمة
موسّعة — يرفضها `playabilityFilter.js` قبل أن تُكتب وثيقته. كذلك يُرفض كلّ
derivative معروف لا يصلح للعرض: `_bw.pdf`, `_text.pdf`, `_djvu.*`,
`_jp2.zip`, `_meta.xml`, `.torrent`, …

### تحقّق Magic Bytes (بلا تنزيل)

`metadataProbe.js` يطلب **أوّل 512 بايت فقط** عبر HTTP Range ثم يتحقّق منها
بـ `verifyHeadBytes` (في `playabilityFilter.js`):

- **PDF**: يبدأ بـ `%PDF-`.
- **Audio**: ID3 / `fLaC` / `OggS` / `RIFF` / `ftyp` (m4a) / إطار MPEG.
- **Video**: 4 بايت ثم `ftyp`.

ملف لا يطابق magic bytes يُرفض ولا تُكتب له وثيقة Firestore.

إضافةً لذلك، **للـ PDF فقط** يجلب المحرّك ذيل الملفّ (~8KB عبر Range) ويمرّره
على `pdfTailIsEncrypted` لاستبعاد المشفّر (قارئ Syncfusion لا يفتحه فيظهر
"المصدر غير متاح"). الحجم يُحسب من رأس `Content-Range`/`Content-Length` —
لا من قراءة الملفّ كاملاً.

---

## 5. سياسة التراخيص

`licenseFilter.js` يقبل افتراضياً ما يطابق:

- `publicdomain` / `public-domain` / `pd`
- `cc0`
- `cc-by` و `cc-by-sa` (يرفض `cc-by-nc` و `cc-by-nd`)
- `creativecommons.org/licenses/by/*` و `…/by-sa/*`

عناصر بلا حقل ترخيص ترفض، **إلا** إن:
1. كانت ضمن `trustedCollections` المُحدَّدة في إعدادات المحرّك.
2. وكان `allowMissingLicenseInTrustedCollections === true`.

يحتفظ السجلّ بـ `__iaLicense` و `__iaCollection` لكلّ ملف لمراجعة الامتثال.

---

## 6. مخطّط Firestore (متوافق مع schema الموبايل) — روابط Proxy

يكتب `metadataRegister.js` سجلَّيْن متطابقَيْن (`content_unified_files` +
`dashboard_uploads`) عبر `adminFsWriteFileMirrorBoth` بنفس schema الرفع
اليدوي، **لكنّ كلّ الروابط العامّة تشير إلى الـ proxy** لا إلى Storage.

الامتداد `{ext}` يؤخذ من اسم الملفّ الأصليّ، وإلا fallback حسب النوع
(`document → .pdf`, `audio → .mp3`, `video → .mp4`).

```jsonc
{
  "id": "<fileId>",
  "fileId": "<fileId>",
  "title": "…",
  "description": "…",
  "author": "…",
  "thumbnail": "{NEBRAS_PUBLIC_BASE_URL}/api/proxy/ia/{fileId}?t=thumb",  // أو null إن لا غلاف
  "content_type": "document | audio | video",
  "subsection": "<sub.id>",
  "subsection_name": "…",
  "secondary_subsection": "<sec.id> | null",
  "main_section": "<main.id>",
  "main_section_id": "<main.id>",
  "main_section_name": "…",
  "downloadUrl": "{NEBRAS_PUBLIC_BASE_URL}/api/proxy/ia/{fileId}.{ext}",
  "sourceUrl":   "{NEBRAS_PUBLIC_BASE_URL}/api/proxy/ia/{fileId}.{ext}",
  "source_url":  "{NEBRAS_PUBLIC_BASE_URL}/api/proxy/ia/{fileId}.{ext}",
  "file_url":    "{NEBRAS_PUBLIC_BASE_URL}/api/proxy/ia/{fileId}.{ext}",
  "audio_url":   "{NEBRAS_PUBLIC_BASE_URL}/api/proxy/ia/{fileId}.{ext}",   // فقط للصوت
  "video_url":   "{NEBRAS_PUBLIC_BASE_URL}/api/proxy/ia/{fileId}.{ext}",   // فقط للفيديو
  "fileType": "application/pdf | audio/mpeg | video/mp4",
  "fileSize": 123456,             // من probe (Content-Range)، لا من تنزيل
  // لا storagePath — لا شيء على Firebase Storage.
  "createdAt": "<serverTimestamp>",
  "created_at": "ISO8601",
  "is_listed": true,

  // — علامات داخليّة — لا يقرأها التطبيق —
  "__provider": "internet_archive",
  "__delivery": "proxy_stream",                          // يميّز عناصر metadata-only عن رفع Storage القديم
  "__iaIdentifier": "<archive.org identifier>",
  "__iaSourceUrl": "https://archive.org/details/…",
  "__iaFileUrl": "https://archive.org/download/…",       // ⇐ المصدر الحقيقيّ — يقرأه الـ proxy فقط
  "__iaThumbUrl": "https://archive.org/…",               // أو "" إن لا غلاف
  "__iaLicense": "…",
  "__iaCollection": "…",
  "__iaImportedAt": "ISO8601",
  "__iaOriginalFilename": "…",

  // — وسوم امتثال Google Play / DMCA —
  "__license_status": "verified_open_license | community_collection | unknown",
  "__license_url": "…",
  "__license_collection": "…",
  "__attribution_url": "https://archive.org/details/…",
  "__source_provider": "archive.org",
  "__compliance_version": "2026.05",
  "__verified_at": "ISO8601"
}
```

> `content_model.dart` يقرأ `id, title, description, author, thumbnail,
> content_type, sourceUrl, subsection, secondary_subsection, …` فقط — وكلّها
> روابط proxy نبراسيّة. الحقول التي تبدأ بـ `__` غير معروفة له ولا تُؤثّر عليه.
>
> **مهمّ:** التطبيق يرفض أيّ رابط يحوي `archive.org` (دالّة `_rejectArchiveOrg`)،
> لذا حفظ الرابط الحقيقيّ في `__iaFileUrl`/`__iaThumbUrl` (لا الحقول العامّة)
> **إلزاميّ** لظهور العنصر؛ الـ proxy وحده يقرأ هذين الحقلين server-side.

---

## 7. RTDB

| المسار | الاستخدام |
|--------|----------|
| `ia_library_engine/config` | `enabled`, `seeds[]`, `tickIntervalMs`, `batchSize`, `scrapeCount`, `trustedCollections[]`, `allowMissingLicenseInTrustedCollections` |
| `ia_library_engine/cursor` | `seedIndex`, `scrapeCursor` |
| `ia_library_engine/stats` | `totalImported`, `totalSkipped`, `totalFailed`, `lastRunAt`, `lastError`, `runsCount`, `consecutiveEmptyRuns` |
| `ia_library_engine/log/{ts}` | آخر 60 إدخال (info / warn / error / success) |
| `ia_library_registry/{identifier}` | `fileId`, `title`, `iaSourceUrl`, `licenseMatched`, `collection`, `hierarchy`, `pickedFileName`, `pickedFileSize`, `nebrasContentType`, `importedAt` |
| `ia_library_failures/{identifier}` | `count`, `firstFailedAt`, `lastFailedAt`, `lastReason`, `lastMessage` |

عتبة الـ blacklist: **3 إخفاقات** على نفس الـ identifier.

---

## 8. شكل البذرة (Seed)

```json
{
  "id": "fiqh-ar-opensource",
  "label": "كتب الفقه العربيّة المفتوحة",
  "q": "فقه إسلامي",
  "nebrasTypes": ["document"],
  "languages": ["Arabic"],
  "collections": ["opensource_arabic", "community_texts"],
  "creators": [],
  "hierarchy": {
    "mainId": "1003",
    "mainName": "الفقه الإسلامي",
    "subId": "2042",
    "subName": "العبادات",
    "secondaryId": null,
    "secondaryName": null
  }
}
```

- لا تصنيف آليّ في النسخة الأولى — كلّ بذرة تكتب في تصنيف **محدّد سلفاً**.
- يجب أن تحتوي البذرة على على الأقل واحد من: `q`, `nebrasTypes`,
  `collections` — وإلا اعتُبرت غير صالحة وحُذفت.

---

## 9. آلية الـ Cron

`vercel.json` يحوي الآن جدولاً ثانياً:

```jsonc
{
  "path": "/api/cron/internet-archive-tick",
  "schedule": "*/15 * * * *"  // كلّ 15 دقيقة
}
```

السلوك:

1. يتحقّق Vercel من `Authorization: Bearer $CRON_SECRET`.
2. الـ endpoint يقرأ `ia_library_engine/config/enabled` — لو
   `false` يخرج فوراً بدون عمل.
3. لو `true` يستدعي `runEngineTick()` مرّة واحدة فقط (تكفي serverless
   execution مدتها ≤ 60 ثانية تقريباً).
4. كلّ tick يعالج `batchSize` عنصر كحدّ أقصى ويحفظ الـ `scrapeCursor`
   لمواصلة نفس البذرة في الـ tick التالي.

---

## 10. متطلّبات بيئة التشغيل (`.env`)

```dotenv
# لازم لتشغيل Firebase Admin (موجود أصلاً).
NEBRAS_STORAGE_BUCKET=nebras-9118c.appspot.com

# ★ لازم لبناء روابط الـ proxy المطلقة المكتوبة في Firestore.
# بدونه يقع المحرّك على VERCEL_PROJECT_PRODUCTION_URL ثم قيمة افتراضيّة.
# (لا تستعمل VERCEL_URL — يتغيّر مع كلّ preview وتفسد الروابط المخزَّنة.)
NEBRAS_PUBLIC_BASE_URL=https://nebras-dashboard-main.vercel.app

# لازم لتفعيل Cron tick.
CRON_SECRET=<سر طويل عشوائي>

# اختياري — Topic FCM. القيمة الافتراضية: nebras_all_users
FCM_BROADCAST_TOPIC=nebras_all_users
```

---

## 11. سيناريو استخدام نموذجي

1. المسؤول يفتح `/admin/internet-archive`.
2. يبحث: `q="تفسير ابن كثير"`, `nebrasTypes=document`, `languages=Arabic`.
3. يضغط "معاينة" → ترى `licenseInfo` + `pickedFile.name` + الحجم.
4. يختار التصنيف الهدف (main + sub + secondary).
5. "استيراد إلى نبراس" → خلال ثوانٍ يظهر الكتاب في التطبيق ضمن نفس
   التصنيف، تماماً كأنّ مديراً رفعه يدوياً.
6. لاحقاً يضبط `seeds[]` لتشغيل الاستيراد الآلي عبر `Start` ثم Cron.

---

## 12. عمليّات الصيانة

- **توقيف فوريّ:** زر "Stop" — يطفئ `enabled` ولن يعمل tick التالي.
- **إعادة المؤشّر:** يبدأ المحرّك من أوّل بذرة دون مسّ المحتوى.
- **Factory reset:** يمسح كلّ ما رفعه IA (`__provider === 'internet_archive'`)
  + registry + failures + cursor + stats. لا يلمس الرفع اليدوي.
- **مراجعة عنصر:** افتح RTDB → `ia_library_registry/{identifier}` لرؤية
  الترخيص، الـ fileId، الـ hierarchy.

---

## 13. ما **لا** يفعله المحرّك (محدّدات النسخة الحاليّة)

- لا يُنزّل الملفّ كاملاً ولا يرفع أيّ بايت إلى Firebase Storage — يكتب
  metadata فقط ويبثّ المحتوى عند الطلب عبر الـ proxy.
- لا يستورد محتوى مقيّداً (loans-only / restricted / privileged).
- لا يستورد derivatives غير مدعومة (DjVu، JP2 zip، …).
- لا يستورد ملفّات أكبر من الحدّ المعلَن لكلّ نوع.
- لا يكتب أيّ شيء في `content_unified_youtube` — العناصر اليوتيوبية في IA
  نادرة وغير موثوقة الصيغة (نتجاوزها).
- لا يجلب من أيّ مضيف خارج `*.archive.org` — حارس SSRF في مسار الـ proxy
  يرفض أيّ رابط آخر حتى لو خُزّن في الوثيقة.
- لا يفتح أيّ مسار في تطبيق Flutter — التطبيق غير معدَّل البتّة.

> **ملاحظة (تصحيح):** خلافاً للنسخة الأولى، أصبح المحرّك **ينشئ أقساماً
> جديدة آليّاً** عند الحاجة. `classifier.js` يصنّف العنصر محلّيّاً (heuristic
> عربي) فإن لم يجد قسماً رئيسيّاً مناسباً أرجع قرار `create_main`، أو
> `create_sub` إن وجد main بلا sub مناسب، و`sectionsCreator.js` يكتب هذه
> الأقسام فعلاً في `sections_unified`. التصنيف لم يعد مقيّداً بهيكليّة
> البذرة المُحدَّدة سلفاً.

---

## 14. مراجع خارجية مفيدة (للمسؤول فقط — ليست للتطبيق)

- IA Scraping API: <https://archive.org/services/search/v1/scrape>
- IA Metadata API: `https://archive.org/metadata/{identifier}`
- IA Search Help (Lucene): <https://archive.org/help/search.php>
- Creative Commons license matrix: <https://creativecommons.org/licenses/>

---

## 15. تذكير أمني

- لا يُعاد تفعيل أيّ من جسور `Mshcat` / `OldApp` / Internet Archive
  legacy stubs.
- لا تُحقن مفاتيح IA في كود العميل أو في Flutter.
- لا يجوز إضافة أيّ زر "Internet Archive" أو WebView إلى `archive.org`
  في التطبيق — هذا تجاوز للسياسة وعطّل ضمان `self-contained`.
