import 'package:flutter_test/flutter_test.dart';
import 'package:nebras_mobile_app/core/services/continue_watching_service.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ContinueWatchingService> fresh() async {
    final svc = ContinueWatchingService.instance;
    await svc.clearAll();
    await svc.init();
    return svc;
  }

  group('ContinueWatchingService', () {
    test('saveProgress then activeEntries returns entry', () async {
      final svc = await fresh();
      await svc.saveProgress(
        contentId: 'c1',
        positionMs: 30_000,
        durationMs: 120_000,
        title: 'Title',
        thumbnailUrl: 'https://example.com/t.jpg',
        type: ContentType.video,
      );
      final entries = await svc.activeEntries();
      expect(entries.length, 1);
      expect(entries.first.contentId, 'c1');
      expect(entries.first.progressRatio, closeTo(0.25, 0.01));
    });

    test('removes entry when progress >= 90%', () async {
      final svc = await fresh();
      await svc.saveProgress(
        contentId: 'done',
        positionMs: 95_000,
        durationMs: 100_000,
        title: 'Done',
        thumbnailUrl: '',
        type: ContentType.audio,
      );
      expect(await svc.activeEntries(), isEmpty);
    });

    test('ignores progress below 2%', () async {
      final svc = await fresh();
      await svc.saveProgress(
        contentId: 'tiny',
        positionMs: 500,
        durationMs: 100_000,
        title: 'Tiny',
        thumbnailUrl: '',
        type: ContentType.video,
      );
      expect(await svc.activeEntries(), isEmpty);
    });

    test('remove deletes single entry', () async {
      final svc = await fresh();
      await svc.saveProgress(
        contentId: 'x',
        positionMs: 10_000,
        durationMs: 100_000,
        title: 'X',
        thumbnailUrl: '',
        type: ContentType.video,
      );
      await svc.remove('x');
      expect(await svc.activeEntries(), isEmpty);
    });

    test('clearAll removes all entries', () async {
      final svc = await fresh();
      await svc.saveProgress(
        contentId: 'a',
        positionMs: 10_000,
        durationMs: 100_000,
        title: 'A',
        thumbnailUrl: '',
        type: ContentType.video,
      );
      await svc.saveProgress(
        contentId: 'b',
        positionMs: 20_000,
        durationMs: 100_000,
        title: 'B',
        thumbnailUrl: '',
        type: ContentType.video,
      );
      await svc.clearAll();
      expect(await svc.activeEntries(), isEmpty);
    });

    test('orders by most recent savedAt first', () async {
      final svc = await fresh();
      await svc.saveProgress(
        contentId: 'old',
        positionMs: 10_000,
        durationMs: 100_000,
        title: 'Old',
        thumbnailUrl: '',
        type: ContentType.video,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await svc.saveProgress(
        contentId: 'new',
        positionMs: 10_000,
        durationMs: 100_000,
        title: 'New',
        thumbnailUrl: '',
        type: ContentType.video,
      );
      final ids = (await svc.activeEntries()).map((e) => e.contentId).toList();
      expect(ids.first, 'new');
    });

    test('caps stored entries at 24', () async {
      final svc = await fresh();
      for (var i = 0; i < 30; i++) {
        await svc.saveProgress(
          contentId: 'id_$i',
          positionMs: 10_000,
          durationMs: 100_000,
          title: 'T$i',
          thumbnailUrl: '',
          type: ContentType.video,
        );
      }
      final entries = await svc.activeEntries();
      expect(entries.length, lessThanOrEqualTo(24));
    });
  });
}
