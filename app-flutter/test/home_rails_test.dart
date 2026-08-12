import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';
import 'package:nebras_mobile_app/features/home/services/home_rail_builders.dart';

Content _content({
  required String id,
  DateTime? createdAt,
  int viewCount = 0,
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
    viewCount: viewCount,
  );
}

HomeSection _section({
  required String id,
  String? parentId,
  List<Content> items = const [],
}) {
  return HomeSection(
    id: id,
    title: id,
    type: 'videos',
    parentId: parentId,
    items: items,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HomeRailBuilders', () {
    test('allContentFlat deduplicates by id', () {
      final pool = HomeRailBuilders.allContentFlat([
        _section(
          id: 's1',
          items: [_content(id: 'a'), _content(id: 'b')],
        ),
        _section(
          id: 's2',
          items: [_content(id: 'a'), _content(id: 'c')],
        ),
      ]);
      expect(pool.map((c) => c.id).toSet(), {'a', 'b', 'c'});
    });

    test('buildNewestRail sorts by createdAt descending', () {
      final pool = [
        _content(id: 'old', createdAt: DateTime(2024, 1, 1)),
        _content(id: 'new', createdAt: DateTime(2024, 6, 1)),
      ];
      final rail = HomeRailBuilders.buildNewestRail(pool, limit: 5);
      expect(rail.first.id, 'new');
      expect(rail.last.id, 'old');
    });

    test('buildPopularRail respects popularIds order', () {
      final pool = [
        _content(id: 'a', viewCount: 1),
        _content(id: 'b', viewCount: 99),
        _content(id: 'c', viewCount: 50),
      ];
      final rail = HomeRailBuilders.buildPopularRail(
        pool,
        popularIds: ['c', 'a'],
        limit: 5,
      );
      expect(rail.map((c) => c.id).toList(), ['c', 'a']);
    });

    test('buildPopularRail falls back to viewCount', () {
      final pool = [
        _content(id: 'low', viewCount: 1),
        _content(id: 'high', viewCount: 100),
      ];
      final rail = HomeRailBuilders.buildPopularRail(pool, limit: 2);
      expect(rail.first.id, 'high');
    });

    test('buildForYouRail excludes given ids', () {
      final pool = [
        _content(id: 'a'),
        _content(id: 'b'),
        _content(id: 'c'),
      ];
      final rail = HomeRailBuilders.buildForYouRail(
        pool,
        excludeIds: {'a', 'b'},
        limit: 10,
      );
      expect(rail.every((c) => c.id != 'a' && c.id != 'b'), isTrue);
    });

    test('buildSearchAffinityRail empty when no keywords', () {
      final result = HomeRailBuilders.buildSearchAffinityRail(
        [_content(id: 'x')],
      );
      expect(result.items, isEmpty);
      expect(result.subtitle, isNull);
    });

    test('buildBrowseSections keeps main sections only', () {
      final refs = HomeRailBuilders.buildBrowseSections([
        _section(id: 'main1', parentId: null),
        _section(id: 'sub1', parentId: 'main1'),
        _section(id: 'main2', parentId: ''),
      ]);
      expect(refs.map((r) => r.id).toSet(), {'main1', 'main2'});
    });

    test('buildContinueRail empty when no local progress', () async {
      final items = await HomeRailBuilders.buildContinueRail([
        _content(id: 'v1'),
      ]);
      expect(items, isEmpty);
    });

    test('idsOf collects content ids', () {
      final ids = HomeRailBuilders.idsOf([
        _content(id: 'x'),
        _content(id: 'y'),
      ]);
      expect(ids, {'x', 'y'});
    });
  });
}
