import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../data/admin_stats.dart';
import '../../data/content_repository.dart';
import '../shell/dashboard_shell.dart';
import '../widgets/common.dart';
import '../../core/smart_title.dart';

const int _kMaxBytes = 500 * 1024 * 1024; // 500MB

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

String _mimeFromName(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.epub')) return 'application/epub+zip';
  if (n.endsWith('.mp3')) return 'audio/mpeg';
  if (n.endsWith('.m4a')) return 'audio/mp4';
  if (n.endsWith('.wav')) return 'audio/wav';
  if (n.endsWith('.ogg')) return 'audio/ogg';
  if (n.endsWith('.aac')) return 'audio/aac';
  if (n.endsWith('.flac')) return 'audio/flac';
  if (n.endsWith('.mp4')) return 'video/mp4';
  if (n.endsWith('.webm')) return 'video/webm';
  if (n.endsWith('.mov')) return 'video/quicktime';
  if (n.endsWith('.mkv')) return 'video/x-matroska';
  return 'application/octet-stream';
}

String _iconFor(String name) {
  final ct = contentTypeFromMime(_mimeFromName(name));
  if (ct == 'video') return '🎬';
  if (ct == 'audio') return '🎵';
  return '📄';
}

class _QItem {
  _QItem({
    required this.file,
    required this.title,
    required this.description,
    required this.author,
    required this.isListed,
    required this.sel,
    this.thumbBytes,
    this.thumbName,
  });

  static int _seq = 0;
  final int id = _seq++;
  final PlatformFile file;
  String title;
  String description;
  String author;
  bool isListed;
  SectionSelection sel;
  Uint8List? thumbBytes;
  String? thumbName;

  String status = 'queued'; // queued | uploading | committing | completed | failed
  double progress = 0;
  String? error;
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _repo = ContentRepository.instance;
  final List<_QItem> _queue = [];
  int _concurrency = 3;
  bool _isUploading = false;
  bool _isPaused = false;
  bool _stopRequested = false;
  String? _lastError;

  // آخر اختيار أقسام محفوظ (يبقى بعد إغلاق التطبيق).
  SectionSelection _lastSections = SectionSelection();

  static const _kMain = 'up_last_main';
  static const _kMainName = 'up_last_main_name';
  static const _kSub = 'up_last_sub';
  static const _kSubName = 'up_last_sub_name';
  static const _kSec = 'up_last_sec';
  static const _kSecName = 'up_last_sec_name';

  @override
  void initState() {
    super.initState();
    _loadLast();
  }

  Future<void> _loadLast() async {
    try {
      final p = await SharedPreferences.getInstance();
      _lastSections = SectionSelection()
        ..mainId = p.getString(_kMain)
        ..mainName = p.getString(_kMainName)
        ..subId = p.getString(_kSub)
        ..subName = p.getString(_kSubName)
        ..secId = p.getString(_kSec)
        ..secName = p.getString(_kSecName);
    } catch (_) {}
  }

  Future<void> _saveLast(SectionSelection s) async {
    _lastSections = s;
    try {
      final p = await SharedPreferences.getInstance();
      Future<void> set(String k, String? v) =>
          (v == null || v.isEmpty) ? p.remove(k) : p.setString(k, v);
      await set(_kMain, s.mainId);
      await set(_kMainName, s.mainName);
      await set(_kSub, s.subId);
      await set(_kSubName, s.subName);
      await set(_kSec, s.secId);
      await set(_kSecName, s.secName);
    } catch (_) {}
  }

  int get _completed => _queue.where((q) => q.status == 'completed').length;
  bool get _hasQueue => _queue.isNotEmpty;
  bool get _canStart =>
      !_isUploading && _queue.any((q) => q.status == 'queued' || q.status == 'failed');
  bool get _allDone =>
      _queue.isNotEmpty && _queue.every((q) => q.status == 'completed');

  // ─── إضافة / تعديل بند عبر النافذة ───────────────────────
  Future<void> _openEditor({_QItem? editing}) async {
    final result = await showModalBottomSheet<_EditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NebrasColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ItemEditorSheet(
        editing: editing,
        lastSections: _lastSections,
      ),
    );
    if (result == null) return;

    if (editing != null) {
      setState(() {
        editing.title = result.title;
        editing.description = result.description;
        editing.author = result.author;
        editing.isListed = result.isListed;
        editing.sel = result.sel;
        if (result.thumbBytes != null) {
          editing.thumbBytes = result.thumbBytes;
          editing.thumbName = result.thumbName;
        }
      });
    } else {
      final multi = result.files.length > 1;
      setState(() {
        for (final f in result.files) {
          _queue.add(_QItem(
            file: f,
            title: multi
                ? smartTitleOrBasename(f.name)
                : (result.title.isEmpty
                    ? smartTitleOrBasename(f.name)
                    : result.title),
            description: result.description,
            author: result.author,
            isListed: result.isListed,
            sel: result.sel.copy(),
            thumbBytes: result.thumbBytes,
            thumbName: result.thumbName,
          ));
        }
      });
      await _saveLast(result.sel.copy());
    }
  }

  void _moveItem(int index, int dir) {
    final to = index + dir;
    if (to < 0 || to >= _queue.length) return;
    setState(() {
      final it = _queue.removeAt(index);
      _queue.insert(to, it);
    });
  }

  Future<void> _removeItem(_QItem it) async {
    if (it.status == 'uploading' || it.status == 'committing') {
      final ok = await _confirm('هذا الملف يُرفع حالياً. هل تريد حذفه ومتابعة بقية الطابور؟');
      if (ok != true) return;
    }
    setState(() => _queue.remove(it));
  }

  Future<void> _reset() async {
    if (_isUploading) {
      final ok = await _confirm('هذا الملف يُرفع حالياً. هل تريد حذفه ومتابعة بقية الطابور؟');
      if (ok != true) return;
    }
    setState(() {
      _queue.clear();
      _isUploading = false;
      _isPaused = false;
      _stopRequested = true;
      _lastError = null;
    });
  }

  void _clearCompleted() {
    setState(() => _queue.removeWhere((q) => q.status == 'completed'));
  }

  Future<bool?> _confirm(String msg) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(msg),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
          ],
        ),
      );

  // ─── محرّك الرفع: تخزين متوازٍ + كتابة قاعدة بترتيب الاختيار ──────
  Future<void> _startAll() async {
    final pending = _queue.where((q) => q.status == 'queued' || q.status == 'failed').toList();
    if (pending.isEmpty) return;
    for (final it in pending) {
      it.status = 'queued';
      it.error = null;
      it.progress = 0;
    }
    setState(() {
      _isUploading = true;
      _isPaused = false;
      _stopRequested = false;
      _lastError = null;
    });

    final completers = {for (final it in pending) it.id: Completer<Map<String, dynamic>?>()};
    var next = 0, active = 0;

    void pump() {
      if (_stopRequested || _isPaused) return;
      while (active < _concurrency && next < pending.length) {
        final it = pending[next++];
        active++;
        _uploadOne(it).then((p) {
          if (!completers[it.id]!.isCompleted) completers[it.id]!.complete(p);
        }).catchError((e) {
          if (mounted) setState(() => it.error = '$e');
          if (!completers[it.id]!.isCompleted) completers[it.id]!.complete(null);
        }).whenComplete(() {
          active--;
          pump();
        });
      }
    }

    pump();
    _pump = pump;

    for (final it in pending) {
      if (_stopRequested) break;
      while (_isPaused && !_stopRequested) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      if (_stopRequested) break;
      final payload = await completers[it.id]!.future;
      if (payload == null) {
        if (mounted && it.status != 'failed') setState(() => it.status = 'failed');
        continue;
      }
      if (mounted) setState(() => it.status = 'committing');
      try {
        await _repo.commitPrepared(payload);
        AdminStats.bumpUpload(); // عدّاد لوحة الشرف — أفضل جهد.
        if (mounted) setState(() {
          it.status = 'completed';
          it.progress = 100;
        });
      } catch (e) {
        if (mounted) setState(() {
          it.status = 'failed';
          it.error = '$e';
        });
      }
    }
    if (mounted) setState(() => _isUploading = false);
  }

  void Function()? _pump;

  Future<Map<String, dynamic>?> _uploadOne(_QItem it) async {
    if (_stopRequested) return null;
    if (mounted) setState(() => it.status = 'uploading');
    final mime = _mimeFromName(it.file.name);
    final metadata = <String, dynamic>{
      'title': it.title.trim().isEmpty ? it.file.name : it.title.trim(),
      'author': it.author.trim(),
      'description': it.description.trim(),
      'content_type': contentTypeFromMime(mime),
      'is_listed': it.isListed,
      'main_section': it.sel.mainId,
      'main_section_id': it.sel.mainId,
      'main_section_name': it.sel.mainName,
      'subsection': it.sel.subId,
      'subsection_name': it.sel.subName,
      'secondary_subsection': it.sel.secId,
      'secondary_subsection_name': it.sel.secName,
    };
    final path = it.file.path;
    if (path == null) throw Exception('تعذّر قراءة الملفّ.');
    return _repo.prepareUploadPath(
      filePath: path,
      filename: it.file.name,
      mimeType: mime,
      metadata: metadata,
      thumbBytes: it.thumbBytes,
      thumbName: it.thumbName,
      onProgress: (p) {
        if (mounted) setState(() => it.progress = p);
      },
      isAborted: () => _stopRequested,
    );
  }

  void _pause() => setState(() => _isPaused = true);
  void _resume() {
    setState(() => _isPaused = false);
    _pump?.call();
  }

  void _stop() {
    setState(() {
      _stopRequested = true;
      _isPaused = false;
      _isUploading = false;
      for (final q in _queue) {
        if (q.status == 'uploading' || q.status == 'committing') {
          q.status = 'queued';
          q.progress = 0;
        }
      }
    });
  }

  // ─── البناء ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ترويسة
        const Text('الرفع المتعدد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'اصطف ملفات بمعلوماتها. رفع التخزين بالتوازي؛ كتابة القاعدة تتبع ترتيب اختيارك حرفياً.',
          style: TextStyle(color: NebrasColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        // إجراءات الترويسة
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('رفع متوازٍ', style: TextStyle(fontSize: 12, color: NebrasColors.textMuted)),
              const SizedBox(width: 6),
              DropdownButton<int>(
                value: _concurrency,
                isDense: true,
                onChanged: _isUploading ? null : (v) => setState(() => _concurrency = v ?? 3),
                items: [1, 2, 3, 4, 5]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
              ),
            ]),
            OutlinedButton(
              onPressed: _hasQueue ? _reset : null,
              child: const Text('تفريغ الطابور'),
            ),
            FilledButton.icon(
              onPressed: _openEditor,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('أضف ملفات إلى الطابور'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _tabs(),
        const SizedBox(height: 12),
        _summaryStrip(),
        if (_lastError != null) ...[
          const SizedBox(height: 8),
          _alert(_lastError!, NebrasColors.rose),
        ],
        if (_allDone) ...[
          const SizedBox(height: 8),
          _alert('اكتمل رفع جميع الملفات.', NebrasColors.emerald),
        ],
        const SizedBox(height: 10),
        _hints(),
        const SizedBox(height: 10),
        if (!_hasQueue)
          _emptyState()
        else
          ..._queue.asMap().entries.map((e) => _queueTile(e.key, e.value)),
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
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: NebrasColors.border)),
      ),
      child: Row(
        children: [
          tab('الملفات المرفوعة', false, () => DashboardNav.goTo('المحتوى')),
          tab('رفع متعدد', true, () {}),
        ],
      ),
    );
  }

  Widget _summaryStrip() {
    final total = _queue.length;
    final pct = total > 0 ? _completed / total : 0.0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NebrasColors.surface,
        border: Border.all(color: NebrasColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$total', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              const Text('ملف في الطابور', style: TextStyle(fontSize: 12, color: NebrasColors.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(value: pct, minHeight: 6, color: NebrasColors.emerald),
          ),
          const SizedBox(height: 4),
          Text('$_completed من $total مكتمل', style: const TextStyle(fontSize: 12, color: NebrasColors.textMuted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_isUploading) ...[
                if (_isPaused)
                  OutlinedButton(onPressed: _resume, child: const Text('استئناف الكل'))
                else
                  OutlinedButton(onPressed: _pause, child: const Text('إيقاف مؤقت للكل')),
                OutlinedButton(onPressed: _stop, child: const Text('إيقاف الرفع')),
              ] else ...[
                OutlinedButton(
                  onPressed: _completed > 0 ? _clearCompleted : null,
                  child: const Text('مسح المكتمل'),
                ),
                FilledButton.icon(
                  onPressed: _canStart ? _startAll : null,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('بدء رفع الكل'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _alert(String msg, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(msg, style: TextStyle(color: color, fontSize: 13)),
      );

  Widget _hints() {
    const notes = [
      'رفع التخزين يعمل بالتوازي للسرعة. كتابة قاعدة البيانات تتبع ترتيب اختيارك حرفياً — أوّل ملف اخترته يُحفَظ أوّلاً دائماً.',
      'ترتيب الحفظ في القاعدة = ترتيب الاختيار، حتى لو انتهى ملف أصغر قبل ملف أكبر.',
      'يمكنك حذف أي ملف في أي لحظة — حتى أثناء رفعه فعلياً — دون إيقاف باقي الطابور.',
      'اسحب الصفوف لإعادة الترتيب قبل بدء الرفع (استخدم الأسهم).',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: notes
          .map((n) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text('• $n',
                    style: const TextStyle(fontSize: 11, color: NebrasColors.textMuted, height: 1.5)),
              ))
          .toList(),
    );
  }

  Widget _emptyState() => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        decoration: BoxDecoration(
          color: NebrasColors.surface,
          border: Border.all(color: NebrasColors.border, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            const Icon(Icons.cloud_upload_outlined, size: 44, color: NebrasColors.textMuted),
            const SizedBox(height: 10),
            const Text('لا توجد ملفات في الطابور بعد. أضف أول ملف لتبدأ.',
                textAlign: TextAlign.center, style: TextStyle(color: NebrasColors.textMuted)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _openEditor, child: const Text('أضف ملفات إلى الطابور')),
          ],
        ),
      );

  Widget _queueTile(int index, _QItem it) {
    final chip = switch (it.status) {
      'uploading' => ('جاري الرفع', NebrasColors.amber),
      'committing' => ('جاري الحفظ في القاعدة', NebrasColors.amber),
      'completed' => ('تم', NebrasColors.emerald),
      'failed' => ('فشل', NebrasColors.rose),
      _ => ('في الطابور', NebrasColors.textMuted),
    };
    final chain = [it.sel.mainName, it.sel.subName, it.sel.secName]
        .where((e) => (e ?? '').trim().isNotEmpty)
        .join(' › ');
    final busy = it.status == 'uploading' || it.status == 'committing';
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              alignment: Alignment.center,
              padding: const EdgeInsets.only(top: 2),
              child: Text('${index + 1}',
                  style: const TextStyle(fontSize: 12, color: NebrasColors.textMuted)),
            ),
            const SizedBox(width: 4),
            Text(_iconFor(it.file.name), style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(it.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: chip.$2.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(chip.$1, style: TextStyle(fontSize: 10, color: chip.$2)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${it.file.name} • ${_fmtSize(it.file.size)}${chain.isNotEmpty ? ' • $chain' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: NebrasColors.textMuted),
                  ),
                  if (busy || (it.status == 'completed' && it.progress > 0))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(100),
                              child: LinearProgressIndicator(
                                  value: it.progress / 100, minHeight: 5, color: chip.$2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('${it.progress.round()}%', style: const TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                  if (it.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(it.error!, style: const TextStyle(fontSize: 10, color: NebrasColors.rose)),
                    ),
                ],
              ),
            ),
            Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _iconBtn(Icons.keyboard_arrow_up, 'تحريك لأعلى',
                        (busy || index == 0) ? null : () => _moveItem(index, -1)),
                    _iconBtn(Icons.keyboard_arrow_down, 'تحريك لأسفل',
                        (busy || index == _queue.length - 1) ? null : () => _moveItem(index, 1)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _iconBtn(Icons.edit_outlined, 'تعديل',
                        (it.status == 'uploading' || it.status == 'completed') ? null : () => _openEditor(editing: it)),
                    _iconBtn(Icons.delete_outline, 'إزالة', () => _removeItem(it), danger: true),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback? onTap, {bool danger = false}) =>
      IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        padding: EdgeInsets.zero,
        tooltip: tip,
        iconSize: 18,
        color: danger ? NebrasColors.rose : NebrasColors.textMuted,
        onPressed: onTap,
        icon: Icon(icon),
      );
}

// ════════════ نافذة إعداد البند (إضافة/تعديل) ════════════
class _EditorResult {
  _EditorResult({
    required this.files,
    required this.title,
    required this.description,
    required this.author,
    required this.isListed,
    required this.sel,
    this.thumbBytes,
    this.thumbName,
  });
  final List<PlatformFile> files;
  final String title;
  final String description;
  final String author;
  final bool isListed;
  final SectionSelection sel;
  final Uint8List? thumbBytes;
  final String? thumbName;
}

class _ItemEditorSheet extends StatefulWidget {
  const _ItemEditorSheet({this.editing, required this.lastSections});
  final _QItem? editing;
  final SectionSelection lastSections;

  @override
  State<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<_ItemEditorSheet> {
  final List<PlatformFile> _files = [];
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _author = TextEditingController();
  bool _listed = true;
  late SectionSelection _sel;
  Uint8List? _thumbBytes;
  String? _thumbName;
  String? _error;
  String? _warn;
  bool _prefilled = false;

  bool get _multiFileMode => widget.editing == null && _files.length > 1;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _files.add(e.file);
      _title.text = e.title;
      _desc.text = e.description;
      _author.text = e.author;
      _listed = e.isListed;
      _sel = e.sel.copy();
      _thumbBytes = e.thumbBytes;
      _thumbName = e.thumbName;
    } else {
      _sel = widget.lastSections.copy();
      _prefilled = (_sel.mainId ?? '').isNotEmpty;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: widget.editing == null,
      withData: false,
      type: FileType.any,
    );
    if (res == null) return;
    setState(() {
      _error = null;
      _warn = null;
      for (final f in res.files) {
        if (f.size > _kMaxBytes) {
          _error = '${f.name}: الملف يتجاوز حد 500 ميغابايت';
          continue;
        }
        if (f.size > 100 * 1024 * 1024) _warn = 'ملف كبير — قد يستغرق الرفع وقتاً طويلاً';
        if (widget.editing != null) {
          _files
            ..clear()
            ..add(f);
        } else {
          _files.add(f);
        }
      }
      if (_files.length == 1 && _title.text.trim().isEmpty) {
        _title.text = smartTitleFromFileName(_files.first.name);
      }
    });
  }

  Future<void> _pickThumb() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.bytes == null) return;
    setState(() {
      _thumbBytes = f.bytes;
      _thumbName = f.name;
    });
  }

  void _save() {
    setState(() => _error = null);
    if (_files.isEmpty) {
      setState(() => _error = 'انقر لتحديد ملف');
      return;
    }
    if (!_multiFileMode && _title.text.trim().isEmpty) {
      setState(() => _error = 'العنوان مطلوب');
      return;
    }
    if ((_sel.mainId ?? '').isEmpty) {
      setState(() => _error = 'القسم الرئيسي مطلوب');
      return;
    }
    if ((_sel.subId ?? '').isEmpty) {
      setState(() => _error = 'القسم الفرعي مطلوب');
      return;
    }
    Navigator.pop(
      context,
      _EditorResult(
        files: List.of(_files),
        title: _title.text.trim(),
        description: _desc.text.trim(),
        author: _author.text.trim(),
        isListed: _listed,
        sel: _sel,
        thumbBytes: _thumbBytes,
        thumbName: _thumbName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
                  Text(editing ? 'تحديث البند' : 'إعداد الملف',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  if (_error != null) ...[
                    _miniAlert(_error!, NebrasColors.rose),
                    const SizedBox(height: 8),
                  ],
                  if (!editing && _prefilled) ...[
                    _miniAlert('تم تعبئة الأقسام تلقائياً من اختيارك السابق. يمكنك تغييرها قبل الحفظ إذا أردت.',
                        NebrasColors.amber),
                    const SizedBox(height: 8),
                  ],
                  // الملفّات
                  const Text('ملف *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  if (_files.isEmpty)
                    InkWell(
                      onTap: _pickFiles,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: NebrasColors.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(children: [
                          Icon(Icons.cloud_upload_outlined, size: 32, color: NebrasColors.textMuted),
                          SizedBox(height: 6),
                          Text('انقر أو أفلت ملفاً أو أكثر', style: TextStyle(color: NebrasColors.textMuted)),
                        ]),
                      ),
                    )
                  else ...[
                    if (_files.length > 1)
                      Row(
                        children: [
                          Text('${_files.length} ملفاً محدّداً',
                              style: const TextStyle(fontSize: 12, color: NebrasColors.textMuted)),
                          const Spacer(),
                          TextButton(onPressed: () => setState(() => _files.clear()), child: const Text('إزالة الكل')),
                        ],
                      ),
                    ..._files.asMap().entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(child: Text(e.value.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                              Text(_fmtSize(e.value.size), style: const TextStyle(fontSize: 11, color: NebrasColors.textMuted)),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () => setState(() => _files.removeAt(e.key)),
                              ),
                            ],
                          ),
                        )),
                    if (!editing)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _pickFiles,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('انقر أو أفلت ملفاً أو أكثر'),
                        ),
                      ),
                  ],
                  if (_warn != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_warn!, style: const TextStyle(fontSize: 11, color: NebrasColors.amber)),
                    ),
                  const SizedBox(height: 12),
                  // العنوان
                  TextField(
                    controller: _title,
                    enabled: !_multiFileMode,
                    decoration: InputDecoration(
                      labelText: 'العنوان ${_multiFileMode ? '' : '*'}',
                      helperText: _multiFileMode ? 'سيستخدم كل ملف اسمه عنواناً (يمكنك تعديل البنود لاحقاً).' : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _desc, maxLines: 2, decoration: const InputDecoration(labelText: 'الوصف')),
                  const SizedBox(height: 12),
                  TextField(controller: _author, decoration: const InputDecoration(labelText: 'المؤلف (اختياري)')),
                  const SizedBox(height: 14),
                  const Text('القسم', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  SectionPicker(selection: _sel, onChanged: () => setState(() => _prefilled = false)),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('مدرج', style: TextStyle(fontSize: 13)),
                    value: _listed,
                    onChanged: (v) => setState(() => _listed = v),
                  ),
                  // الصورة المصغرة
                  const Text('الصورة المصغرة', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (_thumbBytes != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(_thumbBytes!, width: 54, height: 54, fit: BoxFit.cover),
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
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _save,
                          child: Text(editing ? 'تحديث البند' : 'حفظ في الطابور'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniAlert(String msg, Color color) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(msg, style: TextStyle(color: color, fontSize: 12)),
      );
}
