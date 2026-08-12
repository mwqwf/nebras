import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/auth_provider.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../services/server_api.dart';
import '../widgets/common.dart';

/// إشراف «مجتمع نبراس» من تطبيق الإدارة. القنوات ومحتواها مستقلة عن محتوى
/// نبراس الرسمي؛ لا تتدخل الإدارة إلا لتعليق المخالف أو حذفه.
class CommunityModerationScreen extends StatefulWidget {
  const CommunityModerationScreen({super.key});

  @override
  State<CommunityModerationScreen> createState() =>
      _CommunityModerationScreenState();
}

class _CommunityModerationScreenState extends State<CommunityModerationScreen> {
  final _api = ServerApi.instance;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final raw = await _api.communityModeration();
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _action({
    required String action,
    required Map<String, dynamic> payload,
    required String confirmation,
    required String success,
    bool destructive = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(destructive ? 'تأكيد الإجراء النهائي' : 'تأكيد الإجراء'),
        content: Text(confirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: NebrasColors.rose)
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.communityAction({'action': action, ...payload});
      if (mounted) showSnack(context, success);
      _reload();
    } catch (e) {
      if (mounted) {
        showSnack(
          context,
          'فشل الإجراء: ${e is ApiException ? e.message : e}',
          error: true,
        );
      }
    }
  }

  static String _date(dynamic value) {
    if (value is! num || value <= 0) return '';
    return DateFormat(
      'yyyy/MM/dd HH:mm',
    ).format(DateTime.fromMillisecondsSinceEpoch(value.toInt()));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: NebrasColors.rose),
                  const SizedBox(height: 8),
                  Text('تعذّر تحميل بيانات المجتمع: ${snapshot.error}'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
        }
        final data = snapshot.data ?? const <String, dynamic>{};
        final channels = ((data['channels'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);
        final reported = ((data['reportedPosts'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);
        final counts = (data['counts'] as Map?) ?? const {};

        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    _countChip(
                      Icons.groups_2_outlined,
                      '${counts['channels'] ?? channels.length} قناة',
                    ),
                    const SizedBox(width: 8),
                    _countChip(
                      Icons.flag_outlined,
                      '${counts['pendingReports'] ?? reported.length} بلاغ',
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'تحديث',
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'القنوات وأقسامها ملك ناشريها ولا علاقة لها بأقسام نبراس. يتدخل المشرف عند مخالفة الشروط فقط، والحذف النهائي للمالك.',
                  style: TextStyle(fontSize: 12, color: NebrasColors.textMuted),
                ),
              ),
              const SizedBox(height: 8),
              const TabBar(
                tabs: [
                  Tab(text: 'القنوات'),
                  Tab(text: 'منشورات مُبلّغ عنها'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    RefreshIndicator(
                      onRefresh: () async => _reload(),
                      child: channels.isEmpty
                          ? _empty('لا توجد قنوات منشأة بعد.')
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: channels.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, index) =>
                                  _channelCard(channels[index]),
                            ),
                    ),
                    RefreshIndicator(
                      onRefresh: () async => _reload(),
                      child: reported.isEmpty
                          ? _empty('لا توجد بلاغات مجتمعية معلّقة. ✅')
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: reported.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, index) =>
                                  _reportedPostCard(reported[index]),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _countChip(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: NebrasColors.surfaceAlt,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: NebrasColors.emerald),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );

  Widget _empty(String text) => ListView(
    children: [
      const SizedBox(height: 110),
      Center(
        child: Text(
          text,
          style: const TextStyle(color: NebrasColors.textMuted),
        ),
      ),
    ],
  );

  Widget _channelCard(Map<String, dynamic> channel) {
    final id = '${channel['id'] ?? ''}';
    final name = '${channel['name'] ?? ''}'.trim();
    final bio = '${channel['bio'] ?? ''}'.trim();
    final suspended = '${channel['status']}' == 'suspended';
    final reports = channel['pendingReports'] ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: suspended
                      ? NebrasColors.rose.withValues(alpha: 0.16)
                      : NebrasColors.emerald.withValues(alpha: 0.16),
                  child: Icon(
                    suspended ? Icons.pause_circle_outline : Icons.person,
                    color: suspended ? NebrasColors.rose : NebrasColors.emerald,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name.isEmpty ? 'قناة بلا اسم' : name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                _statusChip(suspended ? 'معلّقة' : 'نشطة', suspended),
              ],
            ),
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(bio, style: const TextStyle(fontSize: 12)),
            ],
            const SizedBox(height: 8),
            Text(
              'المعرّف: $id · المنشورات: ${channel['postCount'] ?? 0} · البلاغات المعلّقة: $reports',
              style: const TextStyle(
                fontSize: 11,
                color: NebrasColors.textMuted,
              ),
            ),
            if (_date(channel['updatedAtMs']).isNotEmpty)
              Text(
                'آخر تحديث: ${_date(channel['updatedAtMs'])}',
                style: const TextStyle(
                  fontSize: 10,
                  color: NebrasColors.textMuted,
                ),
              ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: suspended
                      ? NebrasColors.emerald
                      : NebrasColors.rose,
                ),
                onPressed: id.isEmpty
                    ? null
                    : () => _action(
                        action: suspended
                            ? 'unsuspend_channel'
                            : 'suspend_channel',
                        payload: {'channelId': id},
                        confirmation: suspended
                            ? 'سيُعاد نشر محتوى قناة «${name.isEmpty ? id : name}» للمستخدمين.'
                            : 'سيُخفى كل محتوى قناة «${name.isEmpty ? id : name}» فوراً، ولن تستطيع النشر حتى فك التعليق.',
                        success: suspended
                            ? 'فُكّ تعليق القناة.'
                            : 'عُلّقت القناة وأُخفي محتواها.',
                      ),
                icon: Icon(
                  suspended
                      ? Icons.play_circle_outline
                      : Icons.pause_circle_outline,
                ),
                label: Text(suspended ? 'فك التعليق' : 'تعليق القناة'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportedPostCard(Map<String, dynamic> entry) {
    final report = Map<String, dynamic>.from((entry['report'] as Map?) ?? {});
    final post = Map<String, dynamic>.from((entry['post'] as Map?) ?? {});
    final isOwner = context.read<AuthProvider>().isOwner;
    final postId = '${post['id'] ?? report['contentId'] ?? ''}';
    final channelId = '${post['channelId'] ?? ''}';
    final title = '${post['title'] ?? report['contentTitle'] ?? ''}'.trim();
    final sourceUrl = '${post['sourceUrl'] ?? report['sourceUrl'] ?? ''}'
        .trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _reasonChip('${report['reasonCode'] ?? 'other'}'),
                if (_date(report['createdAtMs']).isNotEmpty)
                  Text(
                    _date(report['createdAtMs']),
                    style: const TextStyle(
                      fontSize: 10,
                      color: NebrasColors.textMuted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title.isEmpty ? 'منشور بلا عنوان' : title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'القناة: ${post['channelName'] ?? 'غير معروفة'} · المعرّف: $postId',
              style: const TextStyle(
                fontSize: 11,
                color: NebrasColors.textMuted,
              ),
            ),
            if ('${report['note'] ?? ''}'.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'ملاحظة المُبلّغ: ${report['note']}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (sourceUrl.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(sourceUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('معاينة الملف'),
                  ),
                if (channelId.isNotEmpty)
                  OutlinedButton(
                    onPressed: () => _action(
                      action: 'suspend_channel',
                      payload: {'channelId': channelId},
                      confirmation:
                          'سيُخفى محتوى القناة المرتبطة بهذا البلاغ فوراً.',
                      success: 'عُلّقت القناة وأُخفي محتواها.',
                    ),
                    child: const Text('تعليق القناة'),
                  ),
                if (isOwner)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: NebrasColors.rose,
                    ),
                    onPressed: () => _action(
                      action: 'delete_post',
                      payload: {'postId': postId},
                      confirmation:
                          'سيُحذف المنشور وملفه وتعليقاته نهائياً. لا يمكن التراجع.',
                      success: 'حُذف المنشور المخالف نهائياً.',
                      destructive: true,
                    ),
                    child: const Text('حذف المنشور'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String text, bool suspended) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: (suspended ? NebrasColors.rose : NebrasColors.emerald).withValues(
        alpha: 0.14,
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: suspended ? NebrasColors.rose : NebrasColors.emerald,
      ),
    ),
  );

  Widget _reasonChip(String reason) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: NebrasColors.surfaceAlt,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text('بلاغ: $reason', style: const TextStyle(fontSize: 10)),
  );
}
