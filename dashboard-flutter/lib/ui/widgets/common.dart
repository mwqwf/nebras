import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/sections_repository.dart';

/// عرض حالة Future موحّد: تحميل/خطأ/فارغ/محتوى.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.future,
    required this.builder,
    this.emptyCheck,
    this.emptyText = 'لا توجد بيانات.',
  });

  final Future<T> future;
  final Widget Function(BuildContext, T) builder;
  final bool Function(T)? emptyCheck;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return _ErrorBox(message: '${snap.error}');
        }
        final data = snap.data as T;
        if (emptyCheck != null && emptyCheck!(data)) {
          return _EmptyBox(text: emptyText);
        }
        return builder(context, data);
      },
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: NebrasColors.rose, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: NebrasColors.rose)),
          ],
        ),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, color: NebrasColors.textMuted, size: 44),
            const SizedBox(height: 12),
            Text(text, style: const TextStyle(color: NebrasColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// بطاقة إحصائيّة بسيطة.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? NebrasColors.emerald;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: c),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text(label, style: const TextStyle(color: NebrasColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// نتيجة اختيار الأقسام.
class SectionSelection {
  String? mainId, mainName, subId, subName, secId, secName;
  bool get hasSub => subId != null && subId!.isNotEmpty;

  SectionSelection copy() => SectionSelection()
    ..mainId = mainId
    ..mainName = mainName
    ..subId = subId
    ..subName = subName
    ..secId = secId
    ..secName = secName;
}

/// منتقي أقسام متسلسل (رئيسي → فرعي → ثانوي) يقرأ من Firestore.
class SectionPicker extends StatefulWidget {
  const SectionPicker({super.key, required this.selection, required this.onChanged});
  final SectionSelection selection;
  final VoidCallback onChanged;

  @override
  State<SectionPicker> createState() => _SectionPickerState();
}

class _SectionPickerState extends State<SectionPicker> {
  final _repo = SectionsRepository.instance;
  List<Map<String, dynamic>> _mains = [];
  List<Map<String, dynamic>> _subs = [];
  List<Map<String, dynamic>> _secs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMains();
  }

  Future<void> _loadMains() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _mains = await _repo.listMain();
      if (widget.selection.mainId != null) {
        _subs = await _repo.listSub(mainSection: widget.selection.mainId);
        if (widget.selection.subId != null) {
          _secs = await _repo.listSecondary(subSection: widget.selection.subId);
        }
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذّر تحميل الأقسام — تحقّق من الاتصال.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, color: NebrasColors.rose, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!, style: const TextStyle(color: NebrasColors.rose, fontSize: 12))),
            TextButton(onPressed: _loadMains, child: const Text('إعادة')),
          ],
        ),
      );
    }
    final sel = widget.selection;
    return Column(
      children: [
        _dropdown(
          fieldKey: const ValueKey('main'),
          label: 'القسم الرئيسي',
          value: sel.mainId,
          items: _mains,
          onChanged: (id, name) async {
            sel.mainId = id;
            sel.mainName = name;
            sel.subId = null;
            sel.subName = null;
            sel.secId = null;
            sel.secName = null;
            _subs = id == null ? [] : await _repo.listSub(mainSection: id);
            _secs = [];
            widget.onChanged();
            setState(() {});
          },
        ),
        const SizedBox(height: 10),
        _dropdown(
          fieldKey: ValueKey('sub-${sel.mainId}'),
          label: 'القسم الفرعي',
          value: sel.subId,
          items: _subs,
          onChanged: (id, name) async {
            sel.subId = id;
            sel.subName = name;
            sel.secId = null;
            sel.secName = null;
            _secs = id == null ? [] : await _repo.listSecondary(subSection: id);
            widget.onChanged();
            setState(() {});
          },
        ),
        const SizedBox(height: 10),
        _dropdown(
          fieldKey: ValueKey('sec-${sel.subId}'),
          label: 'القسم الثانوي (اختياري)',
          value: sel.secId,
          items: _secs,
          onChanged: (id, name) {
            sel.secId = id;
            sel.secName = name;
            widget.onChanged();
            setState(() {});
          },
        ),
      ],
    );
  }

  Widget _dropdown({
    required Key fieldKey,
    required String label,
    required String? value,
    required List<Map<String, dynamic>> items,
    required void Function(String?, String?) onChanged,
  }) {
    final ids = items.map((e) => '${e['id']}').toSet();
    final safeValue = (value != null && ids.contains(value)) ? value : null;
    return DropdownButtonFormField<String>(
      key: fieldKey,
      initialValue: safeValue,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('— لا شيء —')),
        ...items.map((e) => DropdownMenuItem<String>(
              value: '${e['id']}',
              child: Text('${e['name'] ?? ''}', overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: items.isEmpty
          ? null
          : (v) {
              final name = v == null
                  ? null
                  : '${items.firstWhere((e) => '${e['id']}' == v, orElse: () => {})['name'] ?? ''}';
              onChanged(v, name);
            },
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? NebrasColors.rose : NebrasColors.emeraldDark,
  ));
}
