import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/core/data/content_ordering.dart';
import 'package:nebras_mobile_app/core/data/rtdb_upload_normalizer.dart';
import 'package:nebras_mobile_app/core/error/error_handler.dart';
import 'package:nebras_mobile_app/core/services/hidden_content_service.dart';
import 'package:nebras_mobile_app/features/content/cache/content_metadata_cache.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';

/// Home Remote Datasource
/// Fetches content and guarantees showing section hierarchy,
/// even when sections currently have no content.
class HomeDatasource {
  final FirebaseFirestore firestore;
  final ContentMetadataCache? metadataCache;

  HomeDatasource(this.firestore, {this.metadataCache});

  // مسارات المجموعات في Firestore (يجب أن تتطابق مع ما تم تصديره من RTDB)
  static const _pathSections = 'sections_unified';
  static const _pathUploads = 'dashboard_uploads';
  static const _pathContentFiles = 'content_unified_files';
  static const _pathContentYoutube = 'content_unified_youtube';

  // ⚠️ كان 20 — صغير جداً: Firestore يُرجع أوّل 20 وثيقة بترتيب المعرّف
  // تصاعدياً (الأقدم)، فالمحتوى الأحدث (ومنه مكتبة Internet Archive التي
  // معرّفاتها fb_<epoch حديث>) لا يدخل ضمن أوّل 20 فلا يظهر في الرئيسية
  // إطلاقاً. البحث يحمّل الكلّ (.get بلا حدّ) فيظهر هناك. نرفع الحدّ ليشمل
  // الكتالوج الحاليّ مع هامش نمو. (الحلّ الأمثل مستقبلاً: ترقيم/ترتيب بالأحدث.)
  static const int _pageSize = 500;

  Future<List<HomeSection>> getHomeData({int page = 1}) async {
    try {
      final queries = await Future.wait([
        firestore.collection(_pathSections).get(),
        firestore.collection(_pathUploads).limit(_pageSize).get(),
        firestore.collection(_pathContentFiles).limit(_pageSize).get(),
        firestore.collection(_pathContentYoutube).limit(_pageSize).get(),
      ]);

      // تحويل المستندات إلى شكل Map يطابق بنية RTDB القديمة
      Map<String, dynamic> docsToMap(QuerySnapshot snapshot) {
        final map = <String, dynamic>{};
        for (var doc in snapshot.docs) {
          map[doc.id] = doc.data();
        }
        return map;
      }

      return _buildFromRawValues(
        sectionsRaw: docsToMap(queries[0]),
        uploadsRaw: docsToMap(queries[1]),
        filesRaw: docsToMap(queries[2]),
        youtubeRaw: docsToMap(queries[3]),
        page: page,
      );
    } catch (e) {
      final cached = _cachedOfflineSections();
      if (cached.isNotEmpty) return cached;
      throw ErrorHandler.handleException(e);
    }
  }

  /// يراقب Firestore (`snapshots`) على نفس المسارات التي يقرأها
  /// [getHomeData]. نحتفظ بآخر قيمة لكلّ مسار، ومع وصول أيّ حدث نُعيد بناء
  /// الشجرة. هذا يجعل المحتوى المضاف من لوحة التحكّم يظهر للجميع خلال
  /// ميلّي ثانية من الكتابة إلى Firebase — بدون الحاجة لمسح التطبيق أو
  /// إعادة تشغيله.
  ///
  /// - Stream عبارة عن broadcast حتى يسمح بإعادة الاشتراك المتعدّد (مثلاً
  ///   من HomeProvider + شاشة فرعية مفتوحة).
  /// - نُلغي جميع الـ listeners عند غلق آخر مشترك [onCancel] حتى لا تتسرّب
  ///   اتصالات بالخادم.
  Stream<List<HomeSection>> watchHomeData({int page = 1}) {
    late StreamController<List<HomeSection>> controller;
    final subs = <StreamSubscription<QuerySnapshot>>[];

    Object? sectionsRaw;
    Object? uploadsRaw;
    Object? filesRaw;
    Object? youtubeRaw;
    var gotSections = false;
    var gotUploads = false;
    var gotFiles = false;
    var gotYoutube = false;

    // Guard ضدّ إرسال نتائج متأخّرة بعد وصول قيم أحدث (compute قد يستغرق
    // عشرات الميلّي ثانية، خلالها قد يصل حدث جديد).
    var buildSeq = 0;

    Future<void> rebuild() async {
      if (!gotSections || !gotUploads || !gotFiles || !gotYoutube) return;
      final mySeq = ++buildSeq;
      try {
        final list = await _buildFromRawValues(
          sectionsRaw: sectionsRaw,
          uploadsRaw: uploadsRaw,
          filesRaw: filesRaw,
          youtubeRaw: youtubeRaw,
          page: page,
        );
        unawaited(_reconcileLiveContent(list));
        if (mySeq != buildSeq) return; // قيم أحدث وصلت أثناء البناء.
        if (!controller.isClosed) controller.add(list);
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    void listenOn(
      Query query,
      void Function(Object? value) assign,
      void Function() markArrived,
    ) {
      subs.add(
        query.snapshots().listen(
          (snapshot) {
            final map = <String, dynamic>{};
            for (var doc in snapshot.docs) {
              map[doc.id] = doc.data();
            }
            assign(map);
            markArrived();
            rebuild();
          },
          onError: (Object err, StackTrace st) {
            final cached = _cachedOfflineSections();
            if (cached.isNotEmpty) {
              controller.add(cached);
            } else if (!controller.isClosed) {
              controller.addError(err, st);
            }
          },
        ),
      );
    }

    controller = StreamController<List<HomeSection>>.broadcast(
      onListen: () {
        if (subs.isNotEmpty) return; // أُعيد الاشتراك لنفس الـ stream.
        listenOn(
          firestore.collection(_pathSections),
          (v) => sectionsRaw = v,
          () => gotSections = true,
        );
        listenOn(firestore.collection(_pathUploads).limit(_pageSize), (v) => uploadsRaw = v, () => gotUploads = true);
        listenOn(firestore.collection(_pathContentFiles).limit(_pageSize), (v) => filesRaw = v, () => gotFiles = true);
        listenOn(
          firestore.collection(_pathContentYoutube).limit(_pageSize),
          (v) => youtubeRaw = v,
          () => gotYoutube = true,
        );
        debugPrint('[HomeDatasource] watchHomeData: listeners attached');
      },
      onCancel: () async {
        debugPrint('[HomeDatasource] watchHomeData: cancelling listeners');
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );

    return controller.stream;
  }

  Stream<List<HomeSection>> watchHomeDataWithOfflineFallback({int page = 1}) {
    late StreamController<List<HomeSection>> controller;
    StreamSubscription<List<HomeSection>>? sub;
    var emittedLive = false;
    controller = StreamController<List<HomeSection>>.broadcast(
      onListen: () {
        sub ??= watchHomeData(page: page).listen(
          (sections) async {
            emittedLive = true;
            await _reconcileLiveContent(sections);
            if (!controller.isClosed) controller.add(sections);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!emittedLive) {
              final cached = _cachedOfflineSections();
              if (cached.isNotEmpty) {
                controller.add(cached);
                return;
              }
            }
            if (!controller.isClosed) controller.addError(error, stackTrace);
          },
        );
      },
      onCancel: () async {
        await sub?.cancel();
        sub = null;
      },
    );
    return controller.stream;
  }

  /// منطق البناء المشترك بين getHomeData و watchHomeData. لا يغيّر الـ
  /// semantics المعروفة — فقط ينقل التحليل إلى مكان واحد قابل للاستخدام.
  Future<List<HomeSection>> _buildFromRawValues({
    required Object? sectionsRaw,
    required Object? uploadsRaw,
    required Object? filesRaw,
    required Object? youtubeRaw,
    int page = 1,
  }) async {
    final sectionsRoot = RtdbUploadNormalizer.normalizeDatabaseRoot(
      sectionsRaw,
    );
    final contentRoot = RtdbUploadNormalizer.combineDatabaseRoots({
      'dashboard_uploads': uploadsRaw,
      'content_unified_files': filesRaw,
      'content_unified_youtube': youtubeRaw,
    });
    final contentRows = await compute(
      _parseAndNormalizeContentRows,
      contentRoot,
    );
    final parsedSections = _parseSectionsTree(sectionsRoot);
    // إزالة التكرار: الـ walker يمرّ على dashboard_uploads و content_unified_files
    // معاً (وهما مرآة لبعضهما)، فينتج كلّ وثيقة مرّتين بنفس الـ id. نحتفظ
    // بأوّل ظهور فقط حتى لا يرى المستخدم كلّ بطاقة مرّتين في كلّ قسم.
    final seenIds = <String>{};
    final allItems = contentRows
        .map(_mapContentFromRtdb)
        // ⛓️ حارس "No source available" — استبعاد كل وثيقة بدون sourceUrl
        //    صالح. يمنع عرض كروت تظهر رسالة "لا يوجد مصدر متاح" عند الضغط.
        //    تطبيق نفس قاعدة search_datasource (انظر _isPlayableAndCompliant
        //    هناك).
        .where(_isPlayableAndCompliant)
        // إزالة المكرّرات بالـ id (نفس الوثيقة من dashboard_uploads وcontent_unified_files)
        .where((item) => seenIds.add(item.id))
        .toList();
    unawaited(metadataCache?.cacheMany(allItems) ?? Future<void>.value());

    debugPrint(
      '[HomeDatasource] rtdb page=$page raw contents: ${allItems.length}',
    );
    debugPrint(
      '[HomeDatasource] rtdb sections main=${parsedSections.main.length}, sub=${parsedSections.sub.length}, secondary=${parsedSections.secondary.length}',
    );
    if (allItems.isNotEmpty) {
      final a = allItems.first;
      debugPrint(
        '[HomeDatasource] sample mapping subsection="${a.section}" secondary="${a.subSection ?? ''}"',
      );
    }

    final dynamicSections = _buildDynamicSections(
      allItems,
      contentRows,
      parsedSections.main,
      parsedSections.sub,
      parsedSections.secondary,
    );
    if (dynamicSections.isNotEmpty) {
      return _appendFallbackSections(dynamicSections, allItems);
    }

    if (allItems.isEmpty) return [];
    return _buildGroupedFallback(allItems);
  }

  /// لقطة فوريّة من ميتادات Hive المحفوظة محليّاً — تُعرض لحظة الإقلاع
  /// قبل وصول أوّل لقطة حيّة من Firestore، حتى لا يرى المستخدم العائد
  /// شاشة تحميل (skeleton) لثوانٍ بينما يُهيَّأ الـ stream. بمجرّد وصول
  /// أوّل لقطة live تُستبدَل هذه اللقطة بالشجرة الكاملة.
  List<HomeSection> cachedHomeSections() => _cachedOfflineSections();

  /// يبني قسماً افتراضياً من ميتادات Hive عند فشل الشبكة. هذا لا يخلط
  /// بيانات قديمة مع لقطات الخادم: بمجرد وصول أي لقطة live نعود لمسار
  /// الخادم ونصالح الكاش لإزالة المحذوفات.
  List<HomeSection> _cachedOfflineSections() {
    final cache = metadataCache;
    if (cache == null) return const [];
    final groups = cache.offlineGroups();
    if (groups.isEmpty) return const [];
    return groups
        .map(
          (group) => HomeSection(
            id: group.id,
            title: group.title,
            type: 'offline_metadata',
            // حتى في وضع عدم الاتصال نحترم إخفاء المحتوى المُبلَّغ عنه.
            items: group.items
                .where((c) => !HiddenContentService.instance.isHidden(c.id))
                .toList(growable: false),
            isOfflineCache: true,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _reconcileLiveContent(List<HomeSection> liveSections) async {
    final cache = metadataCache;
    if (cache == null) return;
    final liveIds = <String>{
      for (final section in liveSections)
        if (!section.isOfflineCache)
          for (final item in section.items) item.id,
    };
    if (liveIds.isNotEmpty) {
      await cache.reconcileWithLiveIds(liveIds);
    }
  }

  List<HomeSection> _buildDynamicSections(
    List<Content> allItems,
    List<Map<String, dynamic>> contentRows,
    List<Map<String, dynamic>> mainRows,
    List<Map<String, dynamic>> subRows,
    List<Map<String, dynamic>> secondaryRows,
  ) {
    if (mainRows.isEmpty && subRows.isEmpty && secondaryRows.isEmpty) {
      return [];
    }

    final mainSections = mainRows
        .map(_parseMainSection)
        .whereType<_SectionMeta>()
        .toList();
    final mainLookup = RtdbUploadNormalizer.mainIdLookup(
      mainSections.map((m) => (id: m.id, name: m.name)),
    );

    var subSections = _resolveSubParentsAgainstMains(
      subRows.map(_parseSubSection).whereType<_SectionMeta>().toList(),
      mainLookup,
    );
    var secondarySections = secondaryRows
        .map(_parseSecondarySection)
        .whereType<_SectionMeta>()
        .toList();

    final subById = {for (final s in subSections) s.id: s};
    final secondaryById = {for (final s in secondarySections) s.id: s};

    // إذا وُجدت في المحتوى أقسام ثانوية غير معرّفة في الشجرة، نُنشئها ونربطها بالقسم الفرعي (subsection)
    //
    // حماية من الأقسام الوهمية: لا نُنشئ قسمًا ضمنيًا من معرِّف يبدو كأنه
    // مرجعٌ لمصدر خارجي (Mshcat / OldApp). هذه المعرّفات
    // تُحجز للأقسام الحقيقية المسجّلة صراحةً في `sections_unified` بحقول
    // `remote_source_*` (وتمرّ بالفعل إلى subById/secondaryById فوق). إذا
    // وصلنا إلى هنا بمعرّف خارجي غير مُسجَّل، فالسجلّ محتوى يتيم لمصدر
    // حُذف أو أُعيد ربطه — لا يجب أن يظهر في الواجهة كقسم باسم "mshcat:sub:..."
    // ولا أن يستدرج محتوًى محذوفًا خلفه.
    for (final item in allItems) {
      final secId = item.subSection?.trim() ?? '';
      if (secId.isEmpty) continue;
      if (secondaryById.containsKey(secId)) continue;
      final subId = item.section.trim();
      if (subId.isEmpty) continue;
      if (_looksLikeExternalRef(secId) || _looksLikeExternalRef(subId)) {
        continue;
      }
      final meta = _SectionMeta(
        id: secId,
        name: RtdbUploadNormalizer.implicitSecondaryDisplayName(
          secId,
          item.sectionName,
        ),
        parentId: subId,
        imageUrl: null,
      );
      secondaryById[secId] = meta;
    }
    secondarySections = secondaryById.values.toList();

    // إذا وُجد في المحتوى subsection غير مُعرّف في الشجرة، نُنشئه تحت قسم رئيسي (من التلميح أو الأول)
    if (mainSections.isNotEmpty) {
      final fallbackMainId = mainSections.first.id;
      final n = allItems.length;
      for (var i = 0; i < n; i++) {
        final item = allItems[i];
        final subId = item.section.trim();
        if (subId.isEmpty) continue;
        if (subById.containsKey(subId)) continue;
        // نفس الحماية في المستوى الفرعي: لا phantom من معرّف خارجي غير مُسجَّل.
        if (_looksLikeExternalRef(subId)) continue;
        final row = i < contentRows.length
            ? contentRows[i]
            : <String, dynamic>{};
        final hint = RtdbUploadNormalizer.mainSectionHint(row);
        final resolvedMain =
            RtdbUploadNormalizer.resolveMainId(hint, mainLookup) ??
            fallbackMainId;
        subById[subId] = _SectionMeta(
          id: subId,
          name: item.sectionName?.trim().isNotEmpty == true
              ? item.sectionName!.trim()
              : subId,
          parentId: resolvedMain,
          imageUrl: null,
        );
      }
      subSections = subById.values.toList();
    }

    // نسمح للمحتوى متى كان مرتبطًا بقسم فرعي معروف وقسم رئيسي حقيقي.
    // وجود القسم الثانوي اختياريّ — لوحة التحكّم تسمح برفع محتوى تحت
    // (رئيسي + فرعي) فقط بدون مستوى ثالث. الفلترة السابقة كانت تشترط
    // وجود secondary_subsection فتُسقط هذا النوع كاملًا، فتظهر الأقسام
    // فارغة على الواجهة وتختفي العناصر من البحث المحلّي.
    final filteredItems = allItems.where((item) {
      final subId = item.section;
      final secondaryId = item.subSection ?? '';
      if (subId.isEmpty) return false;
      final sub = subById[subId];
      if (sub == null) return false;
      // إن وُجد قسم ثانوي مُعلَن في العنصر، نتحقّق من اتساقه مع الشجرة.
      // غيابه ليس خطأً — يعني فقط أنّ المحتوى يجلس مباشرة تحت القسم الفرعي.
      if (secondaryId.isNotEmpty) {
        final secondary = secondaryById[secondaryId];
        if (secondary == null) return false;
        if (secondary.parentId.isNotEmpty && secondary.parentId != subId) {
          return false;
        }
      }
      // تحقق أن القسم الفرعي مربوط بقسم رئيسي فعلي
      if (sub.parentId.isEmpty) return false;
      final hasMain = mainSections.any((m) => m.id == sub.parentId);
      return hasMain;
    }).toList();

    debugPrint(
      '[HomeDatasource] filtered contents with full hierarchy: ${filteredItems.length}',
    );

    final bySub = <String, List<Content>>{};
    final bySecondary = <String, List<Content>>{};
    for (final item in filteredItems) {
      if (item.section.isNotEmpty) {
        bySub.putIfAbsent(item.section, () => <Content>[]).add(item);
      }
      final secondaryId = item.subSection ?? '';
      if (secondaryId.isNotEmpty) {
        bySecondary.putIfAbsent(secondaryId, () => <Content>[]).add(item);
      }
    }

    // ترتيب المحتوى داخل كل قسم فرعي/ثانوي: الأقدم أولاً (انظر content_ordering.dart).
    bySub.forEach((_, list) => sortContentOldestFirst(list));
    bySecondary.forEach((_, list) => sortContentOldestFirst(list));

    final subByMain = <String, List<_SectionMeta>>{};
    for (final sub in subSections) {
      if (sub.parentId.isNotEmpty) {
        subByMain.putIfAbsent(sub.parentId, () => <_SectionMeta>[]).add(sub);
      }
    }

    final sections = <HomeSection>[];

    for (final main in mainSections) {
      final linkedSubs = subByMain[main.id] ?? const <_SectionMeta>[];
      final mainItems = linkedSubs
          .expand((sub) => bySub[sub.id] ?? const <Content>[])
          .toList();
      // dedupe ثم نعيد الترتيب لأن dedupe قد يكسر الترتيب المكتسب من bySub.
      final deduped = _dedupeById(mainItems)..sort(compareContentOldestFirst);
      sections.add(
        HomeSection(
          id: 'main:${main.id}',
          title: main.name,
          type: 'main_section',
          parentId: null,
          imageUrl: main.imageUrl,
          archiveId: main.archiveId,
          items: deduped,
        ),
      );
    }

    for (final sub in subSections) {
      sections.add(
        HomeSection(
          id: 'sub:${sub.id}',
          title: sub.name,
          type: 'sub_section',
          parentId: mainSections.any((m) => m.id == sub.parentId)
              ? 'main:${sub.parentId}'
              : null,
          imageUrl: sub.imageUrl,
          archiveId: sub.archiveId,
          remoteSourceApp: sub.remoteSourceApp,
          remoteSourceLevel: sub.remoteSourceLevel,
          remoteSourceId: sub.remoteSourceId,
          items: bySub[sub.id] ?? const <Content>[],
        ),
      );
    }

    for (final secondary in secondarySections) {
      sections.add(
        HomeSection(
          id: 'secondary:${secondary.id}',
          title: secondary.name,
          type: 'secondary_section',
          parentId: secondary.parentId.isNotEmpty
              ? 'sub:${secondary.parentId}'
              : null,
          imageUrl: secondary.imageUrl,
          archiveId: secondary.archiveId,
          remoteSourceApp: secondary.remoteSourceApp,
          remoteSourceLevel: secondary.remoteSourceLevel,
          remoteSourceId: secondary.remoteSourceId,
          items: bySecondary[secondary.id] ?? const <Content>[],
        ),
      );
    }

    return sections;
  }

  _SectionsParseResult _parseSectionsTree(Map<String, dynamic> root) {
    // لوحة التحكم تحفظ الأقسام في بنية مسطّحة تحت
    // sections_unified/{main|sub|secondary}/{id}. إذا اكتشفنا هذه البنية
    // نفسّر كل مستوى كقائمة مستقلة بمفاتيح FK صريحة بدل محاولة المشي شجريًا
    // (المشي الشجري يعتبر المفاتيح "main"/"sub"/"secondary" أنفسها كأقسام رئيسية
    // ويضع المحتوى تحت شجرة خاطئة تمامًا).
    if (_looksLikeFlatSectionsRoot(root)) {
      return _parseFlatSections(root);
    }
    return _parseLegacyTreeSections(root);
  }

  bool _looksLikeFlatSectionsRoot(Map<String, dynamic> root) {
    return _containerHasSectionRecords(root['main']) ||
        _containerHasSectionRecords(root['sub']) ||
        _containerHasSectionRecords(root['secondary']);
  }

  bool _containerHasSectionRecords(dynamic container) {
    final entries = <dynamic>[];
    if (container is Map) {
      entries.addAll(container.values);
    } else if (container is List) {
      entries.addAll(container);
    } else {
      return false;
    }
    for (final value in entries) {
      if (value is! Map) continue;
      final m = value.map((k, v) => MapEntry(k.toString(), v));
      final hasName =
          (m['name']?.toString().trim().isNotEmpty ?? false) ||
          (m['title']?.toString().trim().isNotEmpty ?? false);
      final hasId = m['id']?.toString().trim().isNotEmpty ?? false;
      final hasFk =
          (m['main_section']?.toString().trim().isNotEmpty ?? false) ||
          (m['sub_section']?.toString().trim().isNotEmpty ?? false);
      if ((hasName && hasId) || hasFk) return true;
    }
    return false;
  }

  _SectionsParseResult _parseFlatSections(Map<String, dynamic> root) {
    final main = <Map<String, dynamic>>[];
    final sub = <Map<String, dynamic>>[];
    final secondary = <Map<String, dynamic>>[];

    void walkContainer(
      dynamic container,
      void Function(String key, Map<String, dynamic> record) onRecord,
    ) {
      if (container is Map) {
        container.forEach((key, value) {
          if (value is Map) {
            onRecord(
              key.toString(),
              value.map((k, v) => MapEntry(k.toString(), v)),
            );
          }
        });
      } else if (container is List) {
        for (var i = 0; i < container.length; i++) {
          final value = container[i];
          if (value is Map) {
            onRecord('$i', value.map((k, v) => MapEntry(k.toString(), v)));
          }
        }
      }
    }

    String? pickThumbnail(Map<String, dynamic> m) {
      return _firstNonEmptyNullable([
        m['thumbnail']?.toString(),
        m['thumbnail_url']?.toString(),
        m['image_url']?.toString(),
        m['image']?.toString(),
      ]);
    }

    bool isExplicitlyHidden(Map<String, dynamic> m) {
      final listed = m['is_listed'];
      if (listed == null) return false;
      if (listed is bool) return !listed;
      final s = listed.toString().trim().toLowerCase();
      return s == 'false' || s == '0';
    }

    String? pickArchiveId(Map<String, dynamic> m) {
      return _firstNonEmptyNullable([
        m['archive_id']?.toString(),
        m['archiveId']?.toString(),
        m['ia_collection']?.toString(),
      ]);
    }

    walkContainer(root['main'], (key, record) {
      if (isExplicitlyHidden(record)) return;
      final id = _firstNonEmpty(record['id']?.toString(), key);
      if (id.isEmpty) return;
      final name = _firstNonEmpty(
        record['name']?.toString(),
        record['title']?.toString(),
        id,
      );
      main.add({
        'id': id,
        'name': name,
        'image_url': pickThumbnail(record),
        'archive_id': pickArchiveId(record),
        'order_index': record['order_index'],
      });
    });

    walkContainer(root['sub'], (key, record) {
      if (isExplicitlyHidden(record)) return;
      final id = _firstNonEmpty(record['id']?.toString(), key);
      if (id.isEmpty) return;
      final name = _firstNonEmpty(
        record['name']?.toString(),
        record['title']?.toString(),
        id,
      );
      final mainSection = _firstNonEmpty(
        record['main_section']?.toString(),
        record['main_section_id']?.toString(),
        record['main_section_name']?.toString(),
      );
      sub.add({
        'id': id,
        'name': name,
        'main_section': mainSection,
        'image_url': pickThumbnail(record),
        'archive_id': pickArchiveId(record),
        ..._pickRemoteSource(record),
      });
    });

    walkContainer(root['secondary'], (key, record) {
      if (isExplicitlyHidden(record)) return;
      final id = _firstNonEmpty(record['id']?.toString(), key);
      if (id.isEmpty) return;
      final name = _firstNonEmpty(
        record['name']?.toString(),
        record['title']?.toString(),
        id,
      );
      final subSection = _firstNonEmpty(
        record['sub_section']?.toString(),
        record['sub_section_id']?.toString(),
        record['subsection']?.toString(),
      );
      secondary.add({
        'id': id,
        'name': name,
        'sub_section': subSection,
        'image_url': pickThumbnail(record),
        'archive_id': pickArchiveId(record),
        ..._pickRemoteSource(record),
      });
    });

    debugPrint(
      '[HomeDatasource] flat sections parsed: main=${main.length}, sub=${sub.length}, secondary=${secondary.length}',
    );
    return _SectionsParseResult(main: main, sub: sub, secondary: secondary);
  }

  _SectionsParseResult _parseLegacyTreeSections(Map<String, dynamic> root) {
    final main = <Map<String, dynamic>>[];
    final sub = <Map<String, dynamic>>[];
    final secondary = <Map<String, dynamic>>[];

    void appendSecondary(String subId, String secKey, dynamic rawSec) {
      final secMap = _asMap(rawSec);
      final secId = _firstNonEmpty(secMap['id']?.toString(), secKey);
      final secName = _firstNonEmpty(
        secMap['name']?.toString(),
        secMap['title']?.toString(),
        secId,
      );
      final secImage = _firstNonEmpty(
        secMap['thumbnail']?.toString(),
        secMap['image']?.toString(),
        secMap['image_url']?.toString(),
      );
      final secArchive = _firstNonEmpty(
        secMap['archive_id']?.toString(),
        secMap['archiveId']?.toString(),
        secMap['ia_collection']?.toString(),
      );
      if (secId.isEmpty) return;
      secondary.add({
        'id': secId,
        'name': secName,
        'sub_section': subId,
        'image_url': secImage,
        'archive_id': secArchive.isEmpty ? null : secArchive,
      });
    }

    Map<String, dynamic> mapOrListToKeyedMap(dynamic raw) {
      if (raw is List) {
        return {for (var i = 0; i < raw.length; i++) '$i': raw[i]};
      }
      return _asMap(raw);
    }

    void appendSubSecondaries(String subId, Map<String, dynamic> subMap) {
      final secondaryContainer = mapOrListToKeyedMap(
        subMap['secondary_sections'] ??
            subMap['secondary_subsections'] ??
            subMap['secondarySections'] ??
            subMap['children'],
      );
      if (secondaryContainer.isNotEmpty) {
        secondaryContainer.forEach((secKey, rawSec) {
          appendSecondary(subId, secKey, rawSec);
        });
        return;
      }
      subMap.forEach((k, v) {
        if (_isReservedSubTreeKey(k)) return;
        if (v is Map) {
          appendSecondary(subId, k, v);
        } else if (v is List) {
          for (var i = 0; i < v.length; i++) {
            appendSecondary(subId, '$i', v[i]);
          }
        }
      });
    }

    void appendSub(String mainId, String subKey, dynamic rawSub) {
      final subMap = _asMap(rawSub);
      final subId = _firstNonEmpty(subMap['id']?.toString(), subKey);
      final subName = _firstNonEmpty(
        subMap['name']?.toString(),
        subMap['title']?.toString(),
        subId,
      );
      final subImage = _firstNonEmpty(
        subMap['thumbnail']?.toString(),
        subMap['image']?.toString(),
        subMap['image_url']?.toString(),
      );
      final subArchive = _firstNonEmpty(
        subMap['archive_id']?.toString(),
        subMap['archiveId']?.toString(),
        subMap['ia_collection']?.toString(),
      );
      if (subId.isEmpty) return;
      sub.add({
        'id': subId,
        'name': subName,
        'main_section': mainId,
        'image_url': subImage,
        'archive_id': subArchive.isEmpty ? null : subArchive,
      });
      appendSubSecondaries(subId, subMap);
    }

    void parseMainBlock(String mainKey, dynamic rawMain) {
      if (rawMain is List) {
        for (var i = 0; i < rawMain.length; i++) {
          parseMainBlock('$mainKey:$i', rawMain[i]);
        }
        return;
      }
      final mainMap = _asMap(rawMain);
      final mainId = _firstNonEmpty(
        mainMap['id']?.toString(),
        mainMap['slug']?.toString(),
        mainKey,
      );
      final mainName = _firstNonEmpty(
        mainMap['name']?.toString(),
        mainMap['title']?.toString(),
        mainId,
      );
      final mainImage = _firstNonEmpty(
        mainMap['thumbnail']?.toString(),
        mainMap['image']?.toString(),
        mainMap['image_url']?.toString(),
      );
      final mainArchive = _firstNonEmpty(
        mainMap['archive_id']?.toString(),
        mainMap['archiveId']?.toString(),
        mainMap['ia_collection']?.toString(),
      );
      if (mainId.isEmpty) return;
      main.add({
        'id': mainId,
        'name': mainName,
        'image_url': mainImage,
        'archive_id': mainArchive.isEmpty ? null : mainArchive,
      });

      final subContainer = mapOrListToKeyedMap(
        mainMap['sub_sections'] ??
            mainMap['subsections'] ??
            mainMap['subSections'] ??
            mainMap['children'],
      );
      if (subContainer.isNotEmpty) {
        subContainer.forEach((subKey, rawSub) {
          appendSub(mainId, subKey, rawSub);
        });
        return;
      }

      mainMap.forEach((k, v) {
        if (_isReservedMainTreeKey(k)) return;
        if (v is Map) {
          appendSub(mainId, k, v);
        } else if (v is List) {
          for (var i = 0; i < v.length; i++) {
            appendSub(mainId, '$k:$i', v[i]);
          }
        }
      });
    }

    root.forEach(parseMainBlock);

    return _SectionsParseResult(main: main, sub: sub, secondary: secondary);
  }

  static bool _isReservedMainTreeKey(String key) {
    const reserved = {
      'id',
      'name',
      'title',
      'slug',
      'description',
      'order',
      'icon',
      'type',
      'created_at',
      'updated_at',
      'createdAt',
      'updatedAt',
      'sub_sections',
      'subsections',
      'subSections',
      'children',
    };
    return reserved.contains(key);
  }

  static bool _isReservedSubTreeKey(String key) {
    const reserved = {
      'id',
      'name',
      'title',
      'slug',
      'description',
      'order',
      'icon',
      'type',
      'created_at',
      'updated_at',
      'createdAt',
      'updatedAt',
      'main_section',
      'main_section_id',
      'main_section_name',
      'secondary_sections',
      'secondary_subsections',
      'secondarySections',
      'children',
      'sub_section',
      'subsection',
    };
    return reserved.contains(key);
  }

  Content _mapContentFromRtdb(Map<String, dynamic> row) {
    return Content.fromJson({...row, 'id': row['id']?.toString() ?? ''});
  }

  /// حارس قبل عرض أي وثيقة. يستبعد:
  ///   • وثيقة بدون sourceUrl صالح (تسبّب "No source available")
  ///   • youtube/audio/video بدون رابط (sourceUrl null)
  ///   • روابط ليست http(s) — حماية من رابط غير قابل للتشغيل
  /// راجع `search_datasource.dart > _isPlayableAndCompliant` — منطق متطابق.
  static bool _isPlayableAndCompliant(Content item) {
    final url = item.sourceUrl?.trim() ?? '';
    if (url.isEmpty) return false;
    if (!(url.startsWith('http://') || url.startsWith('https://'))) return false;
    // التطبيق لا يتصل بـ archive.org إطلاقاً (Content.fromJson يُلغيه أصلاً،
    // وهذا حارس ثانٍ صريح).
    if (url.toLowerCase().contains('archive.org')) return false;
    // امتثال الحقوق: محتوى وضعته اللوحة كـ rejected (بلاغ صحيح/غير مرخّص)
    // يُحجب عن الجميع.
    if (item.licenseStatus == 'rejected') return false;
    // احترام رأي المُبلِّغ: لا يظهر له المحتوى الذي أبلغ عنه.
    if (HiddenContentService.instance.isHidden(item.id)) return false;
    return true;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return {};
  }

  List<_SectionMeta> _resolveSubParentsAgainstMains(
    List<_SectionMeta> subs,
    Map<String, String> mainLookup,
  ) {
    return subs.map((s) {
      final p = s.parentId.trim();
      if (p.isEmpty) return s;
      final resolved = mainLookup[p];
      if (resolved != null) {
        return _SectionMeta(
          id: s.id,
          name: s.name,
          parentId: resolved,
          imageUrl: s.imageUrl,
          archiveId: s.archiveId,
          remoteSourceApp: s.remoteSourceApp,
          remoteSourceLevel: s.remoteSourceLevel,
          remoteSourceId: s.remoteSourceId,
        );
      }
      return s;
    }).toList();
  }

  _SectionMeta? _parseMainSection(Map<String, dynamic> json) {
    final id = _firstNonEmpty(
      json['id']?.toString(),
      json['slug']?.toString(),
      json['name']?.toString(),
    );
    final name = _firstNonEmpty(
      json['name']?.toString(),
      json['title']?.toString(),
      id,
    );
    if (id.isEmpty || name.isEmpty) return null;
    final imageUrl = _firstNonEmpty(
      json['thumbnail']?.toString(),
      json['image_url']?.toString(),
      json['image']?.toString(),
    );
    return _SectionMeta(
      id: id,
      name: name,
      imageUrl: imageUrl,
      archiveId: _pickArchive(json),
    );
  }

  _SectionMeta? _parseSubSection(Map<String, dynamic> json) {
    final id = _firstNonEmpty(json['id']?.toString(), json['name']?.toString());
    final name = _firstNonEmpty(
      json['name']?.toString(),
      json['title']?.toString(),
      id,
    );
    final parentId = _firstNonEmpty(
      json['main_section']?.toString(),
      json['main_section_id']?.toString(),
      json['main_section_name']?.toString(),
    );
    if (id.isEmpty || name.isEmpty) return null;
    final imageUrl = _firstNonEmpty(
      json['thumbnail']?.toString(),
      json['image_url']?.toString(),
      json['image']?.toString(),
    );
    return _SectionMeta(
      id: id,
      name: name,
      parentId: parentId,
      imageUrl: imageUrl,
      archiveId: _pickArchive(json),
      remoteSourceApp: _firstNonEmptyNullable([
        json['remote_source_app']?.toString(),
        json['remoteSourceApp']?.toString(),
      ]),
      remoteSourceLevel: _firstNonEmptyNullable([
        json['remote_source_level']?.toString(),
        json['remoteSourceLevel']?.toString(),
      ]),
      remoteSourceId: _firstNonEmptyNullable([
        json['remote_source_id']?.toString(),
        json['remoteSourceId']?.toString(),
      ]),
    );
  }

  _SectionMeta? _parseSecondarySection(Map<String, dynamic> json) {
    final id = _firstNonEmpty(json['id']?.toString(), json['name']?.toString());
    final name = _firstNonEmpty(
      json['name']?.toString(),
      json['title']?.toString(),
      id,
    );
    final parentId = _firstNonEmpty(
      json['sub_section']?.toString(),
      json['sub_section_id']?.toString(),
      json['subsection']?.toString(),
    );
    if (id.isEmpty || name.isEmpty) return null;
    final imageUrl = _firstNonEmpty(
      json['thumbnail']?.toString(),
      json['image_url']?.toString(),
      json['image']?.toString(),
    );
    return _SectionMeta(
      id: id,
      name: name,
      parentId: parentId,
      imageUrl: imageUrl,
      archiveId: _pickArchive(json),
      remoteSourceApp: _firstNonEmptyNullable([
        json['remote_source_app']?.toString(),
        json['remoteSourceApp']?.toString(),
      ]),
      remoteSourceLevel: _firstNonEmptyNullable([
        json['remote_source_level']?.toString(),
        json['remoteSourceLevel']?.toString(),
      ]),
      remoteSourceId: _firstNonEmptyNullable([
        json['remote_source_id']?.toString(),
        json['remoteSourceId']?.toString(),
      ]),
    );
  }

  /// استخراج حقول ربط المصدر الخارجي (مثل OldApp) من سجلّ RTDB. تبقى
  /// الحقول غير موجودة إن لم تُضبط من لوحة التحكّم — عندها لن يتدخّل
  /// جسر OldApp بتاتًا (وهذا هو السلوك المطلوب).
  static Map<String, Object?> _pickRemoteSource(Map<String, dynamic> record) {
    final app = _firstNonEmptyNullable([
      record['remote_source_app']?.toString(),
      record['remoteSourceApp']?.toString(),
    ]);
    final level = _firstNonEmptyNullable([
      record['remote_source_level']?.toString(),
      record['remoteSourceLevel']?.toString(),
    ]);
    final rid = _firstNonEmptyNullable([
      record['remote_source_id']?.toString(),
      record['remoteSourceId']?.toString(),
    ]);
    if (app == null && level == null && rid == null) return const {};
    return <String, Object?>{
      'remote_source_app': app,
      'remote_source_level': level,
      'remote_source_id': rid,
    };
  }

  static String? _pickArchive(Map<String, dynamic> json) {
    return null;
  }

  List<HomeSection> _buildGroupedFallback(List<Content> allItems) {
    final grouped = <String, List<Content>>{};
    for (final item in allItems) {
      final key = item.section.isNotEmpty ? item.section : 'other';
      grouped.putIfAbsent(key, () => <Content>[]);
      grouped[key]!.add(item);
    }

    return grouped.entries.map((entry) {
      final sorted = [...entry.value]..sort(compareContentOldestFirst);
      final types = sorted.map((c) => c.type).toSet();
      final type = types.length == 1 ? sorted.first.type.name : 'mixed';
      final apiSectionName = sorted
          .firstWhere(
            (c) => c.sectionName != null && c.sectionName!.isNotEmpty,
            orElse: () => sorted.first,
          )
          .sectionName;
      return HomeSection(
        id: 'fallback:${entry.key}',
        title: apiSectionName ?? _typeFallbackTitle(type) ?? entry.key,
        type: type,
        items: sorted,
      );
    }).toList();
  }

  static String _firstNonEmpty(String? a, [String? b, String? c]) {
    for (final value in [a, b, c]) {
      final normalized = (value ?? '').trim();
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }

  static String? _firstNonEmptyNullable(Iterable<String?> values) {
    for (final value in values) {
      final normalized = (value ?? '').trim();
      if (normalized.isNotEmpty) return normalized;
    }
    return null;
  }

  /// بادئات المعرّفات التي تُنتجها جسور المصادر الخارجيّة داخل الـ Dashboard
  /// (Mshcat / OldApp). أيّ معرّف يبدأ بإحداها
  /// إمّا أن يكون مُسجَّلًا صراحةً في `sections_unified` بحقول `remote_source_*`
  /// (فيُعامَل كقسم حقيقيّ مرتبط بمصدر)، وإمّا أن يكون بقايا محتوى يتيم لمصدر
  /// حُذف/أُعيد ربطه فلا نسمح بتحويله لقسم وهميّ يحمل الـ ID الخام كاسم.
  static const List<String> _externalIdPrefixes = [
    'mshcat:',
    'oldapp:',
    'old:',
  ];

  static bool _looksLikeExternalRef(String id) {
    if (id.isEmpty) return false;
    for (final p in _externalIdPrefixes) {
      if (id.startsWith(p)) return true;
    }
    return false;
  }

  static List<Content> _dedupeById(List<Content> items) {
    final map = <String, Content>{};
    for (final item in items) {
      map[item.id] = item;
    }
    return map.values.toList();
  }

  static String? _typeFallbackTitle(String type) {
    switch (type) {
      case 'video':
        return 'Videos';
      case 'audio':
        return 'Audio';
      case 'book':
        return 'Books';
      case 'youtube':
        return 'Videos';
      default:
        return null;
    }
  }

  List<HomeSection> _appendFallbackSections(
    List<HomeSection> sections,
    List<Content> allItems,
  ) {
    final existingIds = <String>{};
    for (final section in sections) {
      for (final item in section.items) {
        existingIds.add(item.id);
      }
    }

    final orphanItems = allItems
        .where((item) => item.id.isNotEmpty && !existingIds.contains(item.id))
        .toList();

    if (orphanItems.isEmpty) return sections;

    debugPrint(
      '[HomeDatasource] appending fallback sections for orphan items: ${orphanItems.length}',
    );

    return [...sections, ..._buildGroupedFallback(orphanItems)];
  }
}

List<Map<String, dynamic>> _parseAndNormalizeContentRows(
  Map<String, dynamic> root,
) {
  final rows = <Map<String, dynamic>>[];

  void walk(dynamic value, {String? keyHint}) {
    if (value is Map) {
      final map = value.map((key, val) => MapEntry(key.toString(), val));
      if (RtdbUploadNormalizer.shouldTreatAsContentNode(
        map,
        keyHint: keyHint,
      )) {
        rows.add({
          'id': _firstNonEmptyBackground(map['id']?.toString(), keyHint ?? ''),
          ...map,
        });
      }

      map.forEach((k, v) => walk(v, keyHint: k));
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        walk(value[i], keyHint: '$i');
      }
    }
  }

  walk(root);
  return rows
      .map(
        (r) => RtdbUploadNormalizer.normalizeRow(Map<String, dynamic>.from(r)),
      )
      .toList();
}

String _firstNonEmptyBackground(String? a, [String? b, String? c]) {
  for (final value in [a, b, c]) {
    final normalized = (value ?? '').trim();
    if (normalized.isNotEmpty) return normalized;
  }
  return '';
}

class _SectionMeta {
  final String id;
  final String name;
  final String parentId;
  final String? imageUrl;
  final String? archiveId;
  final String? remoteSourceApp;
  final String? remoteSourceLevel;
  final String? remoteSourceId;

  const _SectionMeta({
    required this.id,
    required this.name,
    this.parentId = '',
    this.imageUrl,
    this.archiveId,
    this.remoteSourceApp,
    this.remoteSourceLevel,
    this.remoteSourceId,
  });
}

class _SectionsParseResult {
  final List<Map<String, dynamic>> main;
  final List<Map<String, dynamic>> sub;
  final List<Map<String, dynamic>> secondary;

  const _SectionsParseResult({
    required this.main,
    required this.sub,
    required this.secondary,
  });
}
