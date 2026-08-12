import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/widgets/content_section_breadcrumb_nav.dart';
import 'package:nebras_mobile_app/core/widgets/empty_state_widget.dart';
import 'package:nebras_mobile_app/core/widgets/related_content_list.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:url_launcher/url_launcher.dart';

/// قارئ نصّي خفيف — يفتح مقالاً أو ملفّاً نصّياً (.txt) داخل التطبيق
/// دون الحاجة لمتصفّح خارجي أو تطبيق طرف ثالث.
///
/// يُستخدم لعناصر [ContentType.article]؛ إن وُجد `description` فقط
/// بدون `sourceUrl` نعرض الوصف — وهو شائع للمحتوى الوصفي (صورة + نص).
class ArticleReaderScreen extends StatefulWidget {
  final Content content;

  const ArticleReaderScreen({super.key, required this.content});

  @override
  State<ArticleReaderScreen> createState() => _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends State<ArticleReaderScreen> {
  String? _text;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = widget.content.sourceUrl?.trim() ?? '';
    // لا يوجد ملفّ نصّيّ مُحدَّد — نكتفي بوصف التطبيق (أو رسالة فراغ).
    if (url.isEmpty) {
      setState(() {
        _loading = false;
        final desc = widget.content.description.trim();
        _text = desc.isEmpty ? null : desc;
      });
      return;
    }
    try {
      final res = await Dio().get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          // حدّ أعلى لمنع تحميل ملفّات ضخمة تُجمّد الواجهة.
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      var text = (res.data ?? '').trim();
      const maxLen = 200 * 1024; // 200 KB من النصّ يكفي لأطول مقال.
      if (text.length > maxLen) {
        text = '${text.substring(0, maxLen)}\n…';
      }
      setState(() {
        _text = text;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.content.title;
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _loading = true;
            _error = null;
          });
          await _load();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: 80.h),
            EmptyStateWidget(message: 'Something went wrong'.tr()),
          ],
        ),
      );
    }
    final text = _text?.trim();
    if (text == null || text.isEmpty) {
      return EmptyStateWidget(message: 'Content unavailable'.tr());
    }
    final author = widget.content.author.trim();
    return SingleChildScrollView(
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.content.title,
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
          ),
          if (author.isNotEmpty) ...[
            SizedBox(height: 6.h),
            Text(
              author,
              style: TextStyle(
                fontSize: 13.sp,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
          SizedBox(height: 16.h),
          SelectableLinkify(
            text: text,
            style: TextStyle(fontSize: 14.sp, height: 1.6),
            linkStyle: TextStyle(
              fontSize: 14.sp,
              height: 1.6,
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
            linkifiers: const [UrlLinkifier()],
            options: const LinkifyOptions(humanize: false),
            onOpen: (link) async {
              final uri = Uri.tryParse(link.url);
              if (uri == null) return;
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {
                await launchUrl(uri);
              }
            },
          ),
          SizedBox(height: 24.h),
          ContentSectionBreadcrumbNav(content: widget.content),
          SizedBox(height: 24.h),
          // اقتراحات ذات صلة — تعرض محتوى مشابهًا (مقالات/كتب/فيديوهات)
          // من مصادر التطبيق المختلفة أسفل القارئ.
          RelatedContentList(reference: widget.content),
        ],
      ),
    );
  }
}
