/// TextNormalizer — أدوات نصّية عامّة تُستعمل من:
///   * مُتتبّع السلوك (`UserBehaviorTracker`) لتوحيد مفاتيح الكلمات.
///   * محرّك التوصيات (`RecommendationEngine`) لمقارنة العناوين بدقّة.
///   * محرّك البحث الشامل (`GlobalSearchEngine`) لتطبيع الاستعلام وحساب
///     درجة الصلة (Relevance Score) مع التسامح مع الأخطاء الإملائيّة
///     البسيطة والبحث بجزء الكلمة (Substring Matching).
///
/// لماذا أداة مستقلّة ومُجرَّدة؟ لأنّ قواعد تطبيع النصّ العربيّ (همزات،
/// تشكيل، ألف مقصورة، تاء مربوطة) يجب أن تكون **مرجعًا واحدًا** في
/// التطبيق، حتّى لا ينحرف تنفيذها بين الأماكن فينقسم ملف اهتمامات
/// المستخدم أو تختلف نتيجة البحث عن نتيجة التوصية.
///
/// القواعد الأساسيّة لـ [normalizeText]:
///   * تحويل إلى lowercase (مفيد للإنجليزيّة/الفرنسيّة).
///   * إزالة علامات التشكيل العربيّة (ًٌٍَُِّْـ) وعلامة الـ superscript.
///   * توحيد الهمزات/الألف: (أ/إ/آ/ٱ → ا).
///   * توحيد الياء: (ى → ي) والتاء المربوطة (ة → ه).
///   * استبدال علامات الترقيم والمسافات المكرّرة بمسافة واحدة.
///
/// أدوات البحث المتقدّمة:
///   * [substringMatches]: يفحص التطابق الجزئيّ كلمة-بكلمة بعد التطبيع.
///   * [levenshteinDistance]: مسافة تحرير بسيطة لقياس الفرق بين سلسلتَين
///     (مفيدة للتسامح مع الأخطاء الإملائيّة).
///   * [relevanceScore]: يُرجع درجة 0..1 لمدى صلة نصّ مرشّح باستعلام —
///     تعطي أعلى نقاط للمطابقة التامّة، ثمّ البدء بالكلمة، ثمّ الاحتواء،
///     ثمّ تطابق الكلمات المفتاحيّة، ثمّ التشابه التحريريّ.
library;

const _diacritics = <String>[
  // تشكيل عربي كامل + superscript alef + tatweel.
  '\u064B', '\u064C', '\u064D', '\u064E', '\u064F', '\u0650',
  '\u0651', '\u0652', '\u0670', '\u0640',
];

/// رموز لاتيّة لها معادل صوتيّ عربيّ — تُستخدم في [phoneticKey] لتمكين
/// البحث عبر الخطّين (Transliteration matching). مثلاً: كتابة
/// "bukhari" تُطابق "البخاري" بعد تحويل كليهما إلى نفس المفتاح.
/// الخريطة ليست كاملة بل **قاموس فقرة مشترك بين الأبجديّتَين** كافٍ
/// لأسماء المؤلّفين والكتب الأكثر شيوعًا. تجنّبنا خوارزميّات معقّدة
/// مثل Buckwalter الكامل لأنّ التعقيد لا يبرّره العائد.
const _arabicToLatinPhonetic = <String, String>{
  'ا': 'a', 'ب': 'b', 'ت': 't', 'ث': 'th', 'ج': 'j', 'ح': 'h',
  'خ': 'kh', 'د': 'd', 'ذ': 'th', 'ر': 'r', 'ز': 'z', 'س': 's',
  'ش': 'sh', 'ص': 's', 'ض': 'd', 'ط': 't', 'ظ': 'z', 'ع': 'a',
  'غ': 'gh', 'ف': 'f', 'ق': 'q', 'ك': 'k', 'ل': 'l', 'م': 'm',
  'ن': 'n', 'ه': 'h', 'و': 'w', 'ي': 'y', 'ء': 'a',
};

/// يُطبِّع نصًّا عربيًّا/لاتينيًّا بطريقة تنتج مفاتيح قابلة للمقارنة.
/// السلاسل الناتجة خفيفة ومناسبة للتخزين في `SharedPreferences`.
///
/// قواعد التطبيع (مُحدَّثة):
///   * lowercase للاتينية.
///   * إزالة كامل التشكيل + tatweel + **zero-width joiners** (U+200B..U+200F)
///     التي تتسرّب من لصق النصوص.
///   * توحيد أشكال الهمزة والألف: أ/إ/آ/ٱ → ا.
///   * توحيد الياء والتاء المربوطة: ى → ي، ة → ه.
///   * توحيد ؤ → و، ئ → ي.
///   * **مقابلات فارسيّة شائعة**: ی → ي، ک → ك، گ → ك (قد يُلصَق من مصادر
///     فارسيّة دون انتباه المستخدم).
///   * الأرقام العربيّة/الهنديّة تُحوَّل إلى أرقام لاتينيّة.
String normalizeText(String? input) {
  if (input == null) return '';
  var s = input.trim().toLowerCase();
  if (s.isEmpty) return '';
  for (final d in _diacritics) {
    s = s.replaceAll(d, '');
  }
  // Zero-width characters + LRM/RLM marks.
  s = s.replaceAll(RegExp(r'[\u200B-\u200F\u202A-\u202E\uFEFF]'), '');
  s = s
      // هَمَزات الألف.
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ٱ', 'ا')
      // ياء / تاء مربوطة / ؤ / ئ.
      .replaceAll('ى', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي')
      .replaceAll('ة', 'ه')
      // فارسيّة.
      .replaceAll('ی', 'ي')
      .replaceAll('ک', 'ك')
      .replaceAll('گ', 'ك');
  // أرقام عربيّة/هنديّة ⇒ لاتينيّة (٠-٩ و ۰-۹).
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  const persianIndic = '۰۱۲۳۴۵۶۷۸۹';
  final buf = StringBuffer();
  var lastSpace = false;
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    var out = c;
    final iAr = arabicIndic.indexOf(c);
    if (iAr >= 0) out = String.fromCharCode(0x30 + iAr);
    final iPe = persianIndic.indexOf(c);
    if (iPe >= 0) out = String.fromCharCode(0x30 + iPe);
    final isLetterOrDigit = RegExp(r'[0-9A-Za-z\u0600-\u06FF]').hasMatch(out);
    if (isLetterOrDigit) {
      buf.write(out);
      lastSpace = false;
    } else if (!lastSpace) {
      buf.write(' ');
      lastSpace = true;
    }
  }
  return buf.toString().trim();
}

/// يُنتج **مفتاحًا صوتيًّا مشتركًا** بين العربيّة واللاتينيّة بحيث يتساوى
/// عند كتابة الاسم نفسه بأيّ خطّ. مثلاً:
///   phoneticKey("البخاري") == phoneticKey("bukhari")  // ≈ "albkhary" / "bukhari"
///
/// الاستراتيجيّة:
///   1) نُطبّع النصّ عبر [normalizeText].
///   2) نحوّل كل حرف عربيّ إلى معادله الصوتيّ (من خريطة `_arabicToLatinPhonetic`).
///   3) نُزيل أحرف العلّة المتكرّرة لتسامح مع اختلاف الرسم (a/aa، u/oo، ee/i).
///   4) نُبقي تسلسل الأحرف الساكنة — وهو العمود الفقري للمطابقة الصوتيّة.
///
/// لا يُستعمل وحده للمطابقة؛ بل تُضيفه [relevanceScore] كإشارة إضافيّة.
String phoneticKey(String? input) {
  final normalized = normalizeText(input);
  if (normalized.isEmpty) return '';
  final buf = StringBuffer();
  for (final r in normalized.runes) {
    final c = String.fromCharCode(r);
    final mapped = _arabicToLatinPhonetic[c];
    buf.write(mapped ?? c);
  }
  var phonetic = buf.toString();
  // طيّ أحرف العلّة اللاتينيّة المتكرّرة (aa→a، ee→e، oo→o، uu→u).
  phonetic = phonetic.replaceAll(RegExp(r'([aeiouy])\1+'), r'$1');
  // تبسيط المسافات.
  phonetic = phonetic.replaceAll(RegExp(r'\s+'), ' ').trim();
  return phonetic;
}

/// يُقسّم النصّ إلى **رموز دلاليّة** (tokens) قابلة للتخزين كاهتمامات.
/// يُلغي الكلمات القصيرة جدًّا (<3 حروف) وكلمات الوقف (stop words)
/// الشائعة لأنّها لا تُفيد المطابقة.
List<String> extractKeywords(String? input, {int maxTokens = 12}) {
  final normalized = normalizeText(input);
  if (normalized.isEmpty) return const [];
  final parts = normalized.split(' ');
  final out = <String>[];
  for (final raw in parts) {
    final w = raw.trim();
    if (w.length < 3) continue;
    if (_stopWords.contains(w)) continue;
    if (out.contains(w)) continue;
    out.add(w);
    if (out.length >= maxTokens) break;
  }
  return out;
}

/// Jaccard overlap على الرموز الدلاليّة — نتيجة بين 0 و 1.
double keywordOverlapScore(String? a, String? b) {
  final setA = extractKeywords(a).toSet();
  final setB = extractKeywords(b).toSet();
  if (setA.isEmpty || setB.isEmpty) return 0.0;
  final intersect = setA.intersection(setB).length;
  final union = setA.union(setB).length;
  return union == 0 ? 0.0 : intersect / union;
}

/// يفحص إن كان [haystack] يحوي [needle] بعد التطبيع على الطرفين.
/// مفيد لبحث جزئيّ يتجاهل التشكيل/الهمزات.
///
/// **خوارزميّة الجزء-بكلمة**: لو لم يتطابق النصّ كاملاً، نحاول أيضًا
/// العثور على كلّ token منفصلاً. كاف لحالات "فقة" في مقابل "الفقه".
bool fuzzyContains(String? haystack, String? needle) {
  final h = normalizeText(haystack);
  final n = normalizeText(needle);
  if (n.isEmpty || h.isEmpty) return false;
  if (h.contains(n)) return true;
  for (final tk in extractKeywords(needle, maxTokens: 6)) {
    if (tk.length < 3) continue;
    if (h.contains(tk)) return true;
  }
  return false;
}

/// يفحص إن كان [haystack] يحوي أيًّا من كلمات [needle] بعد التطبيع.
/// يختلف عن [fuzzyContains] بأنّه يكتفي بجزء (substring) داخل أيّ كلمة
/// من الـ haystack، ولو كان طوله 2 فقط — مفيد لـ autocomplete حيّ.
bool substringMatches(String? haystack, String? needle) {
  final h = normalizeText(haystack);
  final n = normalizeText(needle);
  if (n.isEmpty || h.isEmpty) return false;
  // تطابق كامل (أسرع).
  if (h.contains(n)) return true;
  // لو كان needle قصيرًا جدًّا لا نسمح بالمطابقة على كلمة منفصلة
  // لتجنّب ضوضاء (حرف واحد يُطابق كلّ شيء).
  if (n.length < 2) return false;

  final haystackTokens = h.split(' ');
  final needleTokens = n.split(' ').where((e) => e.length >= 2).toList();
  if (needleTokens.isEmpty) return false;

  // كلّ كلمة من الاستعلام يجب أن توجد ضمن إحدى كلمات الـ haystack
  // (على الأقل كـ substring من 2 حروف).
  for (final nTok in needleTokens) {
    var found = false;
    for (final hTok in haystackTokens) {
      if (hTok.contains(nTok)) {
        found = true;
        break;
      }
    }
    if (!found) return false;
  }
  return true;
}

/// نسبة تطابق جزئيّ **طرفيّ** بين استعلام ومرشّح على مستوى الكلمات
/// (tokens). تُرجع عددًا بين 0 و 1 يمثّل *كسر* كلمات الاستعلام التي
/// وُجدت ضمن إحدى كلمات المرشَّح كـ substring بطول ≥ 2 حروف.
///
/// الفائدة: حين يطبع المستخدم **جزءًا من الكلمة** (مثلاً "فقه" والعنوان
/// "الفقه الأكبر"، أو "بخاري" والعنوان "صحيح البخاري")، يريد أن يرى
/// النتيجة ولو لم تتطابق كلّ كلمات الاستعلام. [substringMatches] الصارم
/// يرفض ذلك لأنّه يشترط أن تظهر **كلّ** كلمات الاستعلام؛ هنا نرجع
/// نسبة جزئيّة لا صفرًا، فيستطيع المحرّك عرضها في الأسفل بدرجة أقلّ.
///
/// ملاحظة: لا نمرّ على tokens الاستعلام الأصغر من حرفَين (ضوضاء).
double partialTokenScore(String? query, String? candidate) {
  final q = normalizeText(query);
  final c = normalizeText(candidate);
  if (q.isEmpty || c.isEmpty) return 0.0;

  final qTokens = q.split(' ').where((t) => t.length >= 2).toList();
  if (qTokens.isEmpty) return 0.0;
  final cTokens = c.split(' ').where((t) => t.isNotEmpty).toList();
  if (cTokens.isEmpty) return 0.0;

  var matched = 0;
  for (final qt in qTokens) {
    for (final ct in cTokens) {
      if (ct.contains(qt)) {
        matched++;
        break;
      }
    }
  }
  if (matched == 0) return 0.0;
  return matched / qTokens.length;
}

/// مسافة تحرير (Levenshtein) بين سلسلتَين — بعد التطبيع. نُبقي التنفيذ
/// O(m×n) بسيطًا ومناسبًا للنصوص القصيرة (عناوين وكلمات بحث)، بلا
/// مكتبات خارجيّة. تستخدمها [relevanceScore] للتسامح مع الأخطاء.
int levenshteinDistance(String a, String b) {
  final s = normalizeText(a);
  final t = normalizeText(b);
  if (s == t) return 0;
  if (s.isEmpty) return t.length;
  if (t.isEmpty) return s.length;

  final m = s.length;
  final n = t.length;
  final prev = List<int>.filled(n + 1, 0);
  final curr = List<int>.filled(n + 1, 0);
  for (var j = 0; j <= n; j++) {
    prev[j] = j;
  }
  for (var i = 1; i <= m; i++) {
    curr[0] = i;
    for (var j = 1; j <= n; j++) {
      final cost = s.codeUnitAt(i - 1) == t.codeUnitAt(j - 1) ? 0 : 1;
      final del = prev[j] + 1;
      final ins = curr[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      var min = del < ins ? del : ins;
      if (sub < min) min = sub;
      curr[j] = min;
    }
    for (var j = 0; j <= n; j++) {
      prev[j] = curr[j];
    }
  }
  return prev[n];
}

/// حساب درجة الصلة بين استعلام [query] ومرشّح [candidate] — النتيجة
/// مُعيَّرة بين 0 و 1 (كلّما ارتفعت زادت الصلة).
///
/// ترتيب الإشارات التي يزنها المحرّك:
///   * **تطابق تامّ** بعد التطبيع → 1.0.
///   * **بداية تطابق** (startsWith) → 0.90.
///   * **احتواء كامل** → 0.78.
///   * **تطابق جميع رموز الاستعلام كـ tokens** → 0.72.
///   * **Jaccard overlap عالي** → حتى 0.6.
///   * **Substring على مستوى الكلمة** → 0.52.
///   * **تشابه تحريريّ (Levenshtein)** قريب جدًّا → ≈ 0.45.
///
/// إن لم يتحقّق أيّ من الشروط → 0.0. تُستخدم هذه الدرجة لترتيب نتائج
/// البحث الشامل، وللتمييز بين "تطابق حقيقيّ" و"تطابق ضعيف" يُخفَى عن
/// المستخدم إن كان أقلّ من عتبة معيّنة.
double relevanceScore(String? query, String? candidate) {
  final q = normalizeText(query);
  final c = normalizeText(candidate);
  if (q.isEmpty || c.isEmpty) return 0.0;
  if (q == c) return 1.0;
  if (c.startsWith(q)) return 0.90;
  if (c.contains(q)) return 0.78;

  // تطابق كلّ رموز الاستعلام داخل المرشّح.
  final qTokens = extractKeywords(query, maxTokens: 5);
  if (qTokens.isNotEmpty) {
    var allFound = true;
    for (final t in qTokens) {
      if (!c.contains(t)) {
        allFound = false;
        break;
      }
    }
    if (allFound) return 0.72;
  }

  // Jaccard على tokens — نقلّص المساهمة إلى 0.6 كحدّ أقصى.
  final overlap = keywordOverlapScore(query, candidate);
  if (overlap >= 0.5) return 0.60 + (overlap - 0.5) * 0.2; // 0.60..0.70
  if (overlap >= 0.25) return 0.50 + (overlap - 0.25) * 0.4; // 0.50..0.60

  // Substring على مستوى الكلمة — يمسك "فقه" مع "الفقه الأكبر".
  if (substringMatches(c, q)) return 0.52;

  // مسافة تحرير — نتسامح بشكل مقنّن لتجنّب المطابقات الخاطئة.
  // يسمح: q = "بخارى" مع c = "البخاري" (بعد التطبيع "بخاري"/"بخاري" → 0)،
  //       q = "قران" مع c = "القرآن" (بعد التطبيع "قران"/"القران" → substring).
  if (q.length >= 4 && c.length >= q.length) {
    final dist = levenshteinDistance(q, c);
    final maxLen = q.length > c.length ? q.length : c.length;
    final ratio = 1 - (dist / maxLen);
    if (ratio >= 0.75) return 0.40 + (ratio - 0.75) * 0.2; // 0.40..0.45
  }

  // مطابقة جزئيّة مرنة — يجلب حتى نتائج "مشابهة" (جزء من الكلمة وُجد
  // ضمن إحدى كلمات المرشَّح). نعطيها درجة منخفضة (0.25..0.38) لكي
  // تظهر في أسفل قائمة النتائج وليس في صدارتها.
  final partial = partialTokenScore(query, candidate);
  if (partial >= 0.5) return 0.30 + (partial - 0.5) * 0.16; // 0.30..0.38
  if (partial > 0) return 0.20 + partial * 0.10; // 0.20..0.30

  // إشارة أخيرة: مطابقة صوتيّة عابرة للخطَّين — تمسك حالات مثل
  // q = "bukhari" و c = "البخاري"، أو q = "ibn taymiah" و c = "ابن تيميّة".
  // نخفّضها عمدًا (≤ 0.28) حتى لا تنافس المطابقات الحرفيّة.
  final pq = phoneticKey(query);
  final pc = phoneticKey(candidate);
  if (pq.isNotEmpty && pc.isNotEmpty && pq != pc) {
    if (pc.contains(pq)) return 0.28;
    if (pq.length >= 4) {
      final dist = levenshteinDistance(pq, pc);
      final maxLen = pq.length > pc.length ? pq.length : pc.length;
      final ratio = 1 - (dist / maxLen);
      if (ratio >= 0.70) return 0.18 + (ratio - 0.70) * 0.25; // 0.18..0.26
    }
  }

  return 0.0;
}

/// قائمة كلمات وقف مُختصرة — عربيّة وإنجليزيّة وفرنسيّة.
/// ليست شاملة عن قصد؛ الهدف تصفية أعلى تردّد فقط.
const _stopWords = <String>{
  // عربي
  'في', 'من', 'على', 'الى', 'او', 'ثم', 'هذا', 'هذه', 'ذلك', 'تلك',
  'عن', 'انا', 'نحن', 'هو', 'هي', 'هم', 'كل', 'كذلك', 'ما',
  'لم', 'لا', 'ليس', 'كان', 'قد', 'ولا', 'ولم', 'بعد', 'قبل',
  // إنجليزي
  'the', 'and', 'for', 'you', 'with', 'from', 'this', 'that',
  'are', 'was', 'were', 'have', 'has', 'but', 'not', 'any',
  'all', 'one', 'two', 'its', 'our', 'their',
  // فرنسي
  'les', 'des', 'une', 'que', 'qui', 'pour', 'avec', 'dans',
  'sur', 'par', 'son', 'ses', 'est', 'sont', 'aux',
};
