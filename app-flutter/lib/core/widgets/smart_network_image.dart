import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// النظام الذكيّ الشامل لعرض الصور (Global Smart Thumbnail System).
///
/// ---------------------------------------------------------------------------
/// الفلسفة:
/// ---------------------------------------------------------------------------
/// * **أداة واحدة تعمل على مستوى التطبيق**: سواء أكانت الصورة قادمة من
///   Firebase، فإنّ طبقة البيانات
///   (Datasources/Bridges) **لا تلمس** قيمة `imageUrl` ولا تُبدِّلها ببدائل
///   ثابتة. تمرّ القيمة كما هي — حتى لو كانت `null` — إلى هذا الويدجت.
/// * **التذكية في طبقة العرض فقط**: حين يصل الويدجت إلى الشاشة:
///     1) إن كانت لديه صورة صالحة، يعرضها عبر [CachedNetworkImage].
///     2) وإلّا (أو عند فشل التحميل) يُحلِّل [title] بحثاً عن كلمات مفتاحيّة
///        تعكس مجال القسم (قرآن، عقيدة، فقه، حديث، تاريخ، لغة) ويعرض
///        بطاقة افتراضيّة أنيقة: تدرّج لوني متناسق + أيقونة دالّة.
/// * **لا اعتماد على assets ثنائيّة**: لا حاجة لإسقاط صور مسبقًا في
///   `assets/`. كلّ العنصر النائب مبنيّ من تدرّج + أيقونة — يعمل أوفلاين
///   بالكامل وبأداء ثابت.
/// * **واجهة موحَّدة لـ ListTile والـ Cards والـ Grid**: نفس الـ API يعمل
///   في البطاقات الكبيرة والمربّعات المصغّرة والأفاتار الدائرية (عبر
///   تغليف خارجي بـ `ClipOval` من طرف المستدعي).
///
/// استخدام معتاد:
/// ```dart
/// SmartNetworkImage(
///   imageUrl: section.imageUrl,   // قد تكون null
///   title: section.title,
///   fit: BoxFit.cover,
/// )
/// ```
///
/// لو كان المستدعي يرغب بتغطية الأيقونة بأيقونة نوع وسيط (كتاب/فيديو/...):
/// ```dart
/// SmartNetworkImage(
///   imageUrl: item.thumbnailUrl,
///   title: item.title,
///   iconOverride: Icons.play_circle_outline, // يغلب على التصنيف
/// )
/// ```
class SmartNetworkImage extends StatelessWidget {
  const SmartNetworkImage({
    super.key,
    required this.imageUrl,
    required this.title,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.iconOverride,
    this.showLoadingIndicator = false,
  });

  /// عنوان الصورة. عند كونه `null` أو فارغاً يُعرض العنصر النائب الذكيّ
  /// مباشرة دون محاولة شبكة.
  final String? imageUrl;

  /// عنوان القسم/المحتوى — مدخل المصنِّف. كلّما كان العنوان معبّراً
  /// (يحوي كلمة مثل "قرآن" أو "تفسير") كان التصنيف أدقّ.
  final String? title;

  final BoxFit fit;
  final double? width;
  final double? height;

  /// إن أراد المستدعي حدوداً مستديرة على الويدجت نفسه بدلاً من تغليفه
  /// بـ `ClipRRect`. اختياريّ.
  final BorderRadius? borderRadius;

  /// يغلب على أيقونة التصنيف التلقائيّ (مفيد لبطاقات المحتوى التي
  /// تريد عرض أيقونة "كتاب/صوت/فيديو" بدل أيقونة "قرآن/عقيدة/...").
  final IconData? iconOverride;

  /// إن كان `true`، يُعرض مؤشّر تحميل أثناء جلب الصورة. افتراضيّاً نُظهر
  /// العنصر النائب مباشرة لأنّه أخفّ بصريّاً ومطابق للوجه النهائيّ.
  final bool showLoadingIndicator;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    final category = SmartThumbnailClassifier.classify(title);

    Widget image;
    if (url.isEmpty) {
      image = _SmartPlaceholder(
        category: category,
        iconOverride: iconOverride,
      );
    } else {
      // نحسب أبعاد فكّ التشفير بدقّة الجهاز الفعليّة (devicePixelRatio)
      // لتفادي تفكيك صور Firebase Storage الكبيرة بدقّتها الأصليّة في
      // الذاكرة. أجهزة 2GB RAM تنهار OOM على شاشات Home/Search ذات
      // القوائم الطويلة دون هذه الحماية.
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final memWidth = width != null && width!.isFinite
          ? (width! * dpr).round()
          : null;
      final memHeight = height != null && height!.isFinite
          ? (height! * dpr).round()
          : null;

      image = CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        width: width,
        height: height,
        memCacheWidth: memWidth,
        memCacheHeight: memHeight,
        // ضغط الذاكرة فقط — التخزين على القرص يبقى بالأبعاد الأصليّة.
        maxWidthDiskCache: memWidth != null ? memWidth * 2 : null,
        maxHeightDiskCache: memHeight != null ? memHeight * 2 : null,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, _) => showLoadingIndicator
            ? _LoadingTile(category: category)
            : _SmartPlaceholder(
                category: category,
                iconOverride: iconOverride,
              ),
        errorWidget: (_, _, _) => _SmartPlaceholder(
          category: category,
          iconOverride: iconOverride,
        ),
      );
    }

    final sized = (width != null || height != null)
        ? SizedBox(width: width, height: height, child: image)
        : image;

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: sized);
    }
    return sized;
  }
}

// ─────────────────────────── المصنِّف (Classifier) ───────────────────────────

/// فئات الأقسام التي يتعرّف عليها النظام الذكيّ. يمكن توسيعها لاحقاً
/// دون كسر أيّ مستدعي: فقط أضف فئة جديدة و Rule في [_rules].
enum SmartCategory {
  quran,
  creed,
  fiqh,
  hadith,
  history,
  language,
  general,
}

/// مصنِّف الكلمات المفتاحيّة — نقيّ (Pure) بلا أيّ وصول للشبكة أو الملفّات.
///
/// يُطبَّع العنوان أوّلاً (إزالة التشكيل، توحيد الهمزات/الألف، تحويل إلى
/// صغير بالإنجليزيّة) ثمّ يُبحث عن أيّ كلمة من قوائم الكلمات المفتاحيّة
/// في كلّ قاعدة بالترتيب. أوّل مطابقة تفوز.
class SmartThumbnailClassifier {
  const SmartThumbnailClassifier._();

  static SmartCategory classify(String? title) {
    final text = _normalize(title ?? '');
    if (text.isEmpty) return SmartCategory.general;
    for (final rule in _rules) {
      if (rule.matches(text)) return rule.category;
    }
    return SmartCategory.general;
  }
}

/// قاعدة تصنيف واحدة: فئة + قوائم كلمات (عربيّة/إنجليزيّة/فرنسيّة).
class _Rule {
  const _Rule(this.category, {required this.keywords});
  final SmartCategory category;
  final List<String> keywords;

  bool matches(String normalizedText) {
    for (final k in keywords) {
      if (k.isEmpty) continue;
      if (normalizedText.contains(k)) return true;
    }
    return false;
  }
}

const List<_Rule> _rules = [
  // القرآن الكريم، المصاحف، التلاوة، التجويد
  _Rule(
    SmartCategory.quran,
    keywords: [
      // عربي
      'قرآن', 'قران', 'مصحف', 'تلاو', 'تلاوة', 'قراءات', 'قراءة',
      'قراء', 'ترتيل', 'تجويد', 'حفظ القران', 'حفظ القرآن', 'تفسير',
      'تاويل', 'تدبر', 'معاني القران', 'معاني القرآن', 'رسم المصحف',
      'اسباب النزول',
      // English
      'quran', "qur'an", 'mushaf', 'recit', 'tajwid', 'tajweed',
      'tafsir', 'tafseer', 'exeges', 'qira',
      // Français
      'coran', 'récit', 'récitation', 'tafsir',
    ],
  ),
  // العقيدة، التوحيد، الإيمان، المنهج
  _Rule(
    SmartCategory.creed,
    keywords: [
      'عقيدة', 'العقيدة', 'توحيد', 'التوحيد', 'ايمان', 'إيمان',
      'الايمان', 'الإيمان', 'منهج', 'المنهج', 'اعتقاد', 'الاعتقاد',
      'اركان الايمان', 'أركان الإيمان', 'فرق', 'ملل', 'نحل',
      'creed', 'aqeedah', 'aqidah', 'tawhid', 'tawheed',
      'monotheism', 'faith', 'belief', 'theology',
      'croyance', 'foi', 'tawhid', 'théologie',
    ],
  ),
  // الحديث والسنة
  _Rule(
    SmartCategory.hadith,
    keywords: [
      'حديث', 'الحديث', 'احاديث', 'أحاديث', 'سنة', 'السنة', 'سنن',
      'سنن النبي', 'صحيح البخاري', 'صحيح مسلم', 'بخاري', 'مسلم',
      'ترمذي', 'ابو داود', 'أبو داود', 'نسائي', 'ابن ماجه', 'احمد',
      'موطا', 'موطأ', 'الباني', 'مصطلح الحديث', 'علوم الحديث',
      'hadith', 'hadeeth', 'sunnah', 'sunna', 'bukhari', 'muslim',
      'tirmidh', 'abu dawud', 'nasai', 'ibn majah', 'malik',
    ],
  ),
  // الفقه، الأحكام، الفتاوى، العبادات
  _Rule(
    SmartCategory.fiqh,
    keywords: [
      'فقه', 'الفقه', 'احكام', 'أحكام', 'فتوى', 'فتاوى', 'اجتهاد',
      'الاجتهاد', 'عبادات', 'العبادات', 'معاملات', 'المعاملات',
      'طهارة', 'الطهارة', 'صلاة', 'الصلاة', 'صوم', 'الصوم',
      'صيام', 'زكاة', 'الزكاة', 'حج', 'الحج', 'عمرة', 'العمرة',
      'بيوع', 'نكاح', 'طلاق', 'ميراث', 'اصول الفقه', 'أصول الفقه',
      'قواعد فقهية', 'حلال', 'حرام',
      'fiqh', 'jurisprudence', 'fatwa', 'worship', 'prayer', 'salah',
      'zakat', 'hajj', 'usul', 'halal', 'haram', 'ibadah',
      'fiqh', 'jurisprudence', 'prière', 'jeûne',
    ],
  ),
  // التاريخ الإسلامي، السيرة، الصحابة، القصص
  _Rule(
    SmartCategory.history,
    keywords: [
      'تاريخ', 'التاريخ', 'سيرة', 'السيرة', 'النبوية', 'قصص',
      'القصص', 'الانبياء', 'الأنبياء', 'صحابة', 'الصحابة',
      'خلفاء', 'الخلفاء', 'الراشدين', 'غزوات', 'الغزوات',
      'الخلافة', 'حضارة', 'الحضارة', 'الدولة', 'عثمانية',
      'الاندلس', 'الأندلس',
      'history', 'seerah', 'biography', 'sirah', 'prophet',
      'companion', 'caliph', 'caliphate', 'civilization',
      'andalus', 'ottoman',
      'histoire', 'sira', 'compagnons', 'califat',
    ],
  ),
  // اللغة العربية، النحو، الأدب، الشعر
  _Rule(
    SmartCategory.language,
    keywords: [
      'لغة', 'اللغة', 'عربية', 'العربية', 'نحو', 'النحو', 'صرف',
      'الصرف', 'بلاغة', 'البلاغة', 'ادب', 'أدب', 'الادب', 'الأدب',
      'شعر', 'الشعر', 'شاعر', 'معاجم', 'معجم', 'قاموس', 'كتابة',
      'اعراب', 'إعراب', 'فصاحة',
      'language', 'arabic', 'grammar', 'syntax', 'rhetoric',
      'literature', 'poetry', 'poem', 'dictionary',
      'langue', 'arabe', 'grammaire', 'littérature', 'poésie',
    ],
  ),
];

/// تطبيع النصّ العربي/اللاتيني قبل المطابقة:
///   * تحويل إلى حروف صغيرة للاتيني.
///   * إزالة التشكيل (الفتحة/الضمّة/... والتَطويل).
///   * توحيد أشكال الألف (أ/إ/آ → ا) والتاء المربوطة (ة → ه) والياء
///     المقصورة (ى → ي) حتى يلتقط "قرآن" و "قران" نفس القاعدة.
///   * تطبيع المسافات المتعدّدة.
String _normalize(String input) {
  if (input.isEmpty) return '';
  final buf = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    // التشكيل العربي: U+064B..U+0652 و U+0670 و U+0640 (الكَشيدة)
    if (rune >= 0x064B && rune <= 0x0652) continue;
    if (rune == 0x0670 || rune == 0x0640) continue;
    // الهمزات/الألفات
    if (rune == 0x0623 || rune == 0x0625 || rune == 0x0622) {
      buf.write('ا');
      continue;
    }
    if (rune == 0x0629) {
      buf.write('ه');
      continue;
    }
    if (rune == 0x0649) {
      buf.write('ي');
      continue;
    }
    // الهمزة على الواو / الياء
    if (rune == 0x0624) {
      buf.write('و');
      continue;
    }
    if (rune == 0x0626) {
      buf.write('ي');
      continue;
    }
    buf.write(ch);
  }
  return buf
      .toString()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

// ─────────────────────────── العنصر النائب البصريّ ──────────────────────────

/// بطاقة افتراضيّة ذكيّة: تدرّج لوني + أيقونة. لا ترتبط بـ `Theme` إلّا
/// لتدرّج لطيف في الوضع الداكن؛ الألوان الأساسيّة مختارة لتبقى جميلة
/// في الوضعين.
class _SmartPlaceholder extends StatelessWidget {
  const _SmartPlaceholder({
    required this.category,
    this.iconOverride,
  });

  final SmartCategory category;
  final IconData? iconOverride;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(category);
    final icon = iconOverride ?? _iconFor(category);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [palette.dark1, palette.dark2]
              : [palette.light1, palette.light2],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // الأيقونة تتناسب مع حجم الويدجت: ~40% من أقصر ضلع، بحدود
          // معقولة حتى لا تختفي في الأفاتار الصغيرة ولا تضخم في البطاقات.
          final side = constraints.biggest.shortestSide.isFinite
              ? constraints.biggest.shortestSide
              : 48.0;
          final iconSize = (side * 0.42).clamp(18.0, 64.0);
          return Center(
            child: Icon(
              icon,
              size: iconSize,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          );
        },
      ),
    );
  }
}

/// نفس التصميم لكن مع نبض خفيف يدلّ على التحميل — اختياريّ.
class _LoadingTile extends StatelessWidget {
  const _LoadingTile({required this.category});
  final SmartCategory category;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(category);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [palette.light1, palette.light2],
        ),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _Palette {
  const _Palette(this.light1, this.light2, this.dark1, this.dark2);
  final Color light1;
  final Color light2;
  final Color dark1;
  final Color dark2;
}

_Palette _paletteFor(SmartCategory c) {
  switch (c) {
    case SmartCategory.quran:
      // أخضر زاهٍ → زمرّدي: الهويّة التقليديّة للمصحف.
      return const _Palette(
        Color(0xFF2E7D5B),
        Color(0xFF4FAE80),
        Color(0xFF1F5C42),
        Color(0xFF2E7D5B),
      );
    case SmartCategory.creed:
      // نيليّ → أزرق: رمزيّة عمق العقيدة والتوحيد.
      return _Palette(
        const Color(0xFF2C3E7A),
        const Color(0xFF5A6DB5),
        const Color(0xFF1A2450),
        const Color(0xFF2C3E7A),
      );
    case SmartCategory.fiqh:
      // تركوازي → فيروزي: وضوح الأحكام.
      return const _Palette(
        Color(0xFF117A8B),
        Color(0xFF3FAEC2),
        Color(0xFF0B4F5C),
        Color(0xFF117A8B),
      );
    case SmartCategory.hadith:
      // عنبري → ذهبيّ: لون السنّة الدافئ المرتبط بالمخطوط.
      return const _Palette(
        Color(0xFFB3701F),
        Color(0xFFE2A552),
        Color(0xFF7F4B12),
        Color(0xFFB3701F),
      );
    case SmartCategory.history:
      // بنّي → نحاسيّ: الحضارة والمخطوطات التاريخيّة.
      return const _Palette(
        Color(0xFF7A4B2A),
        Color(0xFFB57B4F),
        Color(0xFF4E2F1B),
        Color(0xFF7A4B2A),
      );
    case SmartCategory.language:
      // بنفسجيّ → ورديّ: الأدب والبلاغة.
      return const _Palette(
        Color(0xFF6A3A8C),
        Color(0xFFA567C4),
        Color(0xFF44255B),
        Color(0xFF6A3A8C),
      );
    case SmartCategory.general:
      // رماديّ أردوازيّ محايد — للأقسام غير المصنَّفة.
      return const _Palette(
        Color(0xFF455A64),
        Color(0xFF78909C),
        Color(0xFF263238),
        Color(0xFF455A64),
      );
  }
}

IconData _iconFor(SmartCategory c) {
  switch (c) {
    case SmartCategory.quran:
      return Icons.auto_stories_rounded;
    case SmartCategory.creed:
      return Icons.mosque_rounded;
    case SmartCategory.fiqh:
      return Icons.gavel_rounded;
    case SmartCategory.hadith:
      return Icons.menu_book_rounded;
    case SmartCategory.history:
      return Icons.history_edu_rounded;
    case SmartCategory.language:
      return Icons.translate_rounded;
    case SmartCategory.general:
      return Icons.collections_bookmark_rounded;
  }
}
