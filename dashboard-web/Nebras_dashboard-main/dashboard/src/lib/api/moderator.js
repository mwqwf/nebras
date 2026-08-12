/**
 * Moderator API
 *
 * Sections CRUD + unified file content CRUD.
 * Uses multipart/form-data for create/update (thumbnail/file uploads).
 * The backend enforces created_by = current user automatically.
 */

import {
  apiGet,
  apiPost,
  apiPostForm,
  apiPatchForm,
  apiDelete,
} from "$lib/api/client.js";
import {
  getFirebaseStorage,
} from "$lib/firebase/client.js";
import {
  clientFsReadSectionsLevel,
  clientFsReadSectionsSubMap,
  clientFsGetSectionRecord,
  clientFsSetSectionRecord,
  clientFsDeleteSectionRecord,
  // ⚠️ Legacy-cleanup only: ميزة يوتيوب أُزيلت بالكامل من اللوحة. نُبقي
  // هاتين الدالّتين فقط لتنظيف سجلّات يوتيوب القديمة (content_unified_youtube)
  // عند حذف قسم رئيسي/فرعي/ثانوي حتى لا تبقى وثائق يتيمة.
  clientFsListYoutubeRecords,
  clientFsDeleteYoutubeRecord,
  clientFsListFileRowsMerged,
  clientFsGetFileRow,
  clientFsWriteFileMirrorBoth,
  clientFsDeleteFileMirrorBoth,
} from "$lib/firebase/nebrasUnifiedFirestoreClient.js";
// ⚠️ الرفع لم يعد يستخدم Storage Web SDK مباشرة من هنا؛ نمرّ عبر smartUpload
// الذي يوجِّه تلقائيًّا: Nebras → Web SDK، Mshcat/OldApp → /api/.../uploads.
// نُبقي `ref` و `deleteObject` فقط لحذف كائنات التخزين الفعليّة في Nebras
// (مسار `removeFile`) — وهي عمليّة حذف لا رفع.
import { ref as storageRef, deleteObject } from "firebase/storage";
import { authedJson } from "$lib/api/_authedFetch.js";
import { smartUpload } from "$lib/api/smartUpload.js";
import {
  tokenize,
  matchesAllTokens,
  filterAndRank,
  createTtlCache,
} from "$lib/utils/search.js";
import { pickEngagementStats } from "$lib/utils/engagementStats.js";

// Mshcat/OldApp bridges removed (commit e4e0062). Legacy code paths inside this
// file branch on isMshcatConfigured()/isOldAppConfigured() — wired here to inert
// stubs so the rest of the module stays loadable for the primary Nebras flow.
const NOT_CONFIGURED = () => false;
const RETURN_NULL = () => null;
const EMPTY_LIST = async () => [];
const NOT_SUPPORTED = async () => {
  throw new Error("الجسر الخارجي محذوف — الكتابة مدعومة في نبراس فقط.");
};
const PASSTHROUGH = (x) => x;

const isOldAppConfigured = NOT_CONFIGURED;
const isOldAppId = NOT_CONFIGURED;
const parseOldAppId = RETURN_NULL;
const getHostMainSectionId = async () => null;
const listOldAppMainSections = EMPTY_LIST;
const listOldAppSubSections = EMPTY_LIST;
const adaptOldAppMainAsSub = PASSTHROUGH;
const adaptOldAppSubAsSecondary = PASSTHROUGH;
const createOldAppMainSection = NOT_SUPPORTED;
const updateOldAppMainSection = NOT_SUPPORTED;
const deleteOldAppMainSection = NOT_SUPPORTED;
const createOldAppSubSection = NOT_SUPPORTED;
const updateOldAppSubSection = NOT_SUPPORTED;
const deleteOldAppSubSection = NOT_SUPPORTED;
const listOldAppLessonsBySub = EMPTY_LIST;
const createOldAppLesson = NOT_SUPPORTED;
const updateOldAppLesson = NOT_SUPPORTED;
const deleteOldAppLesson = NOT_SUPPORTED;
const adaptOldAppLessonAsFile = PASSTHROUGH;
const adaptOldAppLessonAsYoutube = PASSTHROUGH;

const isMshcatConfigured = NOT_CONFIGURED;
const isMshcatId = NOT_CONFIGURED;
const parseMshcatId = RETURN_NULL;
const listMshcatMainSections = EMPTY_LIST;
const listMshcatSubSections = EMPTY_LIST;
const listMshcatSecondarySections = EMPTY_LIST;
const listMshcatBooksForCategory = EMPTY_LIST;
const listAllMshcatBooks = EMPTY_LIST;
const classifyMshcatCategories = async () => ({ main: [], sub: [], secondary: [] });
const createMshcatCategory = NOT_SUPPORTED;
const updateMshcatCategory = NOT_SUPPORTED;
const deleteMshcatCategory = NOT_SUPPORTED;
const createMshcatBook = NOT_SUPPORTED;
const updateMshcatBook = NOT_SUPPORTED;
const deleteMshcatBook = NOT_SUPPORTED;
const adaptMshcatMain = PASSTHROUGH;
const adaptMshcatSub = PASSTHROUGH;
const adaptMshcatSecondary = PASSTHROUGH;
const adaptMshcatBookAsFile = PASSTHROUGH;
const adaptMshcatBookAsYoutube = PASSTHROUGH;

// ─── Helpers ────────────────────────────────────────────

/**
 * بوابة البحث الإلزاميّة — ترفض جلب آلاف المستندات على مجرّد فتح الصفحة.
 *
 * الاستعمال: تُمرَّر `{ requireSearch: true, search, hasActiveFilter }`
 * من الصفحات الإداريّة (sections/files/youtube).
 *   - إن كان `search` فارغًا/أقصر من الحدّ الأدنى **و** لا يوجد فلتر نشط،
 *     فإنّ الدالة تعيد `true` (يعني: أرجِع قائمة فارغة فورًا).
 *   - إن كان هناك فلتر نشط (قسم محدَّد، نوع محتوى، …) فالبحث يُسمَح به
 *     حتى بدون نصّ، لأنّ الفلتر نفسه يُقيّد حجم النتيجة.
 * الاستدعاءات الداخليّة (من النوافذ المنبثقة) تتركها على false
 * لأنّها محدودة العدد ومربوطة بفعل صريح من المستخدم.
 */
const MIN_SEARCH_LEN = 2;
function shouldSkipListing({ requireSearch, search, hasActiveFilter } = {}) {
  if (!requireSearch) return false;
  if (hasActiveFilter) return false;
  const q = String(search || "").trim();
  return q.length < MIN_SEARCH_LEN;
}

// ─── Memoization for external heavy merges ──────────────
//
// بعض استدعاءات المشاريع الثانويّة (Mshcat/OldApp) تقرأ شجرة كاملة من
// الكتب أو الأقسام. تكرار البحث خلال ثوانٍ قليلة (مثلاً تصحيح كلمة)
// يجب ألّا يُعيد نفس القراءات الشبكيّة. نستخدم TTL قصير (30s) لنضمن أن
// البيانات تظلّ طازجة بعد أيّ عمليّة كتابة من المستخدم (إنشاء/تعديل/حذف).
const EXTERNAL_TTL_MS = 30000;
const externalCache = createTtlCache(EXTERNAL_TTL_MS);

/** يُفرغ ذاكرة دمج المشاريع الثانويّة بعد أيّ عمليّة كتابة حاسمة. */
function invalidateExternalCaches() {
  externalCache.invalidate();
}

// Tracking partial source failures for UI awareness.
// مخصَّص للاستخدام عبر `getLastPartialFailures()` من الصفحات.
let _lastPartialFailures = [];
function recordPartialFailure(source, err) {
  _lastPartialFailures.push({ source, message: String(err?.message || err) });
  if (import.meta.env.DEV) console.warn(`[moderator] ${source} failed:`, err);
}
function resetPartialFailures() {
  _lastPartialFailures = [];
}
/**
 * يُرجع أيّ فشل جزئي حدث أثناء آخر عمليّة جلب (Mshcat/OldApp).
 * الواجهة تستطيع عرضه كـ toast تحذيري بدل أن يظنّ المشرف أنّ القائمة كاملة.
 */
export function getLastPartialFailures() {
  return [..._lastPartialFailures];
}

function emptyPage() {
  return { results: [], count: 0, page: 1, page_size: 0, has_next: false };
}

/**
 * Build a FormData object from a plain/nested object.
 * Supports nested objects via dot notation: { metadata: { title: 'x' } } → 'metadata.title' = 'x'
 * Skips undefined/null values. Handles File objects natively.
 */
function buildFormData(data, fd = new FormData(), prefix = "") {
  for (const [key, value] of Object.entries(data)) {
    if (value === undefined || value === null) continue;

    const fieldKey = prefix ? `${prefix}.${key}` : key;

    if (value instanceof File) {
      fd.append(fieldKey, value);
    } else if (
      typeof value === "object" &&
      !(value instanceof Date) &&
      !Array.isArray(value)
    ) {
      // Recurse for nested objects
      buildFormData(value, fd, fieldKey);
    } else if (value !== "") {
      fd.append(fieldKey, String(value));
    }
  }
  return fd;
}

function hasOwn(obj, key) {
  return !!obj && Object.prototype.hasOwnProperty.call(obj, key);
}

function asTrimmedString(value) {
  return String(value ?? "").trim();
}

function mergeContentMetadataPreservingHierarchy(
  currentMeta = {},
  incomingMeta = {},
) {
  const next = { ...currentMeta };

  if (hasOwn(incomingMeta, "title")) next.title = asTrimmedString(incomingMeta.title);
  if (hasOwn(incomingMeta, "description")) {
    next.description = asTrimmedString(incomingMeta.description);
  }
  if (hasOwn(incomingMeta, "author")) next.author = asTrimmedString(incomingMeta.author);
  if (hasOwn(incomingMeta, "is_listed")) {
    next.is_listed = Boolean(incomingMeta.is_listed);
  }
  if (hasOwn(incomingMeta, "content_type")) {
    next.content_type = asTrimmedString(incomingMeta.content_type);
  }

  // لا نغيّر القسم/المسار إلا إذا أرسله المستخدم صراحةً.
  if (hasOwn(incomingMeta, "main_section")) next.main_section = incomingMeta.main_section || null;
  if (hasOwn(incomingMeta, "subsection")) next.subsection = incomingMeta.subsection || null;
  if (hasOwn(incomingMeta, "secondary_subsection")) {
    next.secondary_subsection = incomingMeta.secondary_subsection || null;
  }

  return next;
}

function uniqStrings(values) {
  return [...new Set(
    (values || [])
      .filter(Boolean)
      .map((x) => String(x).trim())
      .filter(Boolean),
  )];
}

function collectAssetUrls(row) {
  return uniqStrings([
    row?.thumbnail,
    row?.image,
    row?.imageUrl,
    row?.thumbnailUrl,
    row?.metadata?.thumbnail,
    row?.file_url,
    row?.audio_url,
    row?.video_url,
    row?.downloadUrl,
    row?.sourceUrl,
    row?.url,
  ]);
}

async function deleteStorageUrlsByValue(urls = []) {
  const storage = sectionsStorage();
  for (const url of uniqStrings(urls)) {
    try {
      await deleteObject(storageRef(storage, url));
    } catch {
      // لا نوقف الحذف الجذري بسبب ملف مفقود.
    }
  }
}

// ─── Content mirror helpers ─────────────────────────────

const CONTENT_ROOT = "content_unified";
const UPLOADS_ROOT = "dashboard_uploads";
const UPLOADS_FALLBACK_ROOT = "content_unified/files";

function buildUploadMirrorFields(current, metadata) {
  const normalized = metadata && typeof metadata === "object" ? metadata : {};
  const contentType = String(
    normalized.content_type || current?.content_type || "",
  )
    .trim()
    .toLowerCase();
  const sourceUrl = String(
    current?.downloadUrl ||
      current?.sourceUrl ||
      current?.file_url ||
      current?.audio_url ||
      current?.video_url ||
      "",
  ).trim();
  return {
    id: current?.fileId || current?.id,
    title: normalized.title ?? current?.title,
    description: normalized.description ?? current?.description,
    author: normalized.author ?? current?.author,
    thumbnail: normalized.thumbnail ?? current?.thumbnail,
    content_type: normalized.content_type ?? current?.content_type,
    subsection: normalized.subsection ?? current?.subsection,
    subsection_name:
      normalized.subsection_name ??
      normalized.subsection_title ??
      current?.subsection_name,
    secondary_subsection:
      normalized.secondary_subsection ?? current?.secondary_subsection,
    secondary_subsection_name:
      normalized.secondary_subsection_name ??
      normalized.secondary_subsection_title ??
      current?.secondary_subsection_name,
    main_section: normalized.main_section ?? current?.main_section,
    main_section_id: normalized.main_section_id ?? current?.main_section_id,
    main_section_name:
      normalized.main_section_name ?? current?.main_section_name,
    sourceUrl: sourceUrl || current?.sourceUrl,
    file_url: sourceUrl || current?.file_url,
    audio_url: contentType === "audio" ? sourceUrl : current?.audio_url,
    video_url: contentType === "video" ? sourceUrl : current?.video_url,
  };
}

/**
 * يحسب «المسار القانونيّ» (trail) لقسم محتوى انطلاقًا من المعرّفات المطلوبة:
 * يقرأ سجلّات الأقسام الفعليّة، يستنتج الآباء من الأبناء لضمان سلسلة صحيحة،
 * يجلب الأسماء المحدَّثة، ويُصفّر المستويات الأعمق غير المُختارة. يُستعمل عند
 * *نقل* المحتوى كي لا يبقى اسم/معرّف قسمٍ قديم عالقًا في الوثيقة.
 * @param {{ main_section?: any, subsection?: any, secondary_subsection?: any }} sel
 */
async function resolveContentSectionTrail(sel = {}) {
  const norm = (v) => {
    const s = String(v ?? "").trim();
    return s ? s : null;
  };
  let mainId = norm(sel.main_section);
  let subId = norm(sel.subsection);
  let secId = norm(sel.secondary_subsection);
  let mainName = null;
  let subName = null;
  let secName = null;

  // الثانويّ → اسمه + أبوه القانونيّ (الفرعيّ الحقيقيّ يحكم).
  if (secId) {
    const secRec = await clientFsGetSectionRecord("secondary", secId);
    if (secRec) {
      secName = asTrimmedString(secRec.name) || null;
      const parentSub = norm(secRec.sub_section);
      if (parentSub) subId = parentSub;
    } else {
      secId = null; // ثانويّ غير موجود → أُلغِ
    }
  }

  // الفرعيّ → اسمه + أبوه القانونيّ (الرئيسيّ). لا فرعيّ ⇒ لا ثانويّ.
  if (subId) {
    const subRec = await clientFsGetSectionRecord("sub", subId);
    if (subRec) {
      subName = asTrimmedString(subRec.name) || null;
      const parentMain = norm(subRec.main_section);
      if (parentMain) mainId = parentMain;
    } else {
      subId = null;
      secId = null;
      secName = null;
    }
  } else {
    secId = null;
    secName = null;
  }

  // الرئيسيّ → اسمه.
  if (mainId) {
    const mainRec = await clientFsGetSectionRecord("main", mainId);
    if (mainRec) {
      mainName = asTrimmedString(mainRec.name) || null;
    } else {
      mainId = null;
    }
  }

  return {
    main_section: mainId,
    main_section_id: mainId,
    main_section_name: mainName,
    subsection: subId,
    subsection_name: subName,
    secondary_subsection: secId,
    secondary_subsection_name: secName,
  };
}

// ─── Main Sections ──────────────────────────────────────

const SECTIONS_ROOT = "sections_unified";

async function readLevel(level) {
  return clientFsReadSectionsLevel(
    /** @type {'main'|'sub'|'secondary'} */ (level),
  );
}

function sectionsStorage() {
  const storage = getFirebaseStorage();
  if (!storage) throw new Error("Firebase Storage غير مهيأ.");
  return storage;
}

function makeSectionId() {
  return Date.now() + Math.floor(Math.random() * 1000);
}

/**
 * استنتاج وجهة الرفع (target) من قيمة `level` — الطريقة الأكثر ثباتًا
 * للتوجيه الذكيّ دون أيّ تعديل في مواقع الاستدعاء.
 *
 * تقاليد التسمية الحاليّة في هذا الملفّ (ثابتة تاريخيًّا):
 *   - "main" / "sub" / "secondary" / "youtube"              → Nebras
 *   - "main-mshcat" / "sub-mshcat" / "secondary-mshcat" /
 *     "youtube-mshcat"                                       → Mshcat
 *   - "sub-oldapp" / "secondary-oldapp" / "youtube-oldapp"   → OldApp
 */
function resolveThumbnailTarget(level) {
  const s = String(level || "").toLowerCase();
  if (s.endsWith("-mshcat")) return "mshcat";
  if (s.endsWith("-oldapp")) return "oldapp";
  return "nebras";
}

/**
 * الموجّه الذكيّ لرفع صورة مصغّرة لقسم/محتوى.
 * - Nebras  → smartUpload يضع الملفّ في دلو Nebras مباشرةً (Web SDK).
 * - Mshcat  → smartUpload يمرّر FormData إلى `/api/mshcat/uploads`.
 * - OldApp  → smartUpload يمرّر FormData إلى `/api/oldapp/uploads`.
 *
 * أخطاء smartUpload تحمل `.status` و `.message` عربي جاهز للـ UI
 * ونتركها تُمرَّر إلى الأعلى كما هي (شفافيّة الأخطاء).
 *
 * @param {string} level       — وصفة تُستخدم كمجلد داخل الدلو (مع target suffix).
 * @param {string|number} sectionId
 * @param {File} file
 * @returns {Promise<string|undefined>} — download URL أو undefined إن لا ملف.
 */
async function uploadSectionThumbnail(level, sectionId, file) {
  if (!(file instanceof File)) return undefined;
  const target = resolveThumbnailTarget(level);
  const folder = `sections/${level}/${sectionId}`;
  const filename = `${Date.now()}_${String(file.name || "thumb").replace(
    /[^\w.\-]/g,
    "_",
  )}`;
  const result = await smartUpload({ file, target, folder, filename });
  return result?.url || undefined;
}

function paginate(list, page = 1, pageSize = 10) {
  const current = Math.max(Number(page) || 1, 1);
  const start = (current - 1) * pageSize;
  const end = start + pageSize;
  return {
    count: list.length,
    next: end < list.length ? current + 1 : null,
    previous: current > 1 ? current - 1 : null,
    results: list.slice(start, end),
  };
}

/** مقارنة معرّفات متسامحة مع String/Number (OldApp يستعمل docId نصّي). */
function sameSectionId(a, b) {
  if (a === undefined || a === null || b === undefined || b === null) return false;
  return String(a) === String(b);
}

function parseOldAppContentId(id) {
  const s = String(id || "");
  if (!s.startsWith("oldapp:lesson:")) return null;
  const parts = s.split(":");
  return parts[2] ? { lessonDocId: parts[2] } : null;
}

/**
 * يُحدّد القسم الهدف (Mshcat category docId) عند إنشاء/تحديث محتوى.
 * يفحص `secondary_subsection` ثمّ `subsection` وفق الأولويّة: ثانوي (sec)
 * أفضل من فرعي (sub) أفضل من رئيسي (main). يعيد `{ docId, level }` أو null.
 */
function detectMshcatContentTarget({ subsectionId, secondarySubsectionId }) {
  const candidates = [secondarySubsectionId, subsectionId];
  for (const c of candidates) {
    if (!isMshcatId(c)) continue;
    const parsed = parseMshcatId(c);
    if (!parsed) continue;
    // نقبل أيّ مستوى؛ لكن نفضّل sec > sub > main.
    if (parsed.level === "sec") return { docId: parsed.docId, level: "sec" };
  }
  for (const c of candidates) {
    if (!isMshcatId(c)) continue;
    const parsed = parseMshcatId(c);
    if (parsed?.level === "sub") return { docId: parsed.docId, level: "sub" };
  }
  for (const c of candidates) {
    if (!isMshcatId(c)) continue;
    const parsed = parseMshcatId(c);
    if (parsed?.level === "main") return { docId: parsed.docId, level: "main" };
  }
  return null;
}

function parseMshcatBookId(id) {
  const parsed = parseMshcatId(id);
  return parsed?.level === "book" ? { bookDocId: parsed.docId } : null;
}

function buildSearchAction(kind, id, query = "") {
  const q = String(query || "").trim();
  const withQuery = (base) => ({ ...base, ...(q ? { q } : {}) });

  switch (kind) {
    case "main":
    case "sub":
    case "secondary":
      return {
        edit: {
          route: "/moderator/sections",
          query: withQuery({ level: kind, modal: "edit", id: String(id) }),
        },
        delete: {
          route: "/moderator/sections",
          query: withQuery({ level: kind, modal: "delete", id: String(id) }),
        },
      };
    case "file":
      return {
        edit: {
          route: "/moderator/content/files",
          query: withQuery({ modal: "edit", id: String(id) }),
        },
        delete: {
          route: "/moderator/content/files",
          query: withQuery({ modal: "delete", id: String(id) }),
        },
      };
    default:
      return {};
  }
}

function toSearchHit(kind, item, query = "") {
  if (kind === "main" || kind === "sub" || kind === "secondary") {
    return {
      id: String(item.id),
      kind,
      title: item.name || "",
      description: item.description || "",
      thumbnail: item.thumbnail || null,
      is_listed: item.is_listed ?? true,
      raw: item,
      actions: buildSearchAction(kind, item.id, query),
    };
  }

  return {
    id: String(item.id),
    kind: "file",
    title: item?.metadata?.title || item?.filename || "",
    description: item?.metadata?.description || "",
    thumbnail: item?.metadata?.thumbnail || null,
    content_type: item?.metadata?.content_type || item?.file_type || "file",
    raw: item,
    actions: buildSearchAction("file", item.id, query),
  };
}

export async function searchDashboardUnified({
  query,
  requireSearch = true,
} = {}) {
  const q = String(query || "").trim();

  if (!q || q.length < MIN_SEARCH_LEN) {
    return {
      query: q,
      groups: {
        mainSections: [],
        subSections: [],
        secondarySections: [],
        content: [],
      },
      all: [],
      partialFailures: [],
    };
  }

  resetPartialFailures();

  const [mains, subs, secondaries, files] = await Promise.all([
    listMyMainSections({ search: q, page: 1, requireSearch }),
    listMySubSections({ search: q, page: 1, requireSearch }),
    listMySecondarySections({ search: q, page: 1, requireSearch }),
    listMyFiles({ search: q, page: 1, requireSearch }),
  ]);

  const mainHits = (mains.results || []).map((item) => toSearchHit("main", item, q));
  const subHits = (subs.results || []).map((item) => toSearchHit("sub", item, q));
  const secondaryHits = (secondaries.results || []).map((item) =>
    toSearchHit("secondary", item, q),
  );
  const fileHits = (files.results || []).map((item) => toSearchHit("file", item, q));

  return {
    query: q,
    groups: {
      mainSections: mainHits,
      subSections: subHits,
      secondarySections: secondaryHits,
      content: [...fileHits],
    },
    all: [...mainHits, ...subHits, ...secondaryHits, ...fileHits],
    partialFailures: getLastPartialFailures(),
  };
}

function applySectionFilters(
  list,
  { search = "", is_listed, main_section, sub_section } = {},
) {
  let out = [...list];
  // Arabic-aware AND matching + relevance ranking.
  const tokens = tokenize(search);
  if (tokens.length > 0) {
    out = filterAndRank(out, tokens, (x) => [
      x.name || "",
      x.description || "",
      x.id != null ? String(x.id) : "",
    ]);
  }
  if (is_listed !== undefined) {
    out = out.filter((x) => Boolean(x.is_listed) === Boolean(is_listed));
  }
  if (
    main_section !== undefined &&
    main_section !== "" &&
    main_section !== null
  ) {
    out = out.filter((x) => sameSectionId(x.main_section, main_section));
  }
  if (sub_section !== undefined && sub_section !== "" && sub_section !== null) {
    out = out.filter((x) => sameSectionId(x.sub_section, sub_section));
  }
  // إن لم يكن هناك بحث نفرز بالترتيب الأصلي (order_index ثم id). مع
  // البحث، filterAndRank يُحافظ على ترتيب الصِلة (ما يجعل النتيجة الأهمّ
  // في الأعلى).
  if (tokens.length === 0) {
    out.sort((a, b) => {
      const ao = Number(a.order_index ?? 0);
      const bo = Number(b.order_index ?? 0);
      if (ao !== bo) return ao - bo;
      const an = Number(a.id);
      const bn = Number(b.id);
      if (Number.isFinite(an) && Number.isFinite(bn)) return bn - an;
      return String(b.id || "").localeCompare(String(a.id || ""));
    });
  }
  return out;
}

/**
 * List the moderator's own main sections.
 *
 * **دمج Mshcat**: إن كان المشروع الثانوي مُهيَّأً نُدرج أقسامه الرئيسيّة
 * (mshcat:main:*) بجانب أقسام Nebras — تطابق 1:1 دون هبوط رتبة.
 * @param {Object} params - { search?, page? }
 */
export async function listMyMainSections({ search = "", page = 1, requireSearch = false, all: fetchAll = false } = {}) {
  if (shouldSkipListing({ requireSearch, search })) return emptyPage();
  const all = await readLevel("main");
  let merged = all;
  if (isMshcatConfigured()) {
    try {
      const mains = await listMshcatMainSections();
      merged = [...all, ...mains.map(adaptMshcatMain)];
    } catch (err) {
      if (import.meta.env.DEV) {
        console.warn("[moderator] Mshcat main merge failed:", err);
      }
    }
  }
  const filtered = applySectionFilters(merged, { search });
  // `all: true` ⇒ نتجاوز التصفّح ونُعيد القائمة كاملة (لقوائم الاختيار).
  return paginate(filtered, fetchAll ? 1 : page, fetchAll ? (filtered.length || 1) : 10);
}

/**
 * Create a main section (multipart/form-data).
 *
 * **توجيه المصدر**: إذا حمل `data.source` قيمة `'mshcat'` نُنشئ الفئة
 * مباشرةً في قاعدة بيانات Mshcat (root category) بدل RTDB. خيار المصدر
 * وحيد في شاشة إنشاء القسم الرئيسيّ فقط — كلّ ما يتولّد بعدها من
 * فرعي/ثانوي/محتوى يرث المصدر تلقائيًّا بناءً على الـ ID.
 * @param {Object} data - { name, order_index?, thumbnail? (File), source? }
 */
export async function createMainSection(data) {
  const source = String(data?.source || "nebras").trim().toLowerCase();
  if (source === "mshcat") {
    if (!isMshcatConfigured()) {
      throw new Error("Mshcat Firebase غير مُهيّأ — أضف متغيّرات VITE_MSHCAT_* في .env");
    }
    let thumbUrl = null;
    if (data?.thumbnail instanceof File) {
      thumbUrl = await uploadSectionThumbnail(
        "main-mshcat",
        Date.now(),
        data.thumbnail,
      );
    }
    const created = await createMshcatCategory({
      name: data?.name,
      thumbnailUrl: thumbUrl,
      parentDocId: "",
    });
    return {
      id: `mshcat:main:${created.id}`,
      name: String(data?.name || "").trim(),
      order_index: Number(data?.order_index || 0),
      is_listed: data?.is_listed ?? true,
      thumbnail: thumbUrl || null,
      created_at: new Date().toISOString(),
      __mshcatDocId: created.id,
      __mshcatLevel: "main",
    };
  }

  const id = makeSectionId();
  const thumbUrl = await uploadSectionThumbnail("main", id, data?.thumbnail);
  const payload = {
    id,
    name: String(data?.name || "").trim(),
    order_index: Number(data?.order_index || 0),
    is_listed: data?.is_listed ?? true,
    thumbnail: thumbUrl || null,
    created_at: new Date().toISOString(),
  };
  await clientFsSetSectionRecord("main", id, payload);
  return payload;
}

/**
 * Update a main section (PATCH, multipart/form-data).
 * @param {number} id
 * @param {Object} data - { name?, order_index?, thumbnail? (File) }
 */
export async function updateMainSection(id, data) {
  if (isMshcatId(id)) {
    const parsed = parseMshcatId(id);
    if (parsed?.level === "main") {
      let thumbUrl;
      if (data?.thumbnail instanceof File) {
        thumbUrl = await uploadSectionThumbnail(
          "main-mshcat",
          parsed.docId,
          data.thumbnail,
        );
      }
      await updateMshcatCategory(parsed.docId, {
        name: data?.name,
        ...(thumbUrl !== undefined ? { thumbnailUrl: thumbUrl } : {}),
      });
      return { id, name: data?.name, thumbnail: thumbUrl || null };
    }
  }

  const current = await clientFsGetSectionRecord("main", id);
  if (!current) throw new Error("Section not found");
  const patch = {
    ...(data?.name !== undefined ? { name: String(data.name).trim() } : {}),
    ...(data?.description !== undefined
      ? { description: String(data.description || "").trim() }
      : {}),
    ...(data?.order_index !== undefined
      ? { order_index: Number(data.order_index || 0) }
      : {}),
    ...(data?.is_listed !== undefined
      ? { is_listed: Boolean(data.is_listed) }
      : {}),
  };
  if (data?.thumbnail instanceof File) {
    patch.thumbnail = await uploadSectionThumbnail("main", id, data.thumbnail);
  }
  const next = { ...current, ...patch };
  await clientFsSetSectionRecord("main", id, next);
  return next;
}

/**
 * Delete a main section.
 * @param {number} id
 */
export async function removeMainSection(id) {
  if (isMshcatId(id)) {
    const parsed = parseMshcatId(id);
    if (parsed?.level === "main") {
      await deleteMshcatCategory(parsed.docId);
      return true;
    }
  }

  const mainRow = await clientFsGetSectionRecord("main", id);
  const subItems = await readLevel("sub");
  const secItems = await readLevel("secondary");
  const fileRows = await clientFsListFileRowsMerged();
  const videos = await clientFsListYoutubeRecords();
  const subRows = subItems.filter((s) => sameSectionId(s.main_section, id));
  const subIds = subRows.map((s) => s.id);
  const secondaryRows = secItems.filter((sec) =>
    subIds.some((subId) => sameSectionId(sec.sub_section, subId)),
  );
  const secondaryIds = secondaryRows.map((sec) => sec.id);
  // مُطابِق شامل: المحتوى يخصّ هذا القسم الرئيسيّ إن طابق مباشرةً (main_section)
  // أو طابق أحد أقسامه الفرعيّة/الثانويّة. نقرأ من الميتاداتا ومن حقول المرآة
  // العليا معًا حتى لا ينجو محتوى مرتبط مباشرةً بالرئيسيّ (بلا قسم فرعي) ولا
  // محتوى قديم لا يحمل سوى حقول المرآة.
  const belongsToMain = (row) => {
    const md = row?.metadata || {};
    const mainMatch =
      sameSectionId(md.main_section, id) ||
      sameSectionId(md.main_section_id, id) ||
      sameSectionId(row?.main_section, id) ||
      sameSectionId(row?.main_section_id, id);
    const subMatch = subIds.some(
      (subId) =>
        sameSectionId(md.subsection, subId) || sameSectionId(row?.subsection, subId),
    );
    const secMatch = secondaryIds.some(
      (secId) =>
        sameSectionId(md.secondary_subsection, secId) ||
        sameSectionId(row?.secondary_subsection, secId),
    );
    return mainMatch || subMatch || secMatch;
  };
  const fileRowsToDelete = fileRows.filter(belongsToMain);
  const videosToDelete = videos.filter(belongsToMain);
  await deleteStorageUrlsByValue([
    ...collectAssetUrls(mainRow || {}),
    ...subRows.flatMap(collectAssetUrls),
    ...secondaryRows.flatMap(collectAssetUrls),
    ...fileRowsToDelete.flatMap(collectAssetUrls),
    ...videosToDelete.flatMap(collectAssetUrls),
  ]);
  await Promise.all(
    fileRowsToDelete.map((row) => clientFsDeleteFileMirrorBoth(row.fileId || row.id)),
  );
  await Promise.all(
    videosToDelete.map((row) => clientFsDeleteYoutubeRecord(row.id)),
  );
  for (const sec of secondaryRows) {
    await clientFsDeleteSectionRecord("secondary", sec.id);
  }
  for (const sub of subRows) {
    await clientFsDeleteSectionRecord("sub", sub.id);
  }
  await clientFsDeleteSectionRecord("main", id);
  return true;
}

// ─── Sub Sections ───────────────────────────────────────

/**
 * List the moderator's own sub sections, optionally filtered by main_section.
 *
 * توجيه شفّاف: إن كانت `main_section` هي القسم المضيف لـ OldApp، تُضاف
 * قائمة أقسام OldApp الرئيسيّة الحقيقيّة كأقسام فرعيّة افتراضيّة مع
 * الحفاظ على شكل البيانات المتوقّع من الواجهة.
 * @param {Object} params - { main_section?, search?, page? }
 */
export async function listMySubSections({
  main_section,
  search = "",
  page = 1,
  requireSearch = false,
  all: fetchAll = false,
} = {}) {
  if (shouldSkipListing({ requireSearch, search })) return emptyPage();
  // حالة Mshcat: إن كان الأب المحدّد قسمًا رئيسيًّا من Mshcat نعرض أقسامه
  // الفرعيّة حصرًا من مشروع Mshcat (لا خلط مع Nebras).
  if (isMshcatId(main_section)) {
    const parsed = parseMshcatId(main_section);
    if (parsed?.level === "main") {
      try {
        const subs = await listMshcatSubSections(parsed.docId);
        const adapted = subs.map(adaptMshcatSub);
        const filtered = applySectionFilters(adapted, { search, main_section });
        return paginate(filtered, fetchAll ? 1 : page, fetchAll ? (filtered.length || 1) : 10);
      } catch (err) {
        if (import.meta.env.DEV) {
          console.warn("[moderator] Mshcat sub list failed:", err);
        }
        return paginate([], page);
      }
    }
  }

  const all = await readLevel("sub");
  let merged = all;

  // لا يوجد فلتر → دمج أقسام Mshcat الفرعيّة كافّة (للإدارة/التعديل/الحذف).
  const noMainFilter =
    main_section === undefined || main_section === "" || main_section === null;
  if (noMainFilter && isMshcatConfigured()) {
    try {
      const { allSubs } = await classifyMshcatCategories();
      merged = [...merged, ...allSubs.map(adaptMshcatSub)];
    } catch (err) {
      if (import.meta.env.DEV) {
        console.warn("[moderator] Mshcat subs merge failed:", err);
      }
    }
  }

  if (isOldAppConfigured()) {
    const hostId = await getHostMainSectionId();
    if (hostId != null) {
      const filteringByHost =
        main_section !== undefined &&
        main_section !== "" &&
        main_section !== null &&
        sameSectionId(main_section, hostId);
      const noParentFilter =
        main_section === undefined ||
        main_section === "" ||
        main_section === null;

      if (filteringByHost || noParentFilter) {
        try {
          const oldMains = await listOldAppMainSections();
          const adapted = oldMains.map((m) => adaptOldAppMainAsSub(m, hostId));
          // نمرّر الأقسام الحقيقيّة من OldApp أوّلًا، ثمّ الأقسام المحلّية.
          merged = [...adapted, ...all];
        } catch (err) {
          if (import.meta.env.DEV) {
            console.warn("[moderator] OldApp main list merge failed:", err);
          }
        }
      }
    }
  }

  const filtered = applySectionFilters(merged, { search, main_section });
  return paginate(filtered, fetchAll ? 1 : page, fetchAll ? (filtered.length || 1) : 10);
}

/**
 * Create a sub section. يوجَّه تلقائيًّا إلى OldApp Firestore إن كان
 * الأب هو القسم المضيف — بدون أيّ مربّعات ربط في الواجهة.
 * @param {Object} data - { name, main_section, thumbnail? (File) }
 */
export async function createSubSection(data) {
  const parent = data?.main_section;

  // Mshcat: الأب قسم رئيسيّ من Mshcat → ننشئ فئة فرعيّة في نفس المجموعة
  // `categories` مع تعيين حقل الأبوّة على الـ docId الحقيقي.
  if (isMshcatId(parent)) {
    const parsed = parseMshcatId(parent);
    if (parsed?.level === "main") {
      let thumbUrl = null;
      if (data?.thumbnail instanceof File) {
        thumbUrl = await uploadSectionThumbnail(
          "sub-mshcat",
          Date.now(),
          data.thumbnail,
        );
      }
      const created = await createMshcatCategory({
        name: data?.name,
        thumbnailUrl: thumbUrl,
        parentDocId: parsed.docId,
      });
      return {
        id: `mshcat:sub:${created.id}`,
        name: String(data?.name || "").trim(),
        main_section: parent,
        is_listed: true,
        thumbnail: thumbUrl || null,
        created_at: new Date().toISOString(),
        __mshcatDocId: created.id,
        __mshcatLevel: "sub",
      };
    }
  }

  if (isOldAppConfigured() && parent !== undefined && parent !== null && parent !== "") {
    const hostId = await getHostMainSectionId();
    if (hostId != null && sameSectionId(parent, hostId)) {
      const thumbUrl = data?.thumbnail instanceof File
        ? await uploadSectionThumbnail("sub-oldapp", Date.now(), data.thumbnail)
        : null;
      return createOldAppMainSection({
        name: data?.name,
        thumbnailUrl: thumbUrl,
      });
    }
  }

  const id = makeSectionId();
  const thumbUrl = await uploadSectionThumbnail("sub", id, data?.thumbnail);
  const payload = {
    id,
    name: String(data?.name || "").trim(),
    main_section: Number(data?.main_section),
    is_listed: data?.is_listed ?? true,
    thumbnail: thumbUrl || null,
    created_at: new Date().toISOString(),
  };
  await clientFsSetSectionRecord("sub", id, payload);
  return payload;
}

/**
 * Update a sub section. يوجَّه تلقائيًّا إلى OldApp إن كان معرّفه افتراضيًّا.
 * @param {number|string} id
 * @param {Object} data
 */
export async function updateSubSection(id, data) {
  if (isMshcatId(id)) {
    const parsed = parseMshcatId(id);
    if (parsed?.level === "sub") {
      let thumbUrl;
      if (data?.thumbnail instanceof File) {
        thumbUrl = await uploadSectionThumbnail(
          "sub-mshcat",
          parsed.docId,
          data.thumbnail,
        );
      }
      await updateMshcatCategory(parsed.docId, {
        name: data?.name,
        ...(thumbUrl !== undefined ? { thumbnailUrl: thumbUrl } : {}),
      });
      return { id, name: data?.name, thumbnail: thumbUrl || null };
    }
  }

  if (isOldAppId(id)) {
    const parsed = parseOldAppId(id);
    if (parsed?.level === "main") {
      let thumbUrl;
      if (data?.thumbnail instanceof File) {
        thumbUrl = await uploadSectionThumbnail(
          "sub-oldapp",
          parsed.mainDocId,
          data.thumbnail,
        );
      }
      await updateOldAppMainSection(parsed.mainDocId, {
        name: data?.name,
        ...(thumbUrl !== undefined ? { thumbnailUrl: thumbUrl } : {}),
      });
      return { id, name: data?.name, thumbnail: thumbUrl || null };
    }
  }

  const current = await clientFsGetSectionRecord("sub", id);
  if (!current) throw new Error("Section not found");
  const patch = {
    ...(data?.name !== undefined ? { name: String(data.name).trim() } : {}),
    ...(data?.description !== undefined
      ? { description: String(data.description || "").trim() }
      : {}),
    ...(data?.is_listed !== undefined
      ? { is_listed: Boolean(data.is_listed) }
      : {}),
  };
  if (hasOwn(data, "main_section")) {
    patch.main_section = data.main_section || null;
  }
  if (data?.thumbnail instanceof File) {
    patch.thumbnail = await uploadSectionThumbnail("sub", id, data.thumbnail);
  }
  const next = { ...current, ...patch };
  await clientFsSetSectionRecord("sub", id, next);
  return next;
}

/**
 * Delete a sub section (يوجَّه إلى OldApp إن كان المعرّف افتراضيًّا).
 * @param {number|string} id
 */
export async function removeSubSection(id) {
  if (isMshcatId(id)) {
    const parsed = parseMshcatId(id);
    if (parsed?.level === "sub") {
      await deleteMshcatCategory(parsed.docId);
      return true;
    }
  }
  if (isOldAppId(id)) {
    const parsed = parseOldAppId(id);
    if (parsed?.level === "main") {
      await deleteOldAppMainSection(parsed.mainDocId, { cascade: true });
      return true;
    }
  }
  const subRow = await clientFsGetSectionRecord("sub", id);
  const secItems = await readLevel("secondary");
  const secondaryRows = secItems.filter((sec) => sameSectionId(sec.sub_section, id));
  const secondaryIds = secondaryRows.map((sec) => sec.id);
  const fileRows = await clientFsListFileRowsMerged();
  const videos = await clientFsListYoutubeRecords();
  // المحتوى يخصّ هذا القسم الفرعيّ إن طابقه مباشرةً أو طابق أحد أقسامه
  // الثانويّة. نقرأ من الميتاداتا وحقول المرآة العليا معًا (احترازًا).
  const belongsToSub = (row) => {
    const md = row?.metadata || {};
    const subMatch =
      sameSectionId(md.subsection, id) || sameSectionId(row?.subsection, id);
    const secMatch = secondaryIds.some(
      (secId) =>
        sameSectionId(md.secondary_subsection, secId) ||
        sameSectionId(row?.secondary_subsection, secId),
    );
    return subMatch || secMatch;
  };
  const fileRowsToDelete = fileRows.filter(belongsToSub);
  const videosToDelete = videos.filter(belongsToSub);
  await deleteStorageUrlsByValue([
    ...collectAssetUrls(subRow || {}),
    ...secondaryRows.flatMap(collectAssetUrls),
    ...fileRowsToDelete.flatMap(collectAssetUrls),
    ...videosToDelete.flatMap(collectAssetUrls),
  ]);
  await Promise.all(
    fileRowsToDelete.map((row) => clientFsDeleteFileMirrorBoth(row.fileId || row.id)),
  );
  await Promise.all(
    videosToDelete.map((row) => clientFsDeleteYoutubeRecord(row.id)),
  );
  for (const sec of secondaryRows) {
    await clientFsDeleteSectionRecord("secondary", sec.id);
  }
  await clientFsDeleteSectionRecord("sub", id);
  return true;
}

// ─── Secondary Sub Sections ────────────────────────────

/**
 * List secondary sub sections. إن كان `sub_section` معرّفًا افتراضيًّا
 * (`oldapp:main:<docId>`) نُرجع الأقسام الفرعيّة الحقيقيّة من OldApp
 * بعد تكييف شكلها.
 * @param {Object} params - { sub_section?, search?, page? }
 */
export async function listMySecondarySections({
  sub_section,
  search = "",
  page = 1,
  requireSearch = false,
  all: fetchAll = false,
} = {}) {
  if (shouldSkipListing({ requireSearch, search })) return emptyPage();
  // Mshcat: الأب قسم فرعي من Mshcat (mshcat:sub:*) → ثانويات الأطفال مباشرة.
  if (isMshcatId(sub_section)) {
    const parsed = parseMshcatId(sub_section);
    if (parsed?.level === "sub") {
      try {
        const secs = await listMshcatSecondarySections(parsed.docId);
        const adapted = secs.map(adaptMshcatSecondary);
        const filtered = applySectionFilters(adapted, { search, sub_section });
        return paginate(filtered, fetchAll ? 1 : page, fetchAll ? (filtered.length || 1) : 10);
      } catch (err) {
        if (import.meta.env.DEV) {
          console.warn("[moderator] Mshcat secondary list failed:", err);
        }
        return paginate([], page);
      }
    }
  }

  // حالة 1: استعراض ثانويات Main قديم محدد (oldapp:main:<id>)
  if (isOldAppId(sub_section)) {
    const parsed = parseOldAppId(sub_section);
    if (parsed?.level === "main") {
      try {
        const subs = await listOldAppSubSections(parsed.mainDocId);
        const adapted = subs.map((s) => adaptOldAppSubAsSecondary(s, parsed.mainDocId));
        const filtered = applySectionFilters(adapted, { search, sub_section });
        return paginate(filtered, fetchAll ? 1 : page, fetchAll ? (filtered.length || 1) : 10);
      } catch (err) {
        if (import.meta.env.DEV) {
          console.warn("[moderator] OldApp sub list failed:", err);
        }
        return paginate([], page);
      }
    }
  }

  // حالة 2: لا يوجد فلتر sub_section => ندمج ثانويات OldApp/Mshcat تلقائياً
  // لتظهر في نفس قائمة الإدارة (تعديل/حذف) مثل الأقسام الفرعية.
  const noSubFilter =
    sub_section === undefined || sub_section === "" || sub_section === null;
  if (noSubFilter && isMshcatConfigured()) {
    const all = await readLevel("secondary");
    let merged = all;
    try {
      const { allSecondaries } = await classifyMshcatCategories();
      merged = [...allSecondaries.map(adaptMshcatSecondary), ...merged];
    } catch (err) {
      if (import.meta.env.DEV) {
        console.warn("[moderator] Mshcat secondary merge failed:", err);
      }
    }
    if (isOldAppConfigured()) {
      try {
        const hostId = await getHostMainSectionId();
        if (hostId != null) {
          const oldMains = await listOldAppMainSections();
          const oldSecondaries = [];
          for (const m of oldMains) {
            const oldSubs = await listOldAppSubSections(m.id);
            oldSecondaries.push(
              ...oldSubs.map((s) => adaptOldAppSubAsSecondary(s, m.id)),
            );
          }
          merged = [...oldSecondaries, ...merged];
        }
      } catch (err) {
        if (import.meta.env.DEV) {
          console.warn("[moderator] OldApp secondary merge failed:", err);
        }
      }
    }
    const filtered = applySectionFilters(merged, { search, sub_section });
    return paginate(filtered, fetchAll ? 1 : page, fetchAll ? (filtered.length || 1) : 10);
  }
  if (noSubFilter && isOldAppConfigured()) {
    const all = await readLevel("secondary");
    let merged = all;
    try {
      const hostId = await getHostMainSectionId();
      if (hostId != null) {
        const oldMains = await listOldAppMainSections();
        const oldSecondaries = [];
        for (const m of oldMains) {
          const oldSubs = await listOldAppSubSections(m.id);
          oldSecondaries.push(
            ...oldSubs.map((s) => adaptOldAppSubAsSecondary(s, m.id)),
          );
        }
        merged = [...oldSecondaries, ...all];
      }
    } catch (err) {
      if (import.meta.env.DEV) {
        console.warn("[moderator] OldApp secondary merge failed:", err);
      }
    }
    const filtered = applySectionFilters(merged, { search, sub_section });
    return paginate(filtered, fetchAll ? 1 : page, fetchAll ? (filtered.length || 1) : 10);
  }

  // حالة 3: مسار RTDB العادي
  const all = await readLevel("secondary");
  const filtered = applySectionFilters(all, { search, sub_section });
  return paginate(filtered, fetchAll ? 1 : page, fetchAll ? (filtered.length || 1) : 10);
}

/**
 * Create a secondary sub section. إن كان الأب افتراضيًّا (oldapp:main:*)
 * نُنشئ قسمًا فرعيًّا حقيقيًّا في OldApp Firestore مباشرةً.
 */
export async function createSecondarySection(data) {
  const parent = data?.sub_section;

  // Mshcat: الأب قسم فرعيّ من Mshcat → ننشئ فئة من المستوى الثالث.
  if (isMshcatId(parent)) {
    const parsed = parseMshcatId(parent);
    if (parsed?.level === "sub") {
      let thumbUrl = null;
      if (data?.thumbnail instanceof File) {
        thumbUrl = await uploadSectionThumbnail(
          "secondary-mshcat",
          Date.now(),
          data.thumbnail,
        );
      }
      const created = await createMshcatCategory({
        name: data?.name,
        thumbnailUrl: thumbUrl,
        parentDocId: parsed.docId,
      });
      return {
        id: `mshcat:sec:${created.id}`,
        name: String(data?.name || "").trim(),
        sub_section: parent,
        is_listed: true,
        thumbnail: thumbUrl || null,
        created_at: new Date().toISOString(),
        __mshcatDocId: created.id,
        __mshcatLevel: "sec",
      };
    }
  }

  if (isOldAppId(parent)) {
    const parsed = parseOldAppId(parent);
    if (parsed?.level === "main") {
      let thumbUrl = null;
      if (data?.thumbnail instanceof File) {
        thumbUrl = await uploadSectionThumbnail(
          "secondary-oldapp",
          Date.now(),
          data.thumbnail,
        );
      }
      return createOldAppSubSection(parsed.mainDocId, {
        name: data?.name,
        thumbnailUrl: thumbUrl,
      });
    }
  }

  const id = makeSectionId();
  const thumbUrl = await uploadSectionThumbnail(
    "secondary",
    id,
    data?.thumbnail,
  );
  const payload = {
    id,
    name: String(data?.name || "").trim(),
    sub_section: Number(data?.sub_section),
    is_listed: data?.is_listed ?? true,
    thumbnail: thumbUrl || null,
    created_at: new Date().toISOString(),
  };
  await clientFsSetSectionRecord("secondary", id, payload);
  return payload;
}

export async function updateSecondarySection(id, data) {
  if (isMshcatId(id)) {
    const parsed = parseMshcatId(id);
    if (parsed?.level === "sec") {
      let thumbUrl;
      if (data?.thumbnail instanceof File) {
        thumbUrl = await uploadSectionThumbnail(
          "secondary-mshcat",
          parsed.docId,
          data.thumbnail,
        );
      }
      await updateMshcatCategory(parsed.docId, {
        name: data?.name,
        ...(thumbUrl !== undefined ? { thumbnailUrl: thumbUrl } : {}),
      });
      return { id, name: data?.name, thumbnail: thumbUrl || null };
    }
  }

  if (isOldAppId(id)) {
    const parsed = parseOldAppId(id);
    if (parsed?.level === "sub") {
      let thumbUrl;
      if (data?.thumbnail instanceof File) {
        thumbUrl = await uploadSectionThumbnail(
          "secondary-oldapp",
          parsed.subDocId,
          data.thumbnail,
        );
      }
      await updateOldAppSubSection(parsed.mainDocId, parsed.subDocId, {
        name: data?.name,
        ...(thumbUrl !== undefined ? { thumbnailUrl: thumbUrl } : {}),
      });
      return { id, name: data?.name, thumbnail: thumbUrl || null };
    }
  }

  const current = await clientFsGetSectionRecord("secondary", id);
  if (!current) throw new Error("Section not found");
  const patch = {
    ...(data?.name !== undefined ? { name: String(data.name).trim() } : {}),
    ...(data?.description !== undefined
      ? { description: String(data.description || "").trim() }
      : {}),
    ...(data?.is_listed !== undefined
      ? { is_listed: Boolean(data.is_listed) }
      : {}),
  };
  if (hasOwn(data, "sub_section")) {
    patch.sub_section = data.sub_section || null;
  }
  if (data?.thumbnail instanceof File) {
    patch.thumbnail = await uploadSectionThumbnail(
      "secondary",
      id,
      data.thumbnail,
    );
  }
  const next = { ...current, ...patch };
  await clientFsSetSectionRecord("secondary", id, next);
  return next;
}

export async function removeSecondarySection(id) {
  if (isMshcatId(id)) {
    const parsed = parseMshcatId(id);
    if (parsed?.level === "sec") {
      await deleteMshcatCategory(parsed.docId);
      return true;
    }
  }
  if (isOldAppId(id)) {
    const parsed = parseOldAppId(id);
    if (parsed?.level === "sub") {
      await deleteOldAppSubSection(parsed.mainDocId, parsed.subDocId, { cascade: true });
      return true;
    }
  }
  const secRow = await clientFsGetSectionRecord("secondary", id);
  const fileRows = await clientFsListFileRowsMerged();
  const videos = await clientFsListYoutubeRecords();
  // المحتوى يخصّ هذا القسم الثانويّ (من الميتاداتا أو حقل المرآة العليا).
  const belongsToSecondary = (row) =>
    sameSectionId(row?.metadata?.secondary_subsection, id) ||
    sameSectionId(row?.secondary_subsection, id);
  const fileRowsToDelete = fileRows.filter(belongsToSecondary);
  const videosToDelete = videos.filter(belongsToSecondary);
  await deleteStorageUrlsByValue([
    ...collectAssetUrls(secRow || {}),
    ...fileRowsToDelete.flatMap(collectAssetUrls),
    ...videosToDelete.flatMap(collectAssetUrls),
  ]);
  await Promise.all(
    fileRowsToDelete.map((row) => clientFsDeleteFileMirrorBoth(row.fileId || row.id)),
  );
  await Promise.all(
    videosToDelete.map((row) => clientFsDeleteYoutubeRecord(row.id)),
  );
  await clientFsDeleteSectionRecord("secondary", id);
  return true;
}

// ─── R2 File Content ────────────────────────────────────

/**
 * List moderator's own R2 files with optional filters.
 */
export async function listMyFiles({
  search = "",
  subsection,
  main_section,
  secondary_subsection,
  content_type,
  upload_type,
  is_listed,
  metadata__is_listed,
  page = 1,
  requireSearch = false,
} = {}) {
  const hasActiveFilter =
    (main_section !== undefined && main_section !== "") ||
    (subsection !== undefined && subsection !== "") ||
    (secondary_subsection !== undefined && secondary_subsection !== "") ||
    (content_type !== undefined && content_type !== "") ||
    (upload_type !== undefined && upload_type !== "") ||
    metadata__is_listed !== undefined ||
    is_listed !== undefined;
  if (shouldSkipListing({ requireSearch, search, hasActiveFilter })) return emptyPage();
  resetPartialFailures();
  let list = await clientFsListFileRowsMerged();
  const subMap = await clientFsReadSectionsSubMap();
  const listedFilter = metadata__is_listed ?? is_listed;

  if (isOldAppConfigured()) {
    try {
      const hostId = await getHostMainSectionId();
      const shouldMergeOldApp =
        main_section === undefined || main_section === "" || sameSectionId(main_section, hostId);
      if (hostId != null && shouldMergeOldApp) {
        const oldMains = await externalCache.get("oldapp:mains", () =>
          listOldAppMainSections(),
        );
        const allLessons = await Promise.all(
          oldMains.map(async (m) => {
            try {
              const oldSubs = await externalCache.get(
                `oldapp:subs:${m.id}`,
                () => listOldAppSubSections(m.id),
              );
              const batches = await Promise.all(
                oldSubs.map((s) =>
                  externalCache
                    .get(`oldapp:lessons:${m.id}:${s.id}`, () =>
                      listOldAppLessonsBySub(m.id, s.id),
                    )
                    .then((lessons) =>
                      lessons.map((lesson) => ({ lesson, mainDocId: m.id, subDocId: s.id })),
                    )
                    .catch((err) => {
                      recordPartialFailure(`OldApp lessons ${m.id}/${s.id}`, err);
                      return [];
                    }),
                ),
              );
              return batches.flat();
            } catch (err) {
              recordPartialFailure(`OldApp subs ${m.id}`, err);
              return [];
            }
          }),
        );
        for (const entry of allLessons.flat()) {
          const asFile = adaptOldAppLessonAsFile(entry.lesson, {
            mainDocId: entry.mainDocId,
            subDocId: entry.subDocId,
          });
          if (String(asFile?.metadata?.content_type) !== "youtube") {
            list.push(asFile);
          }
        }
      }
    } catch (err) {
      recordPartialFailure("OldApp files merge", err);
    }
  }

  // دمج ملفات Mshcat (books غير يوتيوب).
  if (isMshcatConfigured()) {
    try {
      const books = await externalCache.get("mshcat:books:all", () =>
        listAllMshcatBooks(),
      );
      for (const b of books) {
        const f = adaptMshcatBookAsFile(b);
        const t = String(f?.metadata?.content_type || "").toLowerCase();
        const url = String(f?.file_url || "").toLowerCase();
        const isYt = t === "youtube" || url.includes("youtube.com") || url.includes("youtu.be");
        if (!isYt) list.push(f);
      }
    } catch (err) {
      recordPartialFailure("Mshcat files merge", err);
    }
  }

  list = list.map((item) => {
    const createdAt =
      item?.metadata?.created_at || item?.createdAt || new Date().toISOString();
    const engagement = pickEngagementStats(item);
    return {
      id: item.fileId || item.id,
      filename: item.filename || "untitled",
      file_type: item.fileType || item.file_type || "",
      file_size: Number(item.fileSize || item.file_size || 0),
      file_url: item.downloadUrl || item.file_url || "",
      upload_type: item.upload_type || "firebase",
      upload_status: item.upload_status || "completed",
      storage_path: item.storagePath || item.storage_path || "",
      engagement,
      metadata: {
        ...(item.metadata || {}),
        created_at: createdAt,
      },
      ...(item.__mshcatBookDocId ? { __mshcatBookDocId: item.__mshcatBookDocId } : {}),
      ...(item.__mshcatCategoryDocId ? { __mshcatCategoryDocId: item.__mshcatCategoryDocId } : {}),
      ...(item.__oldappContentDocId ? { __oldappContentDocId: item.__oldappContentDocId } : {}),
      ...(item.__oldappMainDocId ? { __oldappMainDocId: item.__oldappMainDocId } : {}),
      ...(item.__oldappSubDocId ? { __oldappSubDocId: item.__oldappSubDocId } : {}),
    };
  });

  // ملفات Shadow الناتجة عن رفع محتوى OldApp تُخفى من القائمة لأن العنصر
  // الحقيقي يُدار من Firestore عبر oldapp:lesson:*.
  list = list.filter((item) => {
    const sub = String(item?.metadata?.subsection || "");
    const sec = String(item?.metadata?.secondary_subsection || "");
    return !(sub.startsWith("oldapp:main:") && sec.startsWith("oldapp:sub:"));
  });

  const fileTokens = tokenize(search);
  if (fileTokens.length > 0) {
    list = filterAndRank(list, fileTokens, (item) => [
      item?.metadata?.title || "",
      item?.metadata?.description || "",
      item?.metadata?.author || "",
      item?.filename || "",
      item?.file_url || "",
    ]);
  }
  if (subsection !== undefined && subsection !== "") {
    list = list.filter(
      (item) => sameSectionId(item?.metadata?.subsection, subsection),
    );
  }
  if (secondary_subsection !== undefined && secondary_subsection !== "") {
    list = list.filter(
      (item) =>
        sameSectionId(item?.metadata?.secondary_subsection, secondary_subsection),
    );
  }
  if (main_section !== undefined && main_section !== "") {
    list = list.filter((item) => {
      const subId = item?.metadata?.subsection;
      const sub = subMap[String(subId)];
      return (
        sameSectionId(sub?.main_section, main_section) ||
        sameSectionId(item?.__oldappMainDocId, parseOldAppId(subId)?.mainDocId)
      );
    });
  }
  if (content_type) {
    list = list.filter(
      (item) =>
        String(item?.metadata?.content_type || "") === String(content_type),
    );
  }
  if (upload_type) {
    list = list.filter(
      (item) => String(item?.upload_type || "") === String(upload_type),
    );
  }
  if (listedFilter !== undefined && listedFilter !== "") {
    const boolVal = listedFilter === true || listedFilter === "true";
    list = list.filter(
      (item) => Boolean(item?.metadata?.is_listed ?? true) === boolVal,
    );
  }

  list.sort((a, b) => {
    const ta = new Date(a?.metadata?.created_at || 0).getTime();
    const tb = new Date(b?.metadata?.created_at || 0).getTime();
    return tb - ta;
  });
  return paginate(list, page);
}

/**
 * Initiate a file upload. Metadata is sent as a JSON string field.
 * @param {Object} opts - { file_size, file_type, filename, metadata: {...}, thumbnail? (File) }
 */
export async function initiateFileUpload({
  file_size,
  file_type,
  filename,
  metadata,
  thumbnail,
}) {
  // Backend expects dot-notation fields: metadata.title, metadata.subsection, etc.
  const fd = buildFormData({
    filename,
    file_size,
    file_type,
    metadata, // buildFormData recurses into nested objects → metadata.title, metadata.subsection …
    ...(thumbnail instanceof File ? { thumbnail } : {}),
  });
  const res = await apiPostForm("/api/content/files/", fd);
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(JSON.stringify(err));
  }
  return res.json();
}

/** Get presigned upload URL for a file (or next part). */
export async function getFileUploadUrl(fileId) {
  const res = await apiPost(`/api/content/files/${fileId}/upload-url/`, {});
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.detail || "Failed to get upload URL");
  }
  return res.json();
}

/** Register a completed part (multipart only). */
export async function registerPart({ multipart_upload, part_number, etag }) {
  const res = await apiPost("/api/content/parts/", {
    multipart_upload,
    part_number,
    etag,
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.detail || "Failed to register part");
  }
  return res.json();
}

/** Complete a file upload (both single and multipart). */
export async function completeFileUpload(fileId) {
  const res = await apiPost(`/api/content/files/${fileId}/complete/`, {});
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.detail || "Failed to complete upload");
  }
  return res.json();
}

/**
 * يحوّل سجل رفع Firebase (fileId) إلى درس حقيقي في OldApp lessons
 * عند اختيار شجرة OldApp في شاشة رفع الملفات.
 */
export async function mirrorUploadedFileToOldAppLesson({
  fileId,
  subsectionId,
  secondarySubsectionId,
  fallbackMetadata = {},
} = {}) {
  if (!fileId) throw new Error("fileId مطلوب.");
  const parsedSec = isOldAppId(secondarySubsectionId)
    ? parseOldAppId(secondarySubsectionId)
    : null;
  const parsedSub = isOldAppId(subsectionId) ? parseOldAppId(subsectionId) : null;
  const target =
    parsedSec?.level === "sub"
      ? parsedSec
      : parsedSub?.level === "sub"
        ? parsedSub
        : null;
  if (!target) return null;

  const row = await clientFsGetFileRow(fileId);
  if (!row || Object.keys(row).length === 0) {
    throw new Error("Uploaded file record not found.");
  }
  const metadata = { ...(row.metadata || {}), ...(fallbackMetadata || {}) };
  const sourceUrl =
    row.downloadUrl || row.file_url || row.sourceUrl || metadata.file_url || "";

  const created = await createOldAppLesson({
    mainDocId: target.mainDocId,
    subDocId: target.subDocId,
    title: metadata.title || row.filename || fileId,
    description: metadata.description || "",
    author: metadata.author || "",
    contentType: metadata.content_type || "document",
    sourceUrl,
    thumbnail: metadata.thumbnail || null,
  });
  return { id: `oldapp:lesson:${created.id}` };
}

/**
 * يحوّل سجل رفع Firebase (fileId) إلى كتاب حقيقي في Mshcat `books`
 * عند اختيار شجرة Mshcat في شاشة رفع الملفات.
 */
export async function mirrorUploadedFileToMshcatBook({
  fileId,
  subsectionId,
  secondarySubsectionId,
  fallbackMetadata = {},
} = {}) {
  if (!fileId) throw new Error("fileId مطلوب.");
  const target = detectMshcatContentTarget({
    subsectionId,
    secondarySubsectionId,
  });
  if (!target) return null;

  const row = await clientFsGetFileRow(fileId);
  if (!row || Object.keys(row).length === 0) {
    throw new Error("Uploaded file record not found.");
  }
  const metadata = { ...(row.metadata || {}), ...(fallbackMetadata || {}) };
  const sourceUrl =
    row.downloadUrl || row.file_url || row.sourceUrl || metadata.file_url || "";

  const created = await createMshcatBook({
    categoryDocId: target.docId,
    title: metadata.title || row.filename || fileId,
    description: metadata.description || "",
    author: metadata.author || "",
    contentType: metadata.content_type || "document",
    sourceUrl,
    thumbnail: metadata.thumbnail || null,
  });
  return { id: `mshcat:book:${created.id}` };
}

/** Update file metadata (PATCH). */
export async function updateFile(fileId, data) {
  const mshBook = parseMshcatBookId(fileId);
  if (mshBook) {
    const patch = {};
    if (hasOwn(data?.metadata || {}, "title")) patch.title = asTrimmedString(data.metadata.title);
    if (hasOwn(data?.metadata || {}, "description")) {
      patch.description = asTrimmedString(data.metadata.description);
    }
    if (hasOwn(data?.metadata || {}, "author")) patch.author = asTrimmedString(data.metadata.author);
    if (hasOwn(data?.metadata || {}, "content_type")) {
      patch.contentType = asTrimmedString(data.metadata.content_type);
    }
    if (data?.thumbnail instanceof File) {
      patch.thumbnail = await uploadSectionThumbnail(
        "files-mshcat",
        mshBook.bookDocId,
        data.thumbnail,
      );
    } else if (hasOwn(data?.metadata || {}, "thumbnail")) {
      patch.thumbnail = data.metadata.thumbnail;
    }
    const wantsMove =
      hasOwn(data?.metadata || {}, "subsection") ||
      hasOwn(data?.metadata || {}, "secondary_subsection");
    if (wantsMove) {
      const target = detectMshcatContentTarget({
        subsectionId: data?.metadata?.subsection,
        secondarySubsectionId: data?.metadata?.secondary_subsection,
      });
      if (target?.docId) patch.categoryDocId = target.docId;
    }
    if (data?.file instanceof File) {
      const uploaded = await smartUpload({
        file: data.file,
        target: "mshcat",
        folder: `content/files/${mshBook.bookDocId}`,
        filename: `${Date.now()}_${String(data.file.name || "file").replace(/[^\w.\-]/g, "_")}`,
      });
      patch.sourceUrl = uploaded.url;
    }
    await updateMshcatBook(mshBook.bookDocId, patch);
    return { id: fileId };
  }

  const oldContent = parseOldAppContentId(fileId);
  if (oldContent) {
    const patch = {};
    if (hasOwn(data?.metadata || {}, "title")) patch.title = asTrimmedString(data.metadata.title);
    if (hasOwn(data?.metadata || {}, "description")) {
      patch.description = asTrimmedString(data.metadata.description);
    }
    if (hasOwn(data?.metadata || {}, "author")) patch.author = asTrimmedString(data.metadata.author);
    if (hasOwn(data?.metadata || {}, "content_type")) {
      patch.contentType = asTrimmedString(data.metadata.content_type);
    }
    if (data?.thumbnail instanceof File) {
      patch.thumbnail = await uploadSectionThumbnail(
        "files-oldapp",
        oldContent.lessonDocId,
        data.thumbnail,
      );
    } else if (hasOwn(data?.metadata || {}, "thumbnail")) {
      patch.thumbnail = data.metadata.thumbnail;
    }
    if (data?.file instanceof File) {
      const uploaded = await smartUpload({
        file: data.file,
        target: "oldapp",
        folder: `content/files/${oldContent.lessonDocId}`,
        filename: `${Date.now()}_${String(data.file.name || "file").replace(/[^\w.\-]/g, "_")}`,
      });
      patch.sourceUrl = uploaded.url;
    }
    await updateOldAppLesson(oldContent.lessonDocId, patch);
    return { id: fileId };
  }

  const current = await clientFsGetFileRow(fileId);
  if (!current || Object.keys(current).length === 0) throw new Error("File not found");
  const nextMetadata = mergeContentMetadataPreservingHierarchy(
    current.metadata || {},
    data?.metadata || {},
  );
  const next = {
    ...current,
    metadata: nextMetadata,
  };
  if (data?.thumbnail instanceof File) {
    next.metadata.thumbnail = await uploadSectionThumbnail("files", fileId, data.thumbnail);
  }
  if (data?.file instanceof File) {
    const uploaded = await smartUpload({
      file: data.file,
      target: "nebras",
      folder: `content/files/${fileId}`,
      filename: `${Date.now()}_${String(data.file.name || "file").replace(/[^\w.\-]/g, "_")}`,
    });
    next.filename = data.file.name;
    next.fileType = data.file.type || current.fileType || "";
    next.fileSize = Number(data.file.size || 0);
    next.downloadUrl = uploaded.url;
    next.file_url = uploaded.url;
    next.sourceUrl = uploaded.url;
    next.storagePath = uploaded.path;
    if (current?.storagePath && current.storagePath !== uploaded.path) {
      try {
        const storage = sectionsStorage();
        await deleteObject(storageRef(storage, current.storagePath));
      } catch {}
    }
  }
  // ── نقل الأقسام (move): إن طلب المستخدم تغيير أيّ مستوى قسم، نُعيد حساب
  // «المسار القانونيّ» كاملًا — معرّفات + أسماء محدَّثة + تصفير المستويات
  // الأعمق غير المُختارة — كي لا يبقى أيّ أثر للقسم القديم لا في الميتاداتا
  // ولا في حقول المرآة العليا (التي يقرأها التطبيق أوّلًا). تعديلُ الاسم وحده
  // دون لمس الأقسام لا يدخل هنا إطلاقًا، فيبقى القسم كما هو تمامًا.
  const incomingMeta = data?.metadata || {};
  const wantsMove =
    hasOwn(incomingMeta, "main_section") ||
    hasOwn(incomingMeta, "subsection") ||
    hasOwn(incomingMeta, "secondary_subsection");
  let trail = null;
  if (wantsMove) {
    trail = await resolveContentSectionTrail({
      main_section: next.metadata.main_section,
      subsection: next.metadata.subsection,
      secondary_subsection: next.metadata.secondary_subsection,
    });
    // المحتوى يجب أن يبقى ضمن قسم فرعيّ صالح كي يظهر في التطبيق (يُطابق
    // شرط الرفع). نمنع نقله إلى قسم رئيسيّ بلا فرعيّ فيصير يتيمًا/مخفيًّا.
    if (!trail.subsection) {
      throw new Error(
        "اختر قسمًا فرعيًّا صالحًا قبل الحفظ — لا يمكن نقل المحتوى إلى قسم رئيسي بلا قسم فرعي.",
      );
    }
    next.metadata.main_section = trail.main_section;
    next.metadata.main_section_id = trail.main_section_id;
    next.metadata.main_section_name = trail.main_section_name;
    next.metadata.subsection = trail.subsection;
    next.metadata.subsection_name = trail.subsection_name;
    next.metadata.secondary_subsection = trail.secondary_subsection;
    next.metadata.secondary_subsection_name = trail.secondary_subsection_name;
  }

  Object.assign(next, buildUploadMirrorFields(next, next.metadata));

  if (trail) {
    // فرض القيم القانونيّة على حقول المرآة العليا (تتجاوز fallback الـ ??
    // الذي قد يُبقي معرّف/اسم قسمٍ قديم عند تفريغ مستوى أثناء النقل).
    next.main_section = trail.main_section;
    next.main_section_id = trail.main_section_id;
    next.main_section_name = trail.main_section_name;
    next.subsection = trail.subsection;
    next.subsection_name = trail.subsection_name;
    next.secondary_subsection = trail.secondary_subsection;
    next.secondary_subsection_name = trail.secondary_subsection_name;
  }

  await clientFsWriteFileMirrorBoth(fileId, next);
  return next;
}

/** Delete a file. */
export async function removeFile(fileId) {
  const mshBook = parseMshcatBookId(fileId);
  if (mshBook) {
    await deleteMshcatBook(mshBook.bookDocId);
    return true;
  }
  const oldContent = parseOldAppContentId(fileId);
  if (oldContent) {
    await deleteOldAppLesson(oldContent.lessonDocId);
    return true;
  }

  const item = await clientFsGetFileRow(fileId);
  if (!item || Object.keys(item).length === 0) return true;

  // ── محتوى مصدره Internet Archive ─────────────────────────────
  // إن كان العنصر مستورَداً آليّاً من IA (يحمل __provider/__iaIdentifier)،
  // فالحذف المجرّد لا يكفي: المحرّك التلقائيّ يُعيد استيراده لأنّ المعرّف
  // لا يُسجَّل في قائمة الحظر. نُفوّض الحذف للمسار المخصّص (DMCA endpoint)
  // الذي يحذف الوثيقتين + ملفّ Storage إن وُجد + يُضيف __iaIdentifier إلى
  // ia_library_dmca_blacklist (+ permanent failure) فيمنع رجوعه نهائيّاً.
  // ⚠️ نستدعيه قبل أيّ حذف محلّيّ كي تبقى الوثيقة موجودة حين يقرأ الـ
  // endpoint منها __iaIdentifier (يستنتجه من الوثيقة لا من جسم الطلب).
  // المحتوى المرفوع يدويّاً (بلا هذه العلامات) لا يمرّ من هنا إطلاقاً.
  const isIaItem =
    item?.__provider === "internet_archive" ||
    Boolean(String(item?.__iaIdentifier || "").trim());
  if (isIaItem) {
    await authedJson("/api/admin/internet-archive/dmca", {
      method: "POST",
      body: { fileId: String(fileId), reason: "manual_delete_dashboard" },
    });
    return true;
  }

  await deleteStorageUrlsByValue(collectAssetUrls(item));
  if (item?.storagePath) {
    try {
      const storage = sectionsStorage();
      await deleteObject(storageRef(storage, item.storagePath));
    } catch {
      // Continue deleting DB entry even if file already missing in storage.
    }
  }
  await clientFsDeleteFileMirrorBoth(fileId);
  return true;
}

// ─── Dashboard Statistics ──────────────────────────────

/**
 * Get aggregate total counts of content items, YouTube videos, and sections created by the moderator.
 * @returns {Promise<Object>}
 */
export async function getModeratorTotals() {
  const res = await apiGet("/api/dashboard-statistics/moderator/totals/");
  if (!res.ok) throw new Error("Failed to fetch moderator totals");
  return res.json();
}

/**
 * Get content distribution uploaded by the moderator.
 * @returns {Promise<Object>}
 */
export async function getModeratorContentDistribution() {
  const res = await apiGet(
    "/api/dashboard-statistics/moderator/content-distribution/",
  );
  if (!res.ok)
    throw new Error("Failed to fetch moderator content distribution");
  return res.json();
}

/**
 * Get daily upload counts by content type for the last 30 days specific to the moderator.
 * @returns {Promise<{data: Array}>}
 */
export async function getModeratorContentAddedChart() {
  const res = await apiGet(
    "/api/dashboard-statistics/moderator/content-added-chart/",
  );
  if (!res.ok) throw new Error("Failed to fetch moderator content added chart");
  return res.json();
}
