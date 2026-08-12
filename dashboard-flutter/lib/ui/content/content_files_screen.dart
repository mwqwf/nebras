import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/admin_stats.dart';
import '../../data/content_repository.dart';
import '../../data/sections_repository.dart';
import '../shell/dashboard_shell.dart';
import '../widgets/common.dart';

const int _pageSize = 10;

String _fmtSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
}

String _fmtDate(dynamic v) {
  DateTime? d;
  if (v is Timestamp) {
    d = v.toDate();
  } else if (v is String) {
    d = DateTime.tryParse(v);
  } else if (v is num) {
    d = DateTime.fromMillisecondsSinceEpoch(v.toInt());
  }
  if (d == null) return '—';
  return DateFormat('yyyy/MM/dd').format(d);
}

String _typeIcon(String t) => switch (t) {
      'video' => '🎬',
      'audio' => '🎵',
      _ => '📄',
    };

String _mimeFromName(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.epub')) return 'application/epub+zip';
  if (n.endsWith('.mp3')) return 'audio/mpeg';
  if (n.endsWith('.m4a')) return 'audio/mp4';
  if (n.endsWith('.wav')) return 'audio/wav';
  if (n.endsWith('.mp4')) return 'video/mp4';
  if (n.endsWith('.webm')) return 'video/webm';
  if (n.endsWith('.mov')) return 'video/quicktime';
  if (n.endsWith('.mkv')) return 'video/x-matroska';
  return 'application/octet-stream';
}

class ContentFilesScreen extends StatefulWidget {
  const ContentFilesScreen({super.key});

  @override
  State<ContentFilesScreen> createState() => _ContentFilesScreenState();
}

class _ContentFilesScreenState extends State<ContentFilesScreen> {
  final _repo = ContentRepository.instance;
  final _searchCtrl = TextEditingController();

  String _search = '';
  String _filterType = '';
  String _filterMain = '';
  String _filterListed = '';

  List<Map<String, dynamic>> _mains = [];
  List<ContentRow> _results = [];
  int _page = 1;
  bool _loading = false;
  bool _hasSearched = false;
  String? _error;

  final Set<String> _selected = {};

  bool get _hasActiveFilter =>
      _filterType.isNotEmpty || _filterMain.isNotEmpty || _filterListed.isNotEmpty;

  int get _totalPages => (_results.length / _pageSize).ceil();
  List<ContentRow> get _pageItems {
    final start = (_page - 1) * _pageSize;
    if (start >= _results.length) return const [];
    return _results.sublist(start, (start + _pageSize).clamp(0, _results.length));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureMains() async {
    if (_mains.isEmpty) {
      _mains = await SectionsRepository.instance.listMain();
      if (mounted) setState(() {});
    }
  }

  Future<void> _fetch() async {
    final q = _search.trim();
    if (q.isEmpty && !_hasActiveFilter) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _selected.clear();
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _hasSearched = true;
      _selected.clear();
    });
    try {
      final list = await _repo.listFiles(
        search: q,
        contentType: _filterType.isEmpty ? null : _filterType,
        mainSection: _filterMain.isEmpty ? null : _filterMain,
        isListed: _filterListed.isEmpty ? null : _filterListed == 'true',
      );
      setState(() {
        _results = list;
        _page = 1;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'تعذّر تحميل القائمة: $e';
        _loading = false;
      });
    }
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _search = '';
    _fetch();
  }

  // ─── الإجراءات ───────────────────────────────────────────
  Future<void> _openUpload() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NebrasColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _SingleUploadSheet(),
    );
    if (ok == true) _fetch();
  }

  Future<void> _openEdit(ContentRow row) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NebrasColors.surface,
      builder: (_) => _ContentEditor(row: row),
    );
    if (changed == true) _fetch();
  }

  void _openDetail(ContentRow row) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NebrasColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _DetailSheet(row: row),
    );
  }

  Future<void> _confirmDelete(ContentRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الملف'),
        content: Text('سيُحذف "${row.title}" نهائيّاً. هذا الإجراء لا يمكن التراجع عنه.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NebrasColors.rose),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      await _repo.removeFile(row.id);
      if (mounted) Navigator.pop(context);
      if (mounted) showSnack(context, 'تم الحذف.');
      _fetch();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) showSnack(context, 'فشل الحذف: $e', error: true);
    }
  }

  Future<void> _bulkDelete() async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف المحدد'),
        content: Text('سيُحذف ${_selected.length} عنصراً نهائيّاً. هذا الإجراء لا يمكن التراجع عنه.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NebrasColors.rose),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف الكل'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    var fail = 0;
    for (final id in _selected.toList()) {
      try {
        await _repo.removeFile(id);
      } catch (_) {
        fail++;
      }
    }
    if (mounted) Navigator.pop(context);
    if (mounted) showSnack(context, fail == 0 ? 'تم حذف المحدد.' : 'حُذف مع $fail إخفاق.', error: fail > 0);
    _fetch();
  }

  // ─── البناء ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('المحتوى الخاص بي', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('إدارة الملفات المرفوعة', style: TextStyle(fontSize: 12, color: NebrasColors.textMuted)),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _openUpload,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('رفع ملف'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _tabs(),
        const SizedBox(height: 12),
        // بحث
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'ابحث في الملفات...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.isNotEmpty
                ? IconButton(icon: const Icon(Icons.close), onPressed: _clearSearch)
                : null,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (v) {
            _search = v.trim();
            _fetch();
          },
        ),
        const SizedBox(height: 10),
        // فلاتر
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterDropdown(
              value: _filterType,
              hint: 'جميع الأنواع',
              items: const {'video': 'فيديو', 'audio': 'صوت', 'document': 'مستند'},
              onChanged: (v) {
                _filterType = v;
                _fetch();
              },
            ),
            _mainFilterDropdown(),
            _filterDropdown(
              value: _filterListed,
              hint: 'الكل (مدرج)',
              items: const {'true': 'مدرج', 'false': 'غير مدرج'},
              onChanged: (v) {
                _filterListed = v;
                _fetch();
              },
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: NebrasColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${_results.length} إجمالي', style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_error != null) _alert(_error!),
        _body(),
      ],
    );
  }

  Widget _tabs() {
    Widget tab(String label, bool active, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? NebrasColors.emerald : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                    color: active ? NebrasColors.emerald : NebrasColors.textMuted)),
          ),
        );
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: NebrasColors.border))),
      child: Row(
        children: [
          tab('الملفات المرفوعة', true, () {}),
          tab('رفع متعدد', false, () => DashboardNav.goTo('رفع متعدد')),
        ],
      ),
    );
  }

  Widget _filterDropdown({
    required String value,
    required String hint,
    required Map<String, String> items,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: NebrasColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButton<String>(
        value: value.isEmpty ? null : value,
        hint: Text(hint, style: const TextStyle(fontSize: 12)),
        underline: const SizedBox.shrink(),
        isDense: true,
        items: [
          DropdownMenuItem(value: '', child: Text(hint, style: const TextStyle(fontSize: 12))),
          ...items.entries.map((e) =>
              DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))),
        ],
        onChanged: (v) => onChanged(v ?? ''),
      ),
    );
  }

  Widget _mainFilterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: NebrasColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButton<String>(
        value: _filterMain.isEmpty ? null : _filterMain,
        hint: const Text('جميع الأقسام', style: TextStyle(fontSize: 12)),
        underline: const SizedBox.shrink(),
        isDense: true,
        onTap: _ensureMains,
        items: [
          const DropdownMenuItem(value: '', child: Text('جميع الأقسام', style: TextStyle(fontSize: 12))),
          ..._mains.map((m) => DropdownMenuItem(
                value: '${m['id']}',
                child: Text('${m['name'] ?? ''}', style: const TextStyle(fontSize: 12)),
              )),
        ],
        onChanged: (v) {
          _filterMain = v ?? '';
          _fetch();
        },
      ),
    );
  }

  Widget _alert(String msg) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: NebrasColors.rose.withValues(alpha: 0.1),
          border: Border.all(color: NebrasColors.rose.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(msg, style: const TextStyle(color: NebrasColors.rose, fontSize: 13)),
      );

  Widget _body() {
    if (_loading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()));
    }
    if (!_hasSearched) {
      return _stateBox(
        Icons.search,
        'الرجاء استخدام مربّع البحث للعثور على العناصر',
        'اكتب كلمة واضغط بحث، أو اختر فلترًا. لا يتمّ تحميل أيّ بيانات قبل ذلك حفاظًا على الأداء.',
      );
    }
    if (_results.isEmpty) {
      return _stateBox(Icons.inbox_outlined, 'لا توجد نتائج مطابقة — جرّب كلمة بحث أخرى', null);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // شريط التحديد الجماعي
        Row(
          children: [
            Checkbox(
              value: _selected.isNotEmpty && _selected.length == _results.length,
              tristate: true,
              onChanged: (v) {
                setState(() {
                  if (_selected.length == _results.length) {
                    _selected.clear();
                  } else {
                    _selected
                      ..clear()
                      ..addAll(_results.map((e) => e.id));
                  }
                });
              },
            ),
            const Text('تحديد الكل', style: TextStyle(fontSize: 13)),
            const Spacer(),
            if (_selected.isNotEmpty) ...[
              Text('${_selected.length} محدّد', style: const TextStyle(fontSize: 12, color: NebrasColors.textMuted)),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _bulkDelete,
                icon: const Icon(Icons.delete_outline, size: 16, color: NebrasColors.rose),
                label: const Text('حذف المحدد', style: TextStyle(color: NebrasColors.rose)),
              ),
            ],
          ],
        ),
        ..._pageItems.map(_tile),
        if (_totalPages > 1) _pagination(),
      ],
    );
  }

  Widget _stateBox(IconData icon, String title, String? hint) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        width: double.infinity,
        decoration: BoxDecoration(
          color: NebrasColors.surface,
          border: Border.all(color: NebrasColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, size: 44, color: NebrasColors.textMuted),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(hint, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: NebrasColors.textMuted)),
            ],
          ],
        ),
      );

  Widget _tile(ContentRow row) {
    final thumb = row.thumbnail ?? '';
    final selected = _selected.contains(row.id);
    return Card(
      child: InkWell(
        onTap: () => _openDetail(row),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(row.id);
                  } else {
                    _selected.remove(row.id);
                  }
                }),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: thumb.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: thumb, width: 44, height: 44, fit: BoxFit.cover,
                        memCacheWidth: 150, memCacheHeight: 150,
                        errorWidget: (_, __, ___) => _ph(row.contentType))
                    : _ph(row.contentType),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      row.isListed ? '${row.fileType} · ${_fmtSize(row.fileSize)}' : 'غير مدرج',
                      style: TextStyle(
                        fontSize: 11,
                        color: row.isListed ? NebrasColors.textMuted : NebrasColors.rose,
                      ),
                    ),
                    if (row.hasEngagement) _engagement(row),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_fmtDate(row.createdAt), style: const TextStyle(fontSize: 10, color: NebrasColors.textMuted)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _openEdit(row),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        color: NebrasColors.rose,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(row),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _engagement(ContentRow row) => Tooltip(
        message: 'عدّادات مجهولة من التطبيق: مشاهدة / تشغيل / إكمال',
        child: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            children: [
              _engChip(Icons.visibility_outlined, row.viewCount),
              const SizedBox(width: 8),
              _engChip(Icons.play_arrow_outlined, row.playCount),
              const SizedBox(width: 8),
              _engChip(Icons.check_circle_outline, row.completeCount),
            ],
          ),
        ),
      );

  Widget _engChip(IconData icon, int n) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: NebrasColors.textMuted),
          const SizedBox(width: 2),
          Text('$n', style: const TextStyle(fontSize: 10, color: NebrasColors.textMuted)),
        ],
      );

  Widget _ph(String type) => Container(
        width: 44, height: 44, color: NebrasColors.surfaceAlt,
        alignment: Alignment.center,
        child: Text(_typeIcon(type), style: const TextStyle(fontSize: 20)),
      );

  Widget _pagination() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _page > 1 ? () => setState(() => _page--) : null,
              child: const Text('← السابق'),
            ),
            Text('$_page / $_totalPages'),
            TextButton(
              onPressed: _page < _totalPages ? () => setState(() => _page++) : null,
              child: const Text('التالي →'),
            ),
          ],
        ),
      );
}

// ════════════ نافذة تفاصيل الملف ════════════
class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.row});
  final ContentRow row;

  @override
  Widget build(BuildContext context) {
    final md = row.metadata;
    Widget rowKV(String k, String v, {Widget? valueWidget}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 96, child: Text(k, style: const TextStyle(fontSize: 12, color: NebrasColors.textMuted))),
              Expanded(child: valueWidget ?? Text(v, style: const TextStyle(fontSize: 13))),
            ],
          ),
        );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Text('تفاصيل الملف', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          if ((row.thumbnail ?? '').isNotEmpty)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: row.thumbnail!, height: 140, fit: BoxFit.cover,
                  memCacheWidth: 400,
                ),
              ),
            ),
          const SizedBox(height: 12),
          rowKV('العنوان', row.title),
          if (row.author.isNotEmpty) rowKV('المؤلف', row.author),
          if (row.description.isNotEmpty) rowKV('الوصف', row.description),
          rowKV('ملف', row.filename),
          rowKV('النوع', row.fileType),
          rowKV('الحجم', _fmtSize(row.fileSize)),
          rowKV('مدرج', '', valueWidget: Text(row.isListed ? 'مدرج' : 'غير مدرج',
              style: TextStyle(fontSize: 13, color: row.isListed ? NebrasColors.emerald : NebrasColors.rose))),
          rowKV('الرفع', '${row.uploadType} — ${row.uploadStatus}'),
          if (row.fileUrl.isNotEmpty)
            rowKV('الرابط', '', valueWidget: InkWell(
              onTap: () => launchUrl(Uri.parse(row.fileUrl), mode: LaunchMode.externalApplication),
              child: const Text('افتح الملف', style: TextStyle(fontSize: 13, color: NebrasColors.emerald)),
            )),
          rowKV('تاريخ الإنشاء', _fmtDate(md['created_at'])),
          if (row.hasEngagement)
            rowKV('التفاعل', 'مشاهدات ${row.viewCount} · تشغيلات ${row.playCount} · إكمال ${row.completeCount}'),
        ],
      ),
    );
  }
}

// ════════════ نافذة رفع ملف مفرد ════════════
class _SingleUploadSheet extends StatefulWidget {
  const _SingleUploadSheet();

  @override
  State<_SingleUploadSheet> createState() => _SingleUploadSheetState();
}

class _SingleUploadSheetState extends State<_SingleUploadSheet> {
  final _repo = ContentRepository.instance;
  PlatformFile? _file;
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _author = TextEditingController();
  bool _listed = true;
  final _sel = SectionSelection();
  Uint8List? _thumbBytes;
  String? _thumbName;
  String? _error;
  bool _busy = false;
  double _progress = 0;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(withData: false, type: FileType.any);
    if (res == null || res.files.isEmpty) return;
    setState(() {
      _file = res.files.first;
      if (_title.text.trim().isEmpty) {
        final n = _file!.name;
        final dot = n.lastIndexOf('.');
        _title.text = dot > 0 ? n.substring(0, dot) : n;
      }
    });
  }

  Future<void> _pickThumb() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty || res.files.first.bytes == null) return;
    setState(() {
      _thumbBytes = res.files.first.bytes;
      _thumbName = res.files.first.name;
    });
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_file == null) {
      setState(() => _error = 'اختر ملفاً أولاً.');
      return;
    }
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'العنوان مطلوب.');
      return;
    }
    if ((_sel.mainId ?? '').isEmpty) {
      setState(() => _error = 'اختر القسم الرئيسي.');
      return;
    }
    if ((_sel.subId ?? '').isEmpty) {
      setState(() => _error = 'اختر قسماً فرعياً.');
      return;
    }
    setState(() => _busy = true);
    try {
      final mime = _mimeFromName(_file!.name);
      await _repo.createContentPath(
        filePath: _file!.path!,
        filename: _file!.name,
        mimeType: mime,
        thumbBytes: _thumbBytes,
        thumbName: _thumbName,
        metadata: {
          'title': _title.text.trim(),
          'author': _author.text.trim(),
          'description': _desc.text.trim(),
          'content_type': contentTypeFromMime(mime),
          'is_listed': _listed,
          'main_section': _sel.mainId,
          'main_section_id': _sel.mainId,
          'main_section_name': _sel.mainName,
          'subsection': _sel.subId,
          'subsection_name': _sel.subName,
          'secondary_subsection': _sel.secId,
          'secondary_subsection_name': _sel.secName,
        },
        onProgress: (p) => setState(() => _progress = p),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'فشل الرفع: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (context, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Text('رفع ملف', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(onPressed: _busy ? null : () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: NebrasColors.rose.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!, style: const TextStyle(color: NebrasColors.rose, fontSize: 12)),
                    ),
                    const SizedBox(height: 8),
                  ],
                  InkWell(
                    onTap: _busy ? null : _pick,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: NebrasColors.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_file?.name ?? 'انقر لتحديد ملف',
                          style: const TextStyle(color: NebrasColors.textMuted)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _title, decoration: const InputDecoration(labelText: 'العنوان *')),
                  const SizedBox(height: 12),
                  TextField(controller: _desc, maxLines: 2, decoration: const InputDecoration(labelText: 'الوصف')),
                  const SizedBox(height: 12),
                  TextField(controller: _author, decoration: const InputDecoration(labelText: 'المؤلف (اختياري)')),
                  const SizedBox(height: 14),
                  const Text('القسم', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  SectionPicker(selection: _sel, onChanged: () => setState(() {})),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('مدرج', style: TextStyle(fontSize: 13)),
                    value: _listed,
                    onChanged: (v) => setState(() => _listed = v),
                  ),
                  Row(
                    children: [
                      if (_thumbBytes != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(_thumbBytes!, width: 50, height: 50, fit: BoxFit.cover),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() {
                            _thumbBytes = null;
                            _thumbName = null;
                          }),
                        ),
                      ] else
                        OutlinedButton.icon(
                          onPressed: _pickThumb,
                          icon: const Icon(Icons.image_outlined, size: 18),
                          label: const Text('إضافة صورة مصغرة'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_busy) ...[
                    LinearProgressIndicator(value: _progress / 100),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(_busy ? 'جارٍ الرفع… ${_progress.round()}%' : 'بدء الرفع'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════ نافذة تعديل المحتوى ════════════
class _ContentEditor extends StatefulWidget {
  const _ContentEditor({required this.row});
  final ContentRow row;

  @override
  State<_ContentEditor> createState() => _ContentEditorState();
}

class _ContentEditorState extends State<_ContentEditor> {
  final _repo = ContentRepository.instance;
  late final _title = TextEditingController(text: widget.row.title);
  late final _author = TextEditingController(text: widget.row.author);
  late final _desc = TextEditingController(text: widget.row.description);
  late bool _listed = widget.row.isListed;
  late String _type = widget.row.contentType;
  bool _move = false;
  final _sel = SectionSelection();
  Uint8List? _thumbBytes;
  String? _thumbName;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final md = widget.row.metadata;
    _sel.mainId = _str(md['main_section']);
    _sel.subId = _str(md['subsection']);
    _sel.secId = _str(md['secondary_subsection']);
  }

  String? _str(dynamic v) {
    final s = '${v ?? ''}'.trim();
    return s.isEmpty ? null : s;
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickThumb() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (res != null && res.files.single.bytes != null) {
      setState(() {
        _thumbBytes = res.files.single.bytes;
        _thumbName = res.files.single.name;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _repo.updateContent(
        widget.row.id,
        title: _title.text,
        author: _author.text,
        description: _desc.text,
        isListed: _listed,
        contentType: _type,
        move: _move,
        mainSection: _move ? _sel.mainId : null,
        subsection: _move ? _sel.subId : null,
        secondarySubsection: _move ? _sel.secId : null,
        thumbBytes: _thumbBytes,
        thumbName: _thumbName,
      );
      AdminStats.bumpEdit(); // عدّاد لوحة الشرف — أفضل جهد.
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, 'فشل الحفظ: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('تعديل الملف', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'العنوان')),
            const SizedBox(height: 12),
            TextField(controller: _author, decoration: const InputDecoration(labelText: 'المؤلف')),
            const SizedBox(height: 12),
            TextField(controller: _desc, maxLines: 3, decoration: const InputDecoration(labelText: 'الوصف')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: ['document', 'audio', 'video'].contains(_type) ? _type : 'document',
              decoration: const InputDecoration(labelText: 'نوع الملف'),
              items: const [
                DropdownMenuItem(value: 'document', child: Text('مستند')),
                DropdownMenuItem(value: 'audio', child: Text('صوت')),
                DropdownMenuItem(value: 'video', child: Text('فيديو')),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'document'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('مدرج'),
              value: _listed,
              onChanged: (v) => setState(() => _listed = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('نقل إلى قسم آخر'),
              subtitle: const Text('فعّل لإعادة تصنيف المحتوى', style: TextStyle(fontSize: 11)),
              value: _move,
              onChanged: (v) => setState(() => _move = v),
            ),
            if (_move) ...[
              const SizedBox(height: 8),
              SectionPicker(selection: _sel, onChanged: () => setState(() {})),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickThumb,
              icon: const Icon(Icons.image_outlined),
              label: Text(_thumbBytes != null ? 'صورة جديدة (${_thumbName ?? ''})' : 'تغيير الصورة'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('حفظ التغييرات'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
