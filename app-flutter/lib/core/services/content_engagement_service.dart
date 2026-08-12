import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/core/firebase/firestore_sync_config.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';

/// عدّادات المشاهدة على Firestore — **مجهولة** (بدون UID).
///
/// - `view_count`: عند فتح المحتوى (debounce دقيقة/عنصر).
/// - `play_count`: عند تجاوز 25% من المدّة (مرّة واحدة/جلسة).
/// - `complete_count`: عند تجاوز 90% (مرّة واحدة/جلسة).
///
/// راجع [docs/CONTENT_ORDERING_AND_HOME.md].
class ContentEngagementService {
  ContentEngagementService._();

  static final ContentEngagementService instance =
      ContentEngagementService._();

  static const _filesCollection = 'content_unified_files';
  static const _youtubeCollection = 'content_unified_youtube';
  static const _viewDebounce = Duration(minutes: 1);
  static const _flushEvery = Duration(seconds: 5);

  // قاعدة Firestore المُسمّاة `default` (وليس `(default)`) — انظر FirestoreSyncConfig.
  final FirebaseFirestore _db = FirestoreSyncConfig.instance;
  final Map<String, DateTime> _lastViewAt = {};
  final Map<String, int> _pendingViewIncrements = {};
  final Set<String> _playRecordedThisSession = {};
  final Set<String> _completeRecordedThisSession = {};
  Timer? _flushTimer;

  Future<void> recordContentOpened(Content content) => recordView(content);

  Future<void> recordView(Content content) async {
    final id = content.id.trim();
    if (id.isEmpty) return;
    final now = DateTime.now();
    final last = _lastViewAt[id];
    if (last != null && now.difference(last) < _viewDebounce) return;
    _lastViewAt[id] = now;
    _pendingViewIncrements[id] = (_pendingViewIncrements[id] ?? 0) + 1;
    _scheduleFlush();
  }

  Future<void> recordPlayMilestone(Content content, {required double ratio}) async {
    final id = content.id.trim();
    if (id.isEmpty) return;

    if (ratio >= 0.9 && !_completeRecordedThisSession.contains(id)) {
      _completeRecordedThisSession.add(id);
      try {
        final ref = _docRef(content);
        await ref.set({
          'complete_count': FieldValue.increment(1),
          'last_played_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[ContentEngagement] complete_count failed: $e');
      }
    }

    if (ratio < 0.25 || _playRecordedThisSession.contains(id)) return;
    _playRecordedThisSession.add(id);
    try {
      final ref = _docRef(content);
      await ref.set({
        'play_count': FieldValue.increment(1),
        'last_played_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[ContentEngagement] play_count failed: $e');
    }
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(_flushEvery, () {
      _flushTimer = null;
      unawaited(_flushPendingViews());
    });
  }

  Future<void> _flushPendingViews() async {
    if (_pendingViewIncrements.isEmpty) return;
    final batch = Map<String, int>.from(_pendingViewIncrements);
    _pendingViewIncrements.clear();

    for (final entry in batch.entries) {
      try {
        // نحاول الملفات ثمّ YouTube — أحد المسارين يطابق المعرّف.
        final filesRef = _db.collection(_filesCollection).doc(entry.key);
        final ytRef = _db.collection(_youtubeCollection).doc(entry.key);
        final snap = await filesRef.get();
        final target = snap.exists ? filesRef : ytRef;
        await target.set({
          'view_count': FieldValue.increment(entry.value),
          'last_played_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[ContentEngagement] view_count failed ${entry.key}: $e');
      }
    }
  }

  DocumentReference<Map<String, dynamic>> _docRef(Content content) {
    if (content.type == ContentType.youtube) {
      return _db.collection(_youtubeCollection).doc(content.id);
    }
    return _db.collection(_filesCollection).doc(content.id);
  }
}
