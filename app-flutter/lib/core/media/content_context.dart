/// سياق تشغيل المحتوى (Content Context).
///
/// يُستخدم من قِبَل مُشغّلات الصوت والفيديو ليفهما "من أين جاء المستخدم":
/// - [forYou]    : من صفحة "لك" (موجز التوصيات) — نُفعِّل Smart Auto-Play.
/// - [search]    : من نتائج البحث — نُفعِّل Smart Auto-Play أيضًا.
/// - [section]   : من تصفّح قسم (قائمة تشغيل مبنيّة مسبقًا) — لا نحتاج auto-fill.
/// - [saved]     : من المحفوظات — نلتزم بقائمة المحفوظات ولا نُضيف عشوائيًّا.
/// - [home]      : من الشاشة الرئيسيّة — نُفعِّل Smart Auto-Play بسياسة متحفّظة.
/// - [direct]    : فتح مباشر (إشعار/رابط) — سلوك "مقطع واحد" ثمّ انتهاء.
///
/// ⚠ عند وجود قائمة تشغيل حقيقيّة نتنقّل داخلها أولًا (Next/Prev).
/// فقط إذا لم يتبقَّ عنصر تالٍ، نُطلق `onExhaustedAutoFill` — وهذا
/// لا يحدث إلّا في السياقات التي تسمح به (انظر [allowsSmartAutoPlay]).
enum ContentContext {
  forYou,
  search,
  section,
  saved,
  home,
  direct,
}

extension ContentContextX on ContentContext {
  /// هل يسمح هذا السياق بتشغيل اقتراحات ذكيّة عند نفاد القائمة؟
  /// القاعدة: نعم في "لك / بحث / رئيسية"، ولا في "قسم / محفوظ / مباشر".
  bool get allowsSmartAutoPlay {
    switch (this) {
      case ContentContext.forYou:
      case ContentContext.search:
      case ContentContext.home:
        return true;
      case ContentContext.section:
      case ContentContext.saved:
      case ContentContext.direct:
        return false;
    }
  }
}
