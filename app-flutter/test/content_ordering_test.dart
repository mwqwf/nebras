import 'package:flutter_test/flutter_test.dart';
import 'package:nebras_mobile_app/core/data/content_ordering.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';

Content _item({
  required String id,
  DateTime? createdAt,
  int selectionOrder = 0,
}) {
  final at = createdAt ?? DateTime(2024, 1, 1);
  return Content(
    id: id,
    title: id,
    author: '',
    description: '',
    type: ContentType.video,
    thumbnailUrl: '',
    section: 's1',
    createdAt: at,
    updatedAt: at,
    createdBy: '',
    selectionOrder: selectionOrder,
  );
}

void main() {
  group('compareContentOldestFirst', () {
    test('sorts by createdAt ascending', () {
      final a = _item(id: 'a', createdAt: DateTime(2024, 1, 2));
      final b = _item(id: 'b', createdAt: DateTime(2024, 1, 1));
      expect(compareContentOldestFirst(a, b), greaterThan(0));
      expect(compareContentOldestFirst(b, a), lessThan(0));
    });

    test('uses selectionOrder when createdAt equal', () {
      final at = DateTime(2024, 6, 1);
      final first = _item(id: 'x', createdAt: at, selectionOrder: 1);
      final second = _item(id: 'y', createdAt: at, selectionOrder: 2);
      expect(compareContentOldestFirst(first, second), lessThan(0));
    });

    test('uses fb_ epoch in id when date and order tie', () {
      final at = DateTime(2024, 6, 1);
      final older = _item(id: 'fb_1000_x', createdAt: at);
      final newer = _item(id: 'fb_2000_y', createdAt: at);
      expect(compareContentOldestFirst(older, newer), lessThan(0));
    });

    test('sortContentOldestFirst mutates list in place', () {
      final at = DateTime(2024, 6, 1);
      final items = [
        _item(id: 'c', createdAt: at.add(const Duration(days: 2))),
        _item(id: 'a', createdAt: at),
        _item(id: 'b', createdAt: at.add(const Duration(days: 1))),
      ];
      sortContentOldestFirst(items);
      expect(items.map((e) => e.id).toList(), ['a', 'b', 'c']);
    });
  });
}
