import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/sections_repository.dart';
import '../widgets/common.dart';

const int _pageSize = 10;

String _fmtDate(dynamic v) {
  DateTime? d;
  if (v is Timestamp) {
    d = v.toDate();
  } else if (v is String) {
    d = DateTime.tryParse(v);
  } else if (v is num) {
    d = DateTime.fromMillisecondsSinceEpoch(v.toInt());
  }
  return d == null ? '—' : DateFormat('yyyy/MM/dd').format(d);
}

class SectionsScreen extends StatefulWidget {
  const SectionsScreen({super.key});

  @override
  State<SectionsScreen> createState() => _SectionsScreenState();
}

class _SectionsScreenState extends State<SectionsScreen> {
  final _repo = SectionsRepository.instance;

  SectionLevel _level = SectionLevel.main;
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _filterMain = '';
  String _filterSub = '';
  String _filterListed = '';

  List<Map<String, dynamic>> _mains = [];
  List<Map<String, dynamic>> _subsForFilter = [];
  List<Map<String, dynamic>> _results = [];
  int _page = 1;
  bool _loading = false;
  bool _hasSearched = false;
  String? _error;

  bool get _hasActiveFilter {
    if (_filterListed.isNotEmpty) return true;
    if (_level == SectionLevel.sub) return _filterMain.isNotEmpty;
    if (_level == SectionLevel.secondary) {
      return _filterMain.isNotEmpty || _filterSub.isNotEmpty;
    }
    return false;
  }

  int get _totalPages => (_results.length / _pageSize).ceil();
  List<Map<String, dynamic>> get _pageItems {
    final start = (_page - 1) * _pageSize;
    if (start >= _results.length) return const [];
    return _results.sublist(start, (start + _pageSize).clamp(0, _results.length));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _switchLevel(SectionLevel l) {
    setState(() {
      _level = l;
      _filterMain = '';
      _filterSub = '';
      _filterListed = '';
      _search = '';
      _searchCtrl.clear();
      _results = [];
      _hasSearched = false;
      _error = null;
      _page = 1;
    });
  }

  Future<void> _ensureMains() async {
    if (_mains.isEmpty) {
      _mains = await _repo.listMain();
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadSubsForMain(String mainId) async {
    _subsForFilter = mainId.isEmpty ? [] : await _repo.listSub(mainSection: mainId);
    if (mounted) setState(() {});
  }

  Future<void> _fetch() async {
    final q = _search.trim();
    if (q.isEmpty && !_hasActiveFilter) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _hasSearched = true;
    });
    try {
      List<Map<String, dynamic>> list;
      switch (_level) {
        case SectionLevel.main:
          list = await _repo.listMain(search: q);
          break;
        case SectionLevel.sub:
          list = await _repo.listSub(search: q, mainSection: _filterMain.isEmpty ? null : _filterMain);
          break;
        case SectionLevel.secondary:
          if (_filterSub.isNotEmpty) {
            list = await _repo.listSecondary(search: q, subSection: _filterSub);
          } else if (_filterMain.isNotEmpty) {
            // تصفية الثانويّة بكل الأقسام الفرعيّة التابعة للرئيسيّ المختار.
            final subs = await _repo.listSub(mainSection: _filterMain);
            final subIds = subs.map((e) => '${e['id']}').toSet();
            final all = await _repo.listSecondary(search: q);
            list = all.where((e) => subIds.contains('${e['sub_section']}')).toList();
          } else {
            list = await _repo.listSecondary(search: q);
          }
          break;
      }
      if (_filterListed.isNotEmpty) {
        final want = _filterListed == 'true';
        list = list.where((e) => ((e['is_listed'] ?? true) == true) == want).toList();
      }
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

  // ─── إجراءات ─────────────────────────────────────────────
  Future<void> _openEditor({Map<String, dynamic>? section}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NebrasColors.surface,
      builder: (_) => _SectionEditor(level: _level, section: section),
    );
    if (changed == true) _fetch();
  }

  void _openDetail(Map<String, dynamic> s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NebrasColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _SectionDetail(level: _level, section: s),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف القسم'),
        content: Text(
            'هل أنت متأكد من حذف "${s['name']}"؟ سيُحذف وكل أقسامه ومحتوياته التابعة. هذا الإجراء لا يمكن التراجع عنه.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NebrasColors.rose),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف القسم'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      await _repo.remove(_level, s['id']);
      if (mounted) Navigator.pop(context);
      if (mounted) showSnack(context, 'تم الحذف.');
      _fetch();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) showSnack(context, 'فشل الحذف: $e', error: true);
    }
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
                  Text('الأقسام', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('إدارة جميع تصنيفات المنصة', style: TextStyle(fontSize: 12, color: NebrasColors.textMuted)),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _openEditor,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('قسم جديد'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _levelTabs(),
        const SizedBox(height: 12),
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'البحث في الأقسام...',
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
        _filters(),
        const SizedBox(height: 12),
        if (_error != null) _alert(_error!),
        _body(),
      ],
    );
  }

  Widget _levelTabs() {
    Widget tab(String label, SectionLevel l) {
      final active = _level == l;
      return Expanded(
        child: InkWell(
          onTap: () => _switchLevel(l),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? NebrasColors.emerald : NebrasColors.border,
                  width: 2,
                ),
              ),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                    color: active ? NebrasColors.emerald : NebrasColors.textMuted)),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab('الأقسام الرئيسية', SectionLevel.main),
        tab('الأقسام الفرعية', SectionLevel.sub),
        tab('الأقسام الثانوية', SectionLevel.secondary),
      ],
    );
  }

  Widget _filters() {
    final widgets = <Widget>[];
    if (_level == SectionLevel.sub || _level == SectionLevel.secondary) {
      widgets.add(_dropdown(
        value: _filterMain,
        hint: 'تصفية حسب القسم الرئيسي',
        items: {for (final m in _mains) '${m['id']}': '${m['name'] ?? ''}'},
        onTap: _ensureMains,
        onChanged: (v) {
          _filterMain = v;
          _filterSub = '';
          if (_level == SectionLevel.secondary) _loadSubsForMain(v);
          _fetch();
        },
      ));
    }
    if (_level == SectionLevel.secondary) {
      widgets.add(_dropdown(
        value: _filterSub,
        hint: 'تصفية حسب القسم الفرعي',
        items: {for (final s in _subsForFilter) '${s['id']}': '${s['name'] ?? ''}'},
        onChanged: (v) {
          _filterSub = v;
          _fetch();
        },
      ));
    }
    widgets.add(_dropdown(
      value: _filterListed,
      hint: 'الكل (مدرج)',
      items: const {'true': 'مدرج', 'false': 'غير مدرج'},
      onChanged: (v) {
        _filterListed = v;
        _fetch();
      },
    ));
    widgets.add(Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: NebrasColors.surfaceAlt, borderRadius: BorderRadius.circular(10)),
      child: Text('${_results.length} إجمالي', style: const TextStyle(fontSize: 12)),
    ));
    return Wrap(spacing: 8, runSpacing: 8, children: widgets);
  }

  Widget _dropdown({
    required String value,
    required String hint,
    required Map<String, String> items,
    required ValueChanged<String> onChanged,
    VoidCallback? onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: NebrasColors.surfaceAlt, borderRadius: BorderRadius.circular(10)),
      child: DropdownButton<String>(
        value: value.isEmpty ? null : (items.containsKey(value) ? value : null),
        hint: Text(hint, style: const TextStyle(fontSize: 12)),
        underline: const SizedBox.shrink(),
        isDense: true,
        onTap: onTap,
        items: [
          DropdownMenuItem(value: '', child: Text(hint, style: const TextStyle(fontSize: 12))),
          ...items.entries.map((e) =>
              DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))),
        ],
        onChanged: (v) => onChanged(v ?? ''),
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
      return _stateBox(Icons.search, 'الرجاء استخدام مربّع البحث للعثور على العناصر',
          'اكتب كلمة واضغط بحث، أو اختر فلترًا. لا يتمّ تحميل أيّ بيانات قبل ذلك حفاظًا على الأداء.');
    }
    if (_results.isEmpty) {
      return _stateBox(Icons.inbox_outlined, 'لا توجد نتائج مطابقة — جرّب كلمة بحث أخرى', null);
    }
    return Column(
      children: [
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

  Widget _tile(Map<String, dynamic> s) {
    final thumb = '${s['thumbnail'] ?? ''}';
    final listed = (s['is_listed'] ?? true) == true;
    return Card(
      child: InkWell(
        onTap: () => _openDetail(s),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: thumb.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: thumb, width: 46, height: 46, fit: BoxFit.cover,
                        memCacheWidth: 150, memCacheHeight: 150,
                        errorWidget: (_, __, ___) => _phIcon())
                    : _phIcon(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${s['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      children: [
                        Text('المعرّف: ${s['id']}', style: const TextStyle(fontSize: 11, color: NebrasColors.textMuted)),
                        if (_level == SectionLevel.main && s['order_index'] != null)
                          Text('ترتيب: ${s['order_index']}', style: const TextStyle(fontSize: 11, color: NebrasColors.textMuted)),
                        if (!listed)
                          const Text('غير مدرج', style: TextStyle(fontSize: 11, color: NebrasColors.rose)),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _openEditor(section: s),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                color: NebrasColors.rose,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(s),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phIcon() => Container(
        width: 46, height: 46, color: NebrasColors.surfaceAlt,
        child: const Icon(Icons.folder, color: NebrasColors.textMuted));

  Widget _pagination() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(onPressed: _page > 1 ? () => setState(() => _page--) : null, child: const Text('← السابق')),
            Text('$_page / $_totalPages'),
            TextButton(onPressed: _page < _totalPages ? () => setState(() => _page++) : null, child: const Text('التالي →')),
          ],
        ),
      );
}

// ════════════ تفاصيل القسم ════════════
class _SectionDetail extends StatelessWidget {
  const _SectionDetail({required this.level, required this.section});
  final SectionLevel level;
  final Map<String, dynamic> section;

  @override
  Widget build(BuildContext context) {
    final s = section;
    final typeLabel = switch (level) {
      SectionLevel.main => 'قسم رئيسي',
      SectionLevel.sub => 'قسم فرعي',
      SectionLevel.secondary => 'قسم ثانوي',
    };
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 90, child: Text(k, style: const TextStyle(fontSize: 12, color: NebrasColors.textMuted))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('تفاصيل القسم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          if ('${s['thumbnail'] ?? ''}'.isNotEmpty)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(imageUrl: '${s['thumbnail']}', height: 120, fit: BoxFit.cover, memCacheWidth: 400),
              ),
            ),
          const SizedBox(height: 10),
          kv('المعرّف', '#${s['id']}'),
          kv('النوع', typeLabel),
          kv('الاسم', '${s['name'] ?? ''}'),
          if (s['order_index'] != null) kv('مؤشر الترتيب', '${s['order_index']}'),
          if ('${s['description'] ?? ''}'.isNotEmpty) kv('الوصف', '${s['description']}'),
          kv('مدرج', (s['is_listed'] ?? true) == true ? 'مدرج' : 'غير مدرج'),
          kv('تاريخ الإنشاء', _fmtDate(s['created_at'])),
        ],
      ),
    );
  }
}

// ════════════ إنشاء/تعديل قسم ════════════
class _SectionEditor extends StatefulWidget {
  const _SectionEditor({required this.level, this.section});
  final SectionLevel level;
  final Map<String, dynamic>? section;

  @override
  State<_SectionEditor> createState() => _SectionEditorState();
}

class _SectionEditorState extends State<_SectionEditor> {
  final _repo = SectionsRepository.instance;
  late final _nameCtrl = TextEditingController(text: '${widget.section?['name'] ?? ''}');
  late final _descCtrl = TextEditingController(text: '${widget.section?['description'] ?? ''}');
  late final _orderCtrl = TextEditingController(text: '${widget.section?['order_index'] ?? 0}');
  late bool _listed = (widget.section?['is_listed'] ?? true) == true;
  Uint8List? _thumbBytes;
  String? _thumbName;
  bool _busy = false;

  List<Map<String, dynamic>> _parents = [];
  String? _parentId;

  bool get _isEdit => widget.section != null;
  bool get _needsParent => widget.level != SectionLevel.main;

  @override
  void initState() {
    super.initState();
    if (_needsParent) _loadParents();
    if (_isEdit) {
      _parentId = widget.level == SectionLevel.sub
          ? '${widget.section?['main_section'] ?? ''}'
          : '${widget.section?['sub_section'] ?? ''}';
      if (_parentId!.isEmpty) _parentId = null;
    }
  }

  Future<void> _loadParents() async {
    _parents = widget.level == SectionLevel.sub ? await _repo.listMain() : await _repo.listSub();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _orderCtrl.dispose();
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
    if (_nameCtrl.text.trim().isEmpty) {
      showSnack(context, 'الاسم مطلوب.', error: true);
      return;
    }
    if (_needsParent && (_parentId == null || _parentId!.isEmpty)) {
      showSnack(context, 'اختر القسم الأب.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      if (_isEdit) {
        await _repo.update(
          widget.level,
          widget.section!['id'],
          name: _nameCtrl.text,
          description: _descCtrl.text,
          orderIndex: widget.level == SectionLevel.main ? int.tryParse(_orderCtrl.text) : null,
          isListed: _listed,
          parentSection: _needsParent ? (int.tryParse(_parentId!) ?? _parentId) : null,
          thumbBytes: _thumbBytes,
          thumbName: _thumbName,
        );
      } else {
        switch (widget.level) {
          case SectionLevel.main:
            await _repo.createMain(
              name: _nameCtrl.text,
              orderIndex: int.tryParse(_orderCtrl.text) ?? 0,
              isListed: _listed,
              thumbBytes: _thumbBytes,
              thumbName: _thumbName,
            );
            break;
          case SectionLevel.sub:
            await _repo.createSub(
              name: _nameCtrl.text,
              mainSection: _parentId,
              isListed: _listed,
              thumbBytes: _thumbBytes,
              thumbName: _thumbName,
            );
            break;
          case SectionLevel.secondary:
            await _repo.createSecondary(
              name: _nameCtrl.text,
              subSection: _parentId,
              isListed: _listed,
              thumbBytes: _thumbBytes,
              thumbName: _thumbName,
            );
            break;
        }
      }
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
            Text(_isEdit ? 'تعديل قسم' : 'إنشاء قسم',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'الاسم')),
            const SizedBox(height: 12),
            if (_needsParent)
              DropdownButtonFormField<String>(
                initialValue: (_parentId != null && _parents.any((e) => '${e['id']}' == _parentId)) ? _parentId : null,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: widget.level == SectionLevel.sub ? 'القسم الرئيسي المصدر' : 'القسم الفرعي المصدر'),
                items: _parents
                    .map((e) => DropdownMenuItem(value: '${e['id']}', child: Text('${e['name']}', overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setState(() => _parentId = v),
              ),
            if (widget.level == SectionLevel.main) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _orderCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'مؤشر الترتيب'),
              ),
            ],
            if (_isEdit) ...[
              const SizedBox(height: 12),
              TextField(controller: _descCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'الوصف')),
            ],
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('مدرج'),
              value: _listed,
              onChanged: (v) => setState(() => _listed = v),
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _pickThumb,
              icon: const Icon(Icons.image_outlined),
              label: Text(_thumbBytes != null ? 'تم اختيار صورة (${_thumbName ?? ''})' : 'صورة مصغّرة (اختياري)'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEdit ? 'حفظ التغييرات' : 'إنشاء قسم'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
