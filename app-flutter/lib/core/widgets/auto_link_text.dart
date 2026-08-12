import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';

/// [AutoLinkText] — ويدجت موحَّد لعرض نصوص الوصف في عموم التطبيق
/// (Firebase) مع كشف روابط `http(s)://`
/// تلقائيًّا وتحويلها إلى روابط قابلة للنقر تفتح في **المتصفّح الخارجيّ**
/// للجهاز.
///
/// لماذا منفصل وموحَّد؟
///   * ضمان تجربة مستخدم متّسقة: لونٌ واحد للرابط وتسطيرٌ واحد في كلّ الشاشات.
///   * نقطة دخول واحدة لأيّ تعديل مستقبليّ (منع روابط، إضافة preview…).
///   * عزل `flutter_linkify` و`url_launcher` في ويدجت صغيرة لتفادي تسرّب
///     الاعتماديّة إلى باقي الملفّات.
///
/// إن لم يحتوِ النصّ على أيّ رابط، تبدو النتيجة تمامًا كويدجت [Text] عاديّ،
/// بلا أيّ سلوك أو زيادة في التكلفة البصريّة — حفاظًا على شكل الوصف
/// الحاليّ في جميع البطاقات والقوائم.
class AutoLinkText extends StatelessWidget {
  const AutoLinkText(
    this.text, {
    super.key,
    this.style,
    this.linkStyle,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.textDirection,
    this.softWrap,
  });

  /// النصّ الأصليّ (يمكن أن يكون null أو فارغًا — نعيد عنصرًا فارغًا).
  final String? text;

  /// نمط النصّ العاديّ (غير المرتبط). إن لم يُمرَّر يُستخدم نمط النصّ
  /// الافتراضيّ للثيم الحاليّ.
  final TextStyle? style;

  /// نمط الروابط القابلة للنقر. إن لم يُمرَّر يُحسب تلقائيًّا من لون الثيم
  /// الأساسيّ (primary) مع تسطير.
  final TextStyle? linkStyle;

  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    final value = text ?? '';
    if (value.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final baseStyle = style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final effectiveLinkStyle =
        linkStyle ??
        baseStyle.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
        );

    return Linkify(
      text: value,
      onOpen: _handleOpen,
      style: baseStyle,
      linkStyle: effectiveLinkStyle,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      textAlign: textAlign ?? TextAlign.start,
      textDirection: textDirection,
      softWrap: softWrap ?? true,
      // نُقصر الكاشف على روابط URL فقط لتفادي تحويل الإيميلات والأرقام
      // إلى روابط غير مرغوبة. رغبة المستخدم تنصّ حصرًا على http/https.
      linkifiers: const [UrlLinkifier()],
      options: const LinkifyOptions(humanize: false, removeWww: false),
    );
  }

  Future<void> _handleOpen(LinkableElement link) async {
    final uri = Uri.tryParse(link.url);
    if (uri == null) return;
    // `externalApplication` يضمن الفتح في متصفّح النظام (Chrome, Samsung
    // Internet…) وليس داخل WebView — كما طلب المستخدم.
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // محاولة بديلة بدون تخصيص الوضع إن رفض النظام الطلب لأيّ سبب.
      await launchUrl(uri);
    }
  }
}

/// إضافة مختصرة: تتيح اختياريًّا فتح روابط يدويًّا من أيّ مكان بالتطبيق.
/// تُمرَّر كـ `recognizer` لأجزاء نصّ مُخصَّصة (RichText) — غير مستعملة
/// حاليًّا ولكنّها مفيدة لو احتجنا Linkify يدويًّا خارج [AutoLinkText].
TapGestureRecognizer buildExternalLinkRecognizer(String url) {
  final recognizer = TapGestureRecognizer();
  recognizer.onTap = () async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  };
  return recognizer;
}
