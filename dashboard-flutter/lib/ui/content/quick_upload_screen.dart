import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../core/firestore_refs.dart';
import '../../data/admin_stats.dart';
import '../../data/chat_repository.dart' show guessContentType, formatBytes;
import '../../data/content_repository.dart';
import '../../data/sanitize.dart';
import '../../data/unified_firestore.dart';
import '../../services/notifications_service.dart';
import '../widgets/common.dart';
import '../../core/smart_title.dart';

/// «الرفع السريع» ⚡ — أسرع طريق من ملفّ على الهاتف (أو رابط يوتيوب أو
/// «مشاركة إلى نبراس» من أيّ تطبيق) إلى محتوى منشور: عنوان مقترح تلقائيّاً،
/// آخر قسم مستخدَم محفوظ، كشف تكرار، وطابور استئناف يصمد أمام إغلاق التطبيق.
class QuickUploadScreen extends StatefulWidget {
  const QuickUploadScreen({super.key, this.sharedFilePath, this.sharedText});

  /// ملفّ وصل عبر «مشاركة إلى نبراس».
  final String? sharedFilePath;

  /// نصّ/رابط وصل عبر المشاركة (يُعامل كرابط يوتيوب إن كان كذلك).
  final String? sharedText;

  @override
  State<QuickUploadScreen> createState() => _QuickUploadScreenState();
}

/// مُدخل طابور الاستئناف (يُخزَّن JSON في ملفّ داخل مستندات التطبيق).
class _PendingEntry {
  _PendingEntry({
    required this.path,
    required this.name,
    required this.title,
    required this.mainId,
    required this.mainName,
    required this.subId,
    required this.subName,
    required this.secId,
    required this.secName,
    required this.addedAtMs,
  });

  final String path;
  final String name;
  final String title;
  final String? mainId, mainName, subId, subName, secId, secName;
  final int addedAtMs;

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'title': title,
        'mainId': mainId,
        'mainName': mainName,
        'subId': subId,
        'subName': subName,
        'secId': secId,
        'secName': secName,
        'addedAtMs': addedAtMs,
      };

  static _PendingEntry fromJson(Map<String, dynamic> m) => _PendingEntry(
        path: '${m['path'] ?? ''}',
        name: '${m['name'] ?? ''}',
        title: '${m['title'] ?? ''}',
        mainId: m['mainId'] as String?,
        mainName: m['mainName'] as String?,
        subId: m['subId'] as String?,
        subName: m['subName'] as String?,
        secId: m['secId'] as String?,
        secName: m['secName'] as String?,
        addedAtMs: (m['addedAtMs'] is num) ? (m['addedAtMs'] as num).toInt() : 0,
      );
}

class _QuickUploadScreenState extends State<QuickUploadScreen> {
  final _repo = ContentRepository.instance;
  final _titleCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  final _sel = SectionSelection();

  String? _filePath;
  String _fileName = '';
  int _fileSize = 0;

  bool _busy = false;
  double _progress = 0;
  String _phase = '';
  List<_PendingEntry> _pending = [];

  // نفس مفاتيح «آخر قسم» المستخدمة في شاشة الرفع المتعدّد — تجربة موحّدة.
  static const _kMain = 'up_last_main';
  static const _kMainName = 'up_last_main_name';
  static const _kSub = 'up_last_sub';
  static const _kSubName = 'up_last_sub_name';
  static const _kSec = 'up_last_sec';
  static const _kSecName = 'up_last_sec_name';

  @override
  void initState() {
    super.initState();
    _initFromShare();
    _loadLastSections();
    _loadPending();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  void _initFromShare() {
    final p = widget.sharedFilePath;
    if (p != null && p.isNotEmpty) {
      _setFile(p);
    }
    final t = widget.sharedText?.trim() ?? '';
    if (t.isNotEmpty) {
      if (_looksLikeYoutube(t)) {
        _linkCtrl.text = t;
      } else if (_titleCtrl.text.isEmpty) {
        _titleCtrl.text = t;
      }
    }
  }

  void _setFile(String path) {
    final f = File(path);
    final name = path.split(RegExp(r'[\\/]')).last;
    _filePath = path;
    _fileName = name;
    try {
      _fileSize = f.lengthSync();
    } catch (_) {
      _fileSize = 0;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      _titleCtrl.text = _suggestTitle(name);
    }
    setState(() {});
  }

  /// عنوان مقترح من اسم الملفّ — استخراج ذكيّ (يزيل الترقيم وبصمات المواقع
  /// وأنماط المسجّلات)؛ الاسم الآليّ البحت يُترك فارغاً ليكتبه المشرف.
  static String _suggestTitle(String filename) =>
      smartTitleFromFileName(filename);

  static bool _looksLikeYoutube(String t) =>
      RegExp(r'(youtube\.com|youtu\.be)/', caseSensitive: false).hasMatch(t);

  Future<void> _loadLastSections() async {
    try {
      final p = await SharedPreferences.getInstance();
      _sel
        ..mainId = p.getString(_kMain)
        ..mainName = p.getString(_kMainName)
        ..subId = p.getString(_kSub)
        ..subName = p.getString(_kSubName)
        ..secId = p.getString(_kSec)
        ..secName = p.getString(_kSecName);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveLastSections() async {
    try {
      final p = await SharedPreferences.getInstance();
      Future<void> set(String k, String? v) =>
          (v == null || v.isEmpty) ? p.remove(k) : p.setString(k, v);
      await set(_kMain, _sel.mainId);
      await set(_kMainName, _sel.mainName);
      await set(_kSub, _sel.subId);
      await set(_kSubName, _sel.subName);
      await set(_kSec, _sel.secId);
      await set(_kSecName, _sel.secName);
    } catch (_) {}
  }

  // ─── طابور الاستئناف ─────────────────────────────────────

  Future<File> _pendingFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nebras_pending_uploads.json');
  }

  Future<void> _loadPending() async {
    try {
      final f = await _pendingFile();
      if (!await f.exists()) return;
      final list = jsonDecode(await f.readAsString());
      if (list is List) {
        _pending = list
            .whereType<Map>()
            .map((e) => _PendingEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _savePending() async {
    try {
      final f = await _pendingFile();
      await f.writeAsString(
          jsonEncode(_pending.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _addPending(_PendingEntry e) async {
    _pending.removeWhere((p) => p.path == e.path);
    _pending.add(e);
    await _savePending();
    if (mounted) setState(() {});
  }

  Future<void> _removePending(String path) async {
    _pending.removeWhere((p) => p.path == path);
    await _savePending();
    if (mounted) setState(() {});
  }

  // ─── كشف التكرار ─────────────────────────────────────────

  static String _normalizeForDup(String s) {
    var t = s.toLowerCase();
    final dot = t.lastIndexOf('.');
    if (dot > 0) t = t.substring(0, dot);
    t = t.replaceAll(RegExp(r'[\s_\-]+'), '');
    return t;
  }

  /// true = تابِع الرفع، false = ألغِ.
  Future<bool> _dupCheckPasses() async {
    try {
      final rows = await UnifiedFirestore.instance.listFileRowsMerged();
      final normName = _normalizeForDup(_fileName);
      final normTitle = _normalizeForDup(_titleCtrl.text.trim());
      final hit = rows.where((r) {
        final rTitle = _normalizeForDup('${r['title'] ?? ''}');
        final rFile = _normalizeForDup('${r['filename'] ?? ''}');
        final sizeMatch = _fileSize > 0 && r['fileSize'] == _fileSize;
        return sizeMatch ||
            (normTitle.isNotEmpty && rTitle == normTitle) ||
            (normName.isNotEmpty && (rFile == normName || rTitle == normName));
      }).toList();
      if (hit.isEmpty || !mounted) return true;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('⚠️ محتوى مشابه موجود'),
            content: Text(
              'يبدو أنّ هذا الملفّ مرفوع مسبقاً:\n«${hit.first['title'] ?? hit.first['filename'] ?? ''}»\n\nهل تريد المتابعة على أيّ حال؟',
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('إلغاء')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('متابعة الرفع')),
            ],
          ),
        ),
      );
      return ok == true;
    } catch (_) {
      return true; // فشل الفحص لا يمنع الرفع.
    }
  }

  // ─── التنفيذ ─────────────────────────────────────────────

  Future<void> _pickFile() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.any, withData: false);
    final p = res?.files.firstOrNull?.path;
    if (p != null) _setFile(p);
  }

  Map<String, dynamic> _metadata(String title) => {
        'title': title,
        'author': '',
        'description': '',
        'is_listed': true,
        'main_section': _sel.mainId,
        'main_section_id': _sel.mainId,
        'main_section_name': _sel.mainName,
        'subsection': _sel.subId,
        'subsection_name': _sel.subName,
        'secondary_subsection': _sel.secId,
        'secondary_subsection_name': _sel.secName,
      };

  bool get _isYoutubeMode =>
      _filePath == null && _looksLikeYoutube(_linkCtrl.text.trim());

  bool get _canPublish {
    if (_busy) return false;
    if (_sel.mainId == null || _sel.mainId!.isEmpty) return false;
    if (_titleCtrl.text.trim().isEmpty) return false;
    return _filePath != null || _isYoutubeMode;
  }

  Future<void> _publish() async {
    final title = _titleCtrl.text.trim();
    await _saveLastSections();
    setState(() {
      _busy = true;
      _progress = 0;
      _phase = 'يتحقّق…';
    });
    try {
      if (_isYoutubeMode) {
        await _publishYoutube(title);
      } else {
        if (!await _dupCheckPasses()) {
          setState(() => _busy = false);
          return;
        }
        await _publishFile(title, _filePath!, _fileName);
      }
      AdminStats.bumpUpload();
      NotificationsService.notifySectionUpload(
        sectionId: _sel.mainId ?? '',
        sectionName: _sel.mainName ?? 'نبراس',
        title: title,
      );
      if (mounted) {
        showSnack(context, '🎉 نُشر «$title» بنجاح!');
        setState(() {
          _filePath = null;
          _fileName = '';
          _fileSize = 0;
          _titleCtrl.clear();
          _linkCtrl.clear();
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, 'فشل النشر: $e', error: true);
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _publishFile(String title, String path, String name) async {
    // سجّل في طابور الاستئناف قبل البدء — يُحذف عند النجاح.
    await _addPending(_PendingEntry(
      path: path,
      name: name,
      title: title,
      mainId: _sel.mainId,
      mainName: _sel.mainName,
      subId: _sel.subId,
      subName: _sel.subName,
      secId: _sel.secId,
      secName: _sel.secName,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    setState(() => _phase = 'يرفع الملفّ…');
    await _repo.createContentPath(
      filePath: path,
      filename: name,
      mimeType: guessContentType(name),
      metadata: _metadata(title),
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    await _removePending(path);
  }

  Future<void> _publishYoutube(String title) async {
    setState(() => _phase = 'ينشر الرابط…');
    final url = _linkCtrl.text.trim();
    final id = 'yt_${DateTime.now().millisecondsSinceEpoch}';
    final doc = stripNullsDeep({
      'id': id,
      'title': title,
      'description': '',
      'author': '',
      'content_type': 'youtube',
      'video_url': url,
      'sourceUrl': url,
      'source_url': url,
      'is_listed': true,
      'main_section': _sel.mainId,
      'main_section_id': _sel.mainId,
      'main_section_name': _sel.mainName,
      'subsection': _sel.subId,
      'subsection_name': _sel.subName,
      'secondary_subsection': _sel.secId,
      'secondary_subsection_name': _sel.secName,
      'createdAt': FieldValue.serverTimestamp(),
    }) as Map<String, dynamic>;
    await nebrasFirestore()
        .collection(FsPaths.contentYoutube)
        .doc(id)
        .set(doc);
  }

  Future<void> _resumePending(_PendingEntry e) async {
    if (!File(e.path).existsSync()) {
      showSnack(context, 'الملفّ لم يعُد موجوداً على الجهاز.', error: true);
      await _removePending(e.path);
      return;
    }
    _sel
      ..mainId = e.mainId
      ..mainName = e.mainName
      ..subId = e.subId
      ..subName = e.subName
      ..secId = e.secId
      ..secName = e.secName;
    _titleCtrl.text = e.title;
    _setFile(e.path);
    await _publish();
  }

  // ─── البناء ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الرفع السريع ⚡')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_pending.isNotEmpty) _pendingCard(),
          _sourceCard(),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'العنوان'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SectionPicker(
                  selection: _sel, onChanged: () => setState(() {})),
            ),
          ),
          const SizedBox(height: 16),
          if (_busy) ...[
            LinearProgressIndicator(
              value: _progress > 0 ? _progress / 100 : null,
              minHeight: 5,
              color: NebrasColors.emerald,
              backgroundColor: NebrasColors.border,
            ),
            const SizedBox(height: 6),
            Text('$_phase ${_progress > 0 ? '${_progress.toStringAsFixed(0)}%' : ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, color: NebrasColors.textMuted)),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _canPublish ? _publish : null,
              icon: const Icon(Icons.rocket_launch),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('انشر الآن', style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'يُنشر مباشرة في القسم المحدّد ويصل متابعيه فوراً 🔔',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: NebrasColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _pendingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.restore, size: 18, color: NebrasColors.amber),
                SizedBox(width: 8),
                Text('رفعات لم تكتمل',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5)),
              ],
            ),
            const SizedBox(height: 6),
            for (final e in _pending)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(e.title.isEmpty ? e.name : e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
                subtitle: Text(e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_arrow,
                          color: NebrasColors.emerald, size: 20),
                      tooltip: 'استئناف',
                      onPressed: _busy ? null : () => _resumePending(e),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: NebrasColors.rose, size: 18),
                      tooltip: 'إزالة',
                      onPressed: () => _removePending(e.path),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sourceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_filePath != null) ...[
              Row(
                children: [
                  const Icon(Icons.insert_drive_file,
                      color: NebrasColors.emerald, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_fileName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        if (_fileSize > 0)
                          Text(formatBytes(_fileSize),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: NebrasColors.textMuted)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _filePath = null;
                              _fileName = '';
                              _fileSize = 0;
                            }),
                  ),
                ],
              ),
            ] else ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickFile,
                icon: const Icon(Icons.attach_file),
                label: const Text('اختر ملفّاً من الهاتف'),
              ),
              const SizedBox(height: 10),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('أو',
                        style: TextStyle(
                            fontSize: 11, color: NebrasColors.textMuted)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _linkCtrl,
                decoration: const InputDecoration(
                  labelText: 'رابط يوتيوب',
                  hintText: 'https://youtube.com/watch?v=…',
                  prefixIcon: Icon(Icons.play_circle_outline,
                      color: NebrasColors.rose),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 4),
            const Text(
              '💡 يمكنك أيضاً «مشاركة» أيّ ملفّ من أيّ تطبيق واختيار نبراس.',
              style: TextStyle(fontSize: 10.5, color: NebrasColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
