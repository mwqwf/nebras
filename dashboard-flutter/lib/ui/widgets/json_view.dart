import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// عارض JSON بسيط (مفتاح/قيمة) لعرض ردود الخادم دون افتراض شكلٍ ثابت.
class JsonView extends StatelessWidget {
  const JsonView(this.data, {super.key});
  final dynamic data;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: _node(data, 0),
    );
  }

  Widget _node(dynamic value, int depth) {
    if (value is Map) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: value.entries.map((e) {
          final v = e.value;
          final isLeaf = v is! Map && v is! List;
          if (isLeaf) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 12.5),
                  children: [
                    TextSpan(text: '${e.key}: ', style: const TextStyle(color: NebrasColors.textMuted)),
                    TextSpan(text: '${v ?? '—'}', style: const TextStyle(color: NebrasColors.textPrimary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            );
          }
          return Padding(
            padding: EdgeInsets.only(top: 4, right: depth == 0 ? 0 : 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${e.key}', style: const TextStyle(color: NebrasColors.emerald, fontSize: 12.5, fontWeight: FontWeight.bold)),
                _node(v, depth + 1),
              ],
            ),
          );
        }).toList(),
      );
    }
    if (value is List) {
      if (value.isEmpty) {
        return const Text('— فارغ —', style: TextStyle(color: NebrasColors.textMuted, fontSize: 12));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: value.take(50).map((item) {
          if (item is Map || item is List) {
            return Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: NebrasColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: NebrasColors.border),
                ),
                child: _node(item, depth + 1),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text('• $item', style: const TextStyle(fontSize: 12)),
          );
        }).toList(),
      );
    }
    return Text('$value', style: const TextStyle(fontSize: 12.5));
  }
}

/// زرّ نسخ JSON خام.
class CopyJsonButton extends StatelessWidget {
  const CopyJsonButton(this.data, {super.key});
  final dynamic data;
  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'نسخ JSON',
      icon: const Icon(Icons.copy_all_outlined, size: 18),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data)));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نُسخ JSON.')));
      },
    );
  }
}
