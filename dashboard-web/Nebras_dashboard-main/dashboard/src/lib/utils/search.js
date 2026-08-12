/**
 * ═══════════════════════════════════════════════════════════════════
 * Search Utilities — وحدة بحث عربيّة-إنكليزيّة شاملة
 * ═══════════════════════════════════════════════════════════════════
 *
 * تُقدّم هذه الوحدة طبقة موحَّدة لـ:
 *   • التطبيع (Normalization): أ/إ/آ/ا، ى/ي، ة/ه، ؤ/ئ، تشكيل، tatweel، lowercase.
 *   • التجزئة (Tokenization): تقسيم الاستعلام إلى كلمات AND.
 *   • المطابقة (Matching): كلّ الكلمات يجب أن توجد (AND) عبر حقول العنصر.
 *   • التقييم (Scoring): تطابق العنوان > الوصف > المؤلف/الرابط؛ prefix > contains.
 *   • الإبراز (Highlight): تلوين الكلمات المطابقة داخل النصوص.
 *   • ذاكرة TTL (Memoization): تقليل ضغط القراءات على Firebase/Firestore.
 *   • Debounce: إدخال المستخدم لا يتحوّل إلى ضغط شبكي على كلّ حرف.
 *
 * هذه الأدوات نقيّة (لا تعتمد على Svelte/DOM) لضمان قابليّة الاختبار
 * والاستعمال من أيّ طبقة (UI أو Engine).
 */

// ───────────────────── 1) Normalization ─────────────────────

/**
 * يُطبّع النصّ العربي والإنكليزي لمقارنة معناها لا شكلها:
 *   - lowercase
 *   - إزالة التشكيل: ً ٌ ٍ َ ُ ِ ّ ْ ٰ ۭ
 *   - إزالة الـ tatweel (ـ)
 *   - توحيد الهمزات: أ/إ/آ/ٱ → ا
 *   - توحيد الياء/الألف المقصورة: ى → ي
 *   - توحيد التاء المربوطة: ة → ه
 *   - توحيد الواو: ؤ → و
 *   - توحيد الياء: ئ → ي
 *   - ضغط المسافات المتعدّدة
 *
 * @param {string} s
 * @returns {string}
 */
export function normalizeArabic(s) {
  if (s === undefined || s === null) return "";
  let out = String(s);
  // Lowercase (for Latin chars)
  out = out.toLowerCase();
  // Remove Arabic diacritics (harakat) and Quranic marks
  out = out.replace(/[\u064B-\u0652\u0670\u06D6-\u06ED]/g, "");
  // Remove tatweel
  out = out.replace(/\u0640/g, "");
  // Normalize hamza variants on alef → bare alef
  out = out.replace(/[\u0622\u0623\u0625\u0671]/g, "\u0627"); // آ أ إ ٱ → ا
  // Alef maksura → ya
  out = out.replace(/\u0649/g, "\u064A"); // ى → ي
  // Ta marbuta → ha
  out = out.replace(/\u0629/g, "\u0647"); // ة → ه
  // Hamza on waw → waw
  out = out.replace(/\u0624/g, "\u0648"); // ؤ → و
  // Hamza on ya → ya
  out = out.replace(/\u0626/g, "\u064A"); // ئ → ي
  // Collapse whitespace
  out = out.replace(/\s+/g, " ").trim();
  return out;
}

// ───────────────────── 2) Tokenization ─────────────────────

/**
 * يقطع الاستعلام إلى tokens بعد التطبيع.
 * يُرجع قائمة tokens فريدة وبأطوال ≥ 1 (الفلترة على الطول تتمّ في الطبقة الأعلى).
 *
 * @param {string} query
 * @returns {string[]}
 */
export function tokenize(query) {
  const norm = normalizeArabic(query);
  if (!norm) return [];
  // نقسم على المسافات والـ punctuation العربي والإنكليزي
  const parts = norm.split(/[\s,./\\|~`!@#$%^&*()_+\-={}\[\]:;"'<>?،؛؟]+/);
  const seen = new Set();
  const out = [];
  for (const p of parts) {
    if (!p) continue;
    if (seen.has(p)) continue;
    seen.add(p);
    out.push(p);
  }
  return out;
}

// ───────────────────── 3) Matching ─────────────────────

/**
 * يفحص إذا كانت كلّ tokens موجودة في أيّ من الحقول (OR across fields,
 * لكنّ AND across tokens: كلّ token يجب أن يُطابَق في حقلٍ ما على الأقلّ).
 *
 * @param {string[]} fields - مصفوفة نصوص الحقول الخام (قبل التطبيع).
 * @param {string[]} tokens - tokens مُطبّعة.
 * @returns {boolean}
 */
export function matchesAllTokens(fields, tokens) {
  if (!tokens || tokens.length === 0) return true;
  const normalizedFields = (fields || []).map((f) => normalizeArabic(f));
  for (const token of tokens) {
    let found = false;
    for (const f of normalizedFields) {
      if (f.includes(token)) {
        found = true;
        break;
      }
    }
    if (!found) return false;
  }
  return true;
}

// ───────────────────── 4) Scoring ─────────────────────

/**
 * يحسب درجة صِلة (relevance score) بناءً على:
 *   - ترتيب الحقل (الحقل الأوّل له أعلى وزن).
 *   - نوع المطابقة: exact > prefix > word-boundary > contains.
 *   - عدد الـ tokens المُطابَقة (للحاشية، كلّها يُفترض أنها مطابقة).
 *
 * أوزان ثابتة اخترناها لتتناسب مع غطاء الحقول المعتاد:
 *   field[0] (title/name): ×100
 *   field[1] (description): ×40
 *   field[2] (author/filename): ×20
 *   field[3+] (url/other): ×10
 *
 * @param {string[]} fields - نصوص الحقول بنفس الترتيب المُستخدَم في matches.
 * @param {string[]} tokens
 * @returns {number}
 */
export function scoreMatch(fields, tokens) {
  if (!tokens || tokens.length === 0) return 0;
  const fieldWeights = [100, 40, 20, 10, 5, 5, 5, 5];
  let total = 0;
  for (let i = 0; i < (fields || []).length; i++) {
    const raw = fields[i];
    if (!raw) continue;
    const norm = normalizeArabic(raw);
    const weight = fieldWeights[i] ?? 5;
    for (const token of tokens) {
      if (!norm.includes(token)) continue;
      let bonus = 1;
      if (norm === token) bonus = 4; // exact
      else if (norm.startsWith(token)) bonus = 3; // prefix
      else if (new RegExp(`(^|[\\s\\-_/])${escapeRegex(token)}`).test(norm)) bonus = 2; // word boundary
      total += weight * bonus;
    }
  }
  return total;
}

function escapeRegex(s) {
  return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// ───────────────────── 5) Rank + Filter ─────────────────────

/**
 * يُطبّق فلترة AND ثمّ فرزًا بحسب الصِلة. إن لم تكن هناك tokens يُعيد
 * القائمة بدون تغيير ترتيبها.
 *
 * @template T
 * @param {T[]} list
 * @param {string[]} tokens
 * @param {(item: T) => string[]} extractFields - يُعيد الحقول النصيّة مرتّبة بالأهميّة.
 * @returns {T[]}
 */
export function filterAndRank(list, tokens, extractFields) {
  if (!Array.isArray(list)) return [];
  if (!tokens || tokens.length === 0) return list;
  const matched = [];
  for (const item of list) {
    const fields = extractFields(item) || [];
    if (!matchesAllTokens(fields, tokens)) continue;
    const score = scoreMatch(fields, tokens);
    matched.push({ item, score });
  }
  matched.sort((a, b) => b.score - a.score);
  return matched.map((x) => x.item);
}

// ───────────────────── 6) Highlight ─────────────────────

/**
 * يُغلّف الكلمات المطابقة بـ `<mark class="hl">` داخل النصّ.
 * يعمل على النسخة الأصليّة (غير المُطبّعة) للحفاظ على الشكل المرئي.
 * يُعيد سلسلة HTML آمنة (يُفلتر HTML الأصلي قبل الإبراز).
 *
 * @param {string} text
 * @param {string[]} tokens - بعد التطبيع.
 * @returns {string} HTML
 */
export function highlightMatches(text, tokens) {
  if (text === undefined || text === null) return "";
  const raw = String(text);
  if (!tokens || tokens.length === 0) return escapeHtml(raw);

  // نبني خريطة: كلّ حرف في الأصل يُقابل حرفًا في المُطبّع؟ لا، التطبيع
  // يُغيّر الأطوال. أبسط حلّ موثوق: نفحص كلّ عنصر نصّي بعد escape وقبل
  // الإدراج، ونطابق tokens بعد تطبيعها مع نسخة مطبَّعة بنفس ترتيب
  // الأحرف — لكنّ تغيّر الطول يكسر الفهرسة. لذا نعتمد استراتيجيّة
  // براغماتيّة: نطابق tokens على النصّ الأصلي بعد تطبيق lowercase فقط
  // (لأنّ معظم tokens لن تحتوي حروفًا تغيّرت في التطبيع). هذا قد يفوّت
  // إبراز بعض الصيَغ (مثل همزة مختلفة) لكنّه أسرع وأبسط بلا مخاطر.
  const escaped = escapeHtml(raw);
  let out = escaped;
  const sortedTokens = [...tokens].filter(Boolean).sort((a, b) => b.length - a.length);
  for (const token of sortedTokens) {
    if (!token) continue;
    // نبني regex غير حسّاس لحالة الأحرف يعمل حتى على صيَغ الأحرف المختلفة.
    const pattern = buildLenientPattern(token);
    if (!pattern) continue;
    try {
      const re = new RegExp(pattern, "gi");
      out = out.replace(re, (m) => `<mark class="hl">${m}</mark>`);
    } catch {
      // Ignore faulty regex
    }
  }
  return out;
}

/**
 * يبني نمط regex متسامحًا مع اختلاف الهمزات/الياء/التاء مرّة واحدة،
 * بحيث يُبرز token `"احمد"` كلمات مثل `"أحمد"` أيضًا في النصّ الأصلي.
 */
function buildLenientPattern(token) {
  if (!token) return null;
  const alefClass = "[\u0622\u0623\u0625\u0627\u0671]"; // آ أ إ ا ٱ
  const yaClass = "[\u0649\u064A\u0626]"; // ى ي ئ
  const haClass = "[\u0629\u0647]"; // ة ه
  const wawClass = "[\u0624\u0648]"; // ؤ و
  let out = "";
  for (const ch of token) {
    if (ch === "ا") out += alefClass;
    else if (ch === "ي") out += yaClass;
    else if (ch === "ه") out += haClass;
    else if (ch === "و") out += wawClass;
    else out += escapeRegex(ch);
  }
  return out;
}

/** escape HTML بسيط لمنع XSS داخل `highlightMatches`. */
export function escapeHtml(s) {
  if (s === undefined || s === null) return "";
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// ───────────────────── 7) TTL Cache (Memoization) ─────────────────────

/**
 * ذاكرة تخزين مؤقّتة قصيرة العمر. مصمَّمة لتخفيف الضغط على Firebase
 * حين يكرّر المستخدم بحثه عدّة مرّات خلال دقائق قليلة.
 *
 * @param {number} [ttlMs=30000] - مدّة صلاحيّة كلّ إدخال.
 */
export function createTtlCache(ttlMs = 30000) {
  const store = new Map();
  return {
    /**
     * يُرجع القيمة المُخزَّنة إن كانت صالحة، وإلّا ينفّذ `producer()` ويُخزّن الناتج.
     * @template T
     * @param {string} key
     * @param {() => Promise<T>} producer
     * @returns {Promise<T>}
     */
    async get(key, producer) {
      const now = Date.now();
      const entry = store.get(key);
      if (entry && now - entry.at < ttlMs) {
        return entry.value;
      }
      const value = await producer();
      store.set(key, { at: now, value });
      return value;
    },
    invalidate(key) {
      if (key === undefined) {
        store.clear();
      } else {
        store.delete(key);
      }
    },
  };
}

// ───────────────────── 8) Debounce ─────────────────────

/**
 * Debounce قياسيّ. يُلغي المؤقّت السابق عند كلّ استدعاء جديد، ويُنفّذ
 * الدالة مرّة واحدة بعد الهدوء لمدّة `ms`.
 *
 * @template {(...args:any[]) => void} F
 * @param {F} fn
 * @param {number} [ms=300]
 * @returns {F & { cancel: () => void }}
 */
export function debounce(fn, ms = 300) {
  let timer = null;
  const wrapped = (...args) => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
      timer = null;
      fn(...args);
    }, ms);
  };
  wrapped.cancel = () => {
    if (timer) clearTimeout(timer);
    timer = null;
  };
  return wrapped;
}

// ───────────────────── 9) Public facade ─────────────────────

/**
 * ملاءمة عامّة: يُرجع كائنًا يجمع العمليّات الشائعة، مفيد للاستدعاء من
 * الواجهات التي تحتاج tokens + filter/rank + highlight في حزمة واحدة.
 *
 * @param {string} query
 */
export function buildSearcher(query) {
  const tokens = tokenize(query);
  return {
    tokens,
    isEmpty: tokens.length === 0,
    filterAndRank: (list, extractFields) => filterAndRank(list, tokens, extractFields),
    matches: (fields) => matchesAllTokens(fields, tokens),
    score: (fields) => scoreMatch(fields, tokens),
    highlight: (text) => highlightMatches(text, tokens),
  };
}
