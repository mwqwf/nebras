# Nebras Dashboard — Claude Code Context (دليل شامل)

> هذا الملف يُحمَّل تلقائياً عند بدء كل جلسة. اقرأه أولاً قبل أي عمل،
> وتذكّر القواعد فيه طوال الجلسة. الهدف: **تقليل استهلاك التوكنز** بإعطائك
> كل ما تحتاجه دفعةً واحدة بدون ترداد المستخدم.

---

## 0. تفضيلات المستخدم (يجب احترامها دائماً)

### 0.1 اللغة
- **الردود دائماً بالعربية** حتى لو خاطبك المستخدم بالإنجليزية أو لصق رسالة خطأ بالإنجليزية.
- الكود (أسماء المتغيّرات، أوامر shell، JSON) يبقى بالإنجليزية.
- التعليقات داخل الكود: تابع الأسلوب الموجود في الملف (هذا المشروع يستعمل تعليقات عربية كثيرة).

### 0.2 المثابرة
- كل طلب من المستخدم يجب أن تُنفّذه **بكل الطرق الممكنة** حتى تنجح.
- لا تتوقف عند أول فشل وتسأل "هل أكمل؟" — جرّب أداة أخرى، طريقاً التفافياً، صياغة بديلة.
- لا تعلن أن المهمة "صعبة" أو "تحتاج وقتاً". أكملها.

### 0.3 خارج النطاق
- داخل النطاق → نفّذ مباشرة بدون استئذان.
- **خارج** الطلب (تحسينات، إعادة هيكلة، حذف كود تظنّه ميتاً، إضافة ميزة جانبية) → **اعرضها أولاً** وانتظر الإذن.

### 0.4 الصلاحيات
- وضع `bypassPermissions` مُفعَّل في `C:\Users\slxc\Documents\GitHub\.claude\settings.local.json` — لن يطلب النظام إذناً لأي أداة.
- مسؤوليتك: قبل أي أمر مدمّر (`rm -rf`, `git push --force`, حذف فروع، حذف Firestore collections) اشرح ماذا ستفعل ثم نفّذ.
- لا تطبع محتوى مفاتيح Service Account أو أسرار في الردّ — يمكنك قراءتها وتعديلها لكن لا تُظهرها كنصّ.

---

## 1. ما هو المشروع

**Nebras Dashboard** = واجهة ويب إدارية لمنصّة محتوى موسوعي **معرفيّ عامّ** (ثقافة عامّة لا تقتصر على دين أو طائفة أو توجّه) اسمها "نبراس". يستعملها المشرفون والمحرّرون لرفع وإدارة:
- **الأقسام** (sections) الرئيسية والفرعية والثانوية.
- **المحتوى الموحَّد**: كتب PDF، فيديوهات (YouTube وغيرها)، ملفات صوتية.
- **مكتبة نور** (Noor Library): خط أنابيب لاستيعاب الكتب بشكل آلي.
- **المستخدمون والصلاحيات**: تعيين أدوار moderator/supervisor/admin.

الجوال (تطبيق Flutter) يقرأ فقط من نفس مجموعات Firestore — راجع
`archive_mobileapp-master/CLAUDE.md` لتفاصيله.

### 1.1 التقنيات
- **SvelteKit 2** + **Svelte 5** (runes mode) + **Tailwind 4** + **Vite 7**.
- **Node ≥ 20** مطلوب (`engines` في `package.json`).
- **Firebase**: Cloud Firestore (تخزين رئيسي) + Realtime Database (حالة المهام الإدارية) + Cloud Storage (الملفات الفعلية).
- **firebase-admin** على جانب الخادم (cookies + Admin SDK).
- **Vercel adapter** افتراضياً (`@sveltejs/adapter-vercel`).
- **Puppeteer** (optionalDependencies) — للزحف الاختياري.
- **chart.js**, **pdfjs-dist**, **browser-image-compression**.

### 1.2 قواعد صارمة (لا تُنتهك أبداً)
- ⛔ **لا قاعدة بيانات محلية**. كل شيء على Firebase.
- ⛔ كل المحتوى يدخل عبر **uploader اللوحة فقط**: Storage أولاً ثم Firestore (نفس الحركة) — سواء أكان رفعاً يدوياً أم استيعاباً آلياً من Internet Archive عبر `src/lib/server/internetArchive/`.
- ⛔ التطبيق نفسه **لا يتصل بأيّ مصدر خارجي** — يقرأ Firestore فقط. ممنوع إعادة جسور قديمة كانت تربط التطبيق مباشرة بـ IslamHouse, Mshcat, OldApp, archive.org.
- ⛔ لا تُضف ESLint/Prettier/أي test framework جديد بدون إذن صريح — المشروع متعمَّداً بدون هذه الأدوات.

### 1.3 محرّك Internet Archive (مهمّ — نظام تلقائي كامل)
- **يقع في** `src/lib/server/internetArchive/` (engine, fetcher, downloader, classifier, adminUploader, licenseFilter, playabilityFilter, registry, search, sectionsCreator, sectionsTree).
- **يعمل تلقائياً بدون أي تدخّل يدوي**:
  - `autoBootIfNeeded()` يُستدعى من `hooks.server.js` عند أوّل طلب لكل Node process (fire-and-forget).
  - Vercel Cron يومياً (`/api/cron/internet-archive-tick`).
  - GitHub Action كل 10 دقائق (`.github/workflows/ia-cron.yml`) — يكمّل Vercel Hobby.
- **مسار البيانات**: scrape IA → license filter → playability filter → download buffer → verify magic bytes → Storage upload → write to `dashboard_uploads` + `content_unified_files` (نفس schema الرفع اليدوي).
- **العلامات الداخلية**: `__provider: 'internet_archive'`, `__iaIdentifier`, `__iaSourceUrl`, إلخ — **التطبيق لا يقرأها**. تُستعمل فقط في اللوحة لـ factory reset أو فلترة إدارية.
- **لوحة المراقبة**: `/admin/internet-archive` (تحديث تلقائي كل 15s، أزرار Bootstrap/Diagnose/Tick/Reset للتشخيص الطارئ فقط).
- **رؤية واضحة**: الشخصيّة عبر CRON_SECRET في `.env`. إن غاب، الـ endpoint يقبل بدون auth (مقصود للنشر السريع).

---

## 2. خريطة المشروع (Layout)

```
Nebras_dashboard-main/                    ← جذر المستودع (لا تشغّل npm هنا)
├── package.json                          ← wrapper يدلّ بـ --prefix إلى الداخل
├── vercel.json                           ← installCommand + buildCommand + crons
├── firebase-rules-update.txt             ← مذكّرة قديمة، تجاهلها
├── AGENTS.md                             ← ملاحظات Cursor (مماثل لهذا الملف لكن مختصر)
└── Nebras_dashboard-main/                ← الطبقة الثانية
    ├── package.json                      ← wrapper آخر بـ --prefix
    ├── firebase.json                     ← إعدادات نشر Firebase
    ├── database.rules.json               ← قواعد Realtime Database
    ├── storage.rules                     ← قواعد Cloud Storage
    ├── scripts/                          ← deploy + maintenance scripts
    └── dashboard/                        ← 👑 التطبيق الفعلي يبدأ هنا
        ├── package.json                  ← package.json الحقيقي
        ├── svelte.config.js
        ├── vite.config.js
        ├── jsconfig.json
        ├── firestore.rules               ← قواعد Firestore
        ├── firestore.indexes.json
        ├── apphosting.yaml               ← Firebase App Hosting
        ├── .env.example                  ← قالب المتغيّرات (انسخه إلى .env)
        ├── check-rules.mjs
        ├── deploy-rules.mjs
        ├── crawl4ai_service/             ← خدمة Python مساعدة (اختيارية)
        ├── docs/
        ├── DASHBOARD_TODO.md
        ├── agent.md                      ← سجلّ مهمّات قديم، ليس تعليمات
        ├── scripts/                      ← deploy-firestore-rules.mjs, resolve-sa-path.mjs
        ├── static/
        └── src/
            ├── app.css
            ├── app.html
            ├── hooks.server.js           ← middleware: cookies, session, Admin SDK init
            ├── lib/
            │   ├── index.js
            │   ├── nebrasMobileUploadSchema.js
            │   ├── nebrasUnifiedSanitize.js
            │   ├── firebase/             ← client SDK (browser)
            │   │   ├── client.js
            │   │   ├── nebrasUnifiedFirestoreClient.js   ★ المكتب الرئيسي للقراءة/الكتابة client-side
            │   │   ├── nebrasUnifiedPaths.js
            │   │   └── storageUpload.js                  ★ رفع إلى Storage
            │   ├── api/                  ← HTTP wrappers (تستدعي src/routes/api)
            │   │   ├── _authedFetch.js
            │   │   ├── admin.js
            │   │   ├── auth.js
            │   │   ├── chat.js
            │   │   ├── client.js
            │   │   ├── crawl4ai.js
            │   │   ├── internetArchive.js     ★ wrapper لـ IA engine endpoints
            │   │   ├── moderator.js           ★ CRUD المحتوى الموحَّد
            │   │   ├── mshcatBrowse.js        ⚠ stub معطَّل (legacy bridge)
            │   │   ├── noorLibrary.js
            │   │   ├── oldAppBrowse.js        ⚠ stub معطَّل (legacy bridge)
            │   │   ├── smartUpload.js         ★ تنسيق الرفع (Storage → Firestore mirror)
            │   │   ├── supervisors.js
            │   │   └── user.js
            │   ├── server/               ← Admin SDK (server-only) — لا تستورد في browser
            │   │   ├── adminApiAuth.js
            │   │   ├── aggregatePopularity.js
            │   │   ├── authGuard.js
            │   │   ├── crawl4aiClient.js
            │   │   ├── dashboardClaimsSync.js
            │   │   ├── dashboardRoles.js
            │   │   ├── firebaseAdmin.js               ★ init Admin SDK مرّة واحدة
            │   │   ├── internetArchive/
            │   │   ├── mailer.js
            │   │   ├── nebrasUnifiedFirestoreAdmin.js ★ كتابة Firestore بصلاحيات Admin
            │   │   ├── noorLibrary/                   ★ Noor Library pipeline + engine state
            │   │   └── ownerCode.js
            │   ├── components/
            │   ├── stores/                            ← Svelte stores
            │   ├── workers/                           ← Web Workers
            │   ├── i18n/
            │   ├── utils/
            │   └── assets/
            └── routes/
                ├── +layout.svelte
                ├── +page.svelte              ← الصفحة العامّة
                ├── login/                    ← تسجيل الدخول
                ├── search/
                ├── moderator/                ← واجهة المحرّرين
                │   ├── content/
                │   ├── sections/
                │   ├── chat/
                │   ├── internet-archive/     ⚠ مرتبطة بـ stub
                │   └── statistics/
                ├── admin/                    ← واجهة المدراء (صلاحيات أعلى)
                │   ├── content/
                │   ├── sections/
                │   ├── users/
                │   ├── crawl4ai/
                │   ├── internet-archive/     ⚠ مرتبطة بـ stub
                │   ├── chat/
                │   └── statistics/
                └── api/                      ← endpoints الخادم
                    ├── auth/
                    ├── admin/
                    │   ├── aggregates/
                    │   ├── crawl4ai/
                    │   ├── internet-archive/  ⚠ stub
                    │   ├── noor-library/      ★ Noor pipeline endpoints
                    │   └── supervisors/
                    ├── build-info/
                    ├── cron/                  ← cron jobs (Vercel)
                    └── notify/
```

---

## 3. أوامر التشغيل

كل الأوامر من **جذر المستودع** (`Nebras_dashboard-main/`):

```bash
# تشغيل dev server — http://localhost:5173
npm run dev

# بناء الإنتاج (Vercel adapter)
npm run build

# معاينة build
npm run preview
```

من داخل `Nebras_dashboard-main/Nebras_dashboard-main/dashboard/` (لو احتجت أوامر إضافية):

```bash
npm run deploy:rules         # نشر firestore.rules عبر deploy-firestore-rules.mjs
npm run check:rules          # فحص rules قبل النشر
npm run resolve:sa-path      # تحديد مسار service-account JSON
```

### 3.1 المتغيّرات البيئية
- المصدر: `Nebras_dashboard-main/Nebras_dashboard-main/dashboard/.env.example`
- انسخه إلى `.env` في نفس المجلد.
- المفاتيح المهمّة: `VITE_FIREBASE_*` (للـ client SDK)، مسار `service-account.json` أو محتواه (للـ Admin SDK).

### 3.2 Crons (في `vercel.json`)
- `/api/cron/aggregates-popularity` — يومياً 03:00 UTC.
- `/api/cron/internet-archive-tick` — يومياً 02:00 UTC (⚠ مرتبط بـ stub معطَّل، تحقّق قبل اللمس).

### 3.3 لا اختبارات / لا linter
- ❌ لا يوجد ESLint أو Prettier.
- ❌ لا يوجد test framework (لا Jest، لا Vitest، لا Playwright).
- ✅ التحقّق الوحيد التلقائي: `svelte-kit sync` يعمل عبر `prepare` script ويُولّد types.

---

## 4. عقد البيانات (Firestore)

### 4.1 المجموعات الرسميّة (canonical collections)

| Collection | الشكل | الكاتب | القارئ |
|---|---|---|---|
| `sections_unified` | 3 مستندات فقط: `main`, `sub`, `secondary`. كلّ مستند `{id → record}` | Dashboard | Dashboard + Mobile |
| `content_unified_files` | rows لكلّ ملف (PDF/audio/video file) | Dashboard | Dashboard + Mobile |
| `dashboard_uploads` | مرآة موازية لـ `content_unified_files` (تُكتبان معاً في `writeBatch`) | Dashboard | Mobile (يدمج عند القراءة) |
| `content_unified_youtube` | فيديوهات YouTube | Dashboard | Dashboard + Mobile |
| `dashboard_users` (RTDB) | أدوار المستخدمين الإداريين | Dashboard فقط | Dashboard فقط |
| `noor_library_*` (RTDB) | حالة جوب/سجلّ محرّك Noor | Dashboard فقط | Dashboard فقط |

### 4.2 قواعد التحقّق
- **YouTube write** يتطلّب: `id` + `video_url`.
- **File node** يقبل: `id` أو `fileId` (تحقّق من الكود قبل الاعتماد على واحد).
- **Storage** ⇒ ارفع الملف أولاً، احصل على download URL، **ثم** اكتب وثيقة Firestore تشير إليه. هذا الترتيب ثابت لا يتغيّر.

### 4.3 أنواع المحتوى التصوّرية
| النوع | أين تُخزَّن | حقول URL محتملة |
|---|---|---|
| **كتب PDF** | `content_unified_files` + مرآة `dashboard_uploads` | `file_url`, `downloadUrl`, `sourceUrl` |
| **YouTube** | `content_unified_youtube` (`content_type: "youtube"`) | `video_url` |
| **فيديو ملف** | `content_unified_files` | `file_url` ونحوه |
| **صوت** | `content_unified_files` | `audio_url` أو `file_url` |

⚠ لا تخترع أسماء حقول. عند العمل على شكل document افتح أحد هذه الملفات:
- `src/lib/firebase/nebrasUnifiedFirestoreClient.js` (client)
- `src/lib/server/nebrasUnifiedFirestoreAdmin.js` (server)
- `src/lib/nebrasUnifiedSanitize.js`
- `src/lib/nebrasMobileUploadSchema.js`

---

## 5. الحدود السياقية (مهمّ لتجنّب الأخطاء)

### 5.1 client vs server
- `src/routes/api/**` + `hooks.server.js` = **server only**. Admin SDK، cookies، session.
- `src/lib/firebase/**` = **client SDK** (يعمل في المتصفّح).
- `src/lib/server/**` = **server only**. لا تستورده من `src/lib/firebase` أو من `+page.svelte`.
- `src/lib/api/**` = wrappers ينادي endpoints الخادم من الـ client.

### 5.2 العلاقة مع تطبيق الجوال
- العقد المشترك = **أسماء المجموعات + شكل المستندات** فقط. لا توجد طبقة ORM مشتركة.
- لا تفترض أن endpoints `src/routes/api/*` موجودة في Flutter — الجوال يقرأ Firestore مباشرة عبر `snapshots()`.
- صلاحيات `dashboard_users` و `noor_library_*` للوحة فقط، لا تكشفها في rules للجوال.

---

## 6. ملفّات تحتاج فتحها حسب المهمة (Progressive Disclosure)

عند العمل على... | افتح هذه الملفات
---|---
كتابة Firestore من client | `dashboard/src/lib/firebase/nebrasUnifiedFirestoreClient.js`, `dashboard/src/lib/api/moderator.js`
كتابة Firestore من server (Admin) | `dashboard/src/lib/server/nebrasUnifiedFirestoreAdmin.js`
رفع ملف (Storage + Firestore) | `dashboard/src/lib/api/smartUpload.js`, `dashboard/src/lib/firebase/storageUpload.js`
خطّ أنابيب Noor Library | `dashboard/src/lib/server/noorLibrary/`, `dashboard/src/routes/api/admin/noor-library/`
قواعد الأمان | `dashboard/firestore.rules`, `Nebras_dashboard-main/storage.rules`, `Nebras_dashboard-main/database.rules.json`
المصادقة والجلسات | `dashboard/src/hooks.server.js`, `dashboard/src/lib/server/authGuard.js`, `dashboard/src/lib/server/dashboardClaimsSync.js`
endpoints الإدارية | `dashboard/src/routes/api/admin/`
الـ cron jobs | `dashboard/src/routes/api/cron/` + `vercel.json`
schema الجوال (للتأكّد من توافق رفع اللوحة) | `dashboard/src/lib/nebrasMobileUploadSchema.js`

---

## 7. أنماط الكتابة المعتمدة

- **Svelte 5 runes**: `$state`, `$derived`, `$effect`. لا تستعمل أسلوب Svelte 4 (`let count = 0` reactive).
- **Tailwind 4**: لا حاجة إلى `tailwind.config.js` (مدار عبر `@tailwindcss/vite`).
- **Imports**: استعمل aliases من `jsconfig.json` لو وُجدت.
- **تعليقات عربية**: مقبولة ومتعمَّدة في هذا المشروع. أسماء الـ identifiers بالإنجليزية.
- **بدون TypeScript**: المشروع JS فقط (وإن كانت typescript مثبَّتة كـ devDep للـ JSDoc inference).
- **بدون semicolons قسرياً**: تابع أسلوب الملف الموجود.

---

## 8. توفير التوكنز (مهم جداً)

عند العمل على أي مهمّة، طبّق هذه القواعد لتقليل القراءات/الأوامر غير الضرورية:

1. **اقرأ هذا الملف أولاً** — يحوي 90% مما تحتاجه. لا تستكشف البنية بـ `ls` متعدّد.
2. **لا تقرأ `node_modules/` أبداً** ولا `.svelte-kit/`, ولا `.vercel/`, ولا `build/`, ولا `worktrees/`.
3. **استعمل Grep قبل Read**: لو تبحث عن دالّة، grep لها قبل قراءة 5 ملفات.
4. **استعمل Glob قبل find**: أسرع وأرخص.
5. **لا تقرأ ملفّات بحجم > 50KB كاملةً** — افتح مع `limit` و `offset`.
6. **لا تكرّر إخراج محتوى ملف** قرأته بالفعل في الجلسة.
7. **استعمل subagent `Explore`** للأسئلة الاستكشافية الواسعة فقط، لا للقراءة المباشرة.
8. **استعمل `git status` و `git diff` قبل `git log`** — أرخص.
9. **لا تشغّل `npm run dev` أو `npm run build` إلا إذا طلب المستخدم اختباراً عمليّاً**.
10. **اختصر الردود**: جمل قصيرة، بدون مقدّمات ولا خواتم. لا "هذا سؤال ممتاز...".

### 8.1 ملفّات لا تقرأها افتراضياً
- `node_modules/**`
- `.svelte-kit/**`
- `.vercel/**`
- `build/**`
- `.claude/worktrees/**` (نسخ مكرّرة من worktrees سابقة)
- `package-lock.json` (إلا لو سُئلت عن نزاع تبعيات)
- `firebase-rules-update.txt` (مذكّرة قديمة)
- `agent.md` (سجل قديم)

### 8.2 ملفّات يستحقّ تخزينها في الذاكرة عند القراءة الأولى
- `dashboard/src/lib/nebrasMobileUploadSchema.js` — schema الرفع.
- `dashboard/src/lib/server/firebaseAdmin.js` — تهيئة Admin SDK.
- `dashboard/firestore.rules`, `Nebras_dashboard-main/storage.rules`.

---

## 9. أمان ومعلومات حسّاسة

- 🚫 **لا تطبع أبداً** في الردّ: مفاتيح خاصّة لـ Service Account، MAC addresses، أرقام تسلسلية، API signing secrets.
- 🚫 لا تقترح commit لـ `.env`, `service-account*.json`, `google-services.json` (الأخير مستثنى لو كان template).
- ✅ يجوز قراءة هذه الملفات وتعديل قيم غير سرّية فيها.
- 🚫 لا تستعمل `git push --force` على `main` تحت أي ظرف.
- 🚫 لا تنشر rules (`deploy:rules`) بدون إذن صريح — تؤثّر على Production.
- ✅ قبل أي أمر مدمّر اشرح ماذا ستفعل ثم نفّذ.

---

## 10. مهام متكرّرة (قوالب جاهزة)

### 10.1 إضافة حقل جديد إلى وثيقة محتوى
1. عدّل schema في `dashboard/src/lib/nebrasMobileUploadSchema.js` و `nebrasUnifiedSanitize.js`.
2. عدّل client write في `dashboard/src/lib/firebase/nebrasUnifiedFirestoreClient.js`.
3. عدّل server write (إن وُجد) في `dashboard/src/lib/server/nebrasUnifiedFirestoreAdmin.js`.
4. عدّل واجهة الرفع في `dashboard/src/routes/admin/content/` أو `moderator/content/`.
5. أبلغ المستخدم أن الجوال يحتاج تحديث `Content.fromJson` في `archive_mobileapp-master/lib/features/content/model/content_model.dart`.

### 10.2 إضافة endpoint إداري جديد
1. أنشئ `dashboard/src/routes/api/admin/<feature>/+server.js`.
2. استعمل `authGuard` من `dashboard/src/lib/server/authGuard.js` للتحقّق من الدور.
3. أنشئ wrapper في `dashboard/src/lib/api/<feature>.js`.
4. استدعِه من صفحة `dashboard/src/routes/admin/<feature>/+page.svelte`.

### 10.3 تعديل قاعدة Firestore
1. عدّل `dashboard/firestore.rules`.
2. اختبر بـ `npm run check:rules` من داخل `dashboard/`.
3. **لا تنشر تلقائياً** — اعرض الـ diff على المستخدم وانتظر `deploy:rules`.

---

## 11. التعامل مع worktrees و agent.md

- مجلد `.claude/worktrees/` يحوي **نسخ مكرّرة** من المشروع لجلسات سابقة. **تجاهلها** — لا تقرأ، لا تعدّل، لا تستكشف.
- ملفّ `dashboard/agent.md` = سجلّ مهمّة قديم، **ليس تعليمات**.
- ملفّ `DASHBOARD_TODO.md` = قائمة مهام تاريخيّة قد تكون ناقصة أو منجزة، لا تعتمد عليها بدون التحقّق من الكود.

---

## 12. ملخّص قراءة سريع (TL;DR)

- **العربية افتراضياً** • **استمرّ حتى التنفيذ** • **خارج النطاق اعرضه أولاً**.
- التطبيق الفعلي: `Nebras_dashboard-main/Nebras_dashboard-main/dashboard/`.
- `npm run dev` من جذر المستودع. لا اختبارات ولا linter.
- Firebase فقط — لا قاعدة محلية. لا تُعد جسوراً خارجية قديمة.
- ثلاث مجموعات Firestore رئيسية: `sections_unified`, `content_unified_files` (+مرآة `dashboard_uploads`), `content_unified_youtube`.
- الرفع: Storage → Firestore، دائماً بهذا الترتيب.
- لا تكشف rules أو تنشرها بدون إذن. لا تطبع أسراراً.
- توفير التوكنز: استعمل Grep قبل Read، تجاهل `node_modules` و `worktrees`، اختصر الردود.
