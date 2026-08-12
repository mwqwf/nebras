import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// تفعيل كاش Firestore على القرص للمنصات الأصلية. الويب لا يدعم persistence هنا،
/// لذلك نعتمد هناك على Hive metadata cache الذي يسبق أي انتظار للشبكة.
class FirestoreSyncConfig {
  const FirestoreSyncConfig._();

  /// قاعدة Firestore المسمّاة في مشروع nebras-9118c (بدون أقواس).
  ///
  /// لوحة التحكم والـ Admin SDK يستخدمان `getFirestore(app, 'default')`.
  /// `FirebaseFirestore.instance` على الموبايل يتّصل افتراضياً بـ `(default)`
  /// (مع أقواس) — قاعدة مختلفة غير موجودة، فيرجع NOT_FOUND وتبقى الشاشة فارغة
  /// بينما يعمل FCM لأنّه لا يمرّ عبر Firestore.
  static const String nebrasDatabaseId = 'default';

  static FirebaseFirestore get instance => FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: nebrasDatabaseId,
      );

  static Future<void> configure(FirebaseFirestore firestore) async {
    if (kIsWeb) return;
    try {
      firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 100 * 1024 * 1024,
      );
    } catch (e) {
      debugPrint('[FirestoreSyncConfig] persistence already locked: $e');
    }
  }

  /// قراءة تستفيد من الكاش ثم تتزامن مع الخادم (`serverAndCache`) حتى لا تبقى
  /// وثائق محذوفة في الواجهة عند عودة الشبكة.
  static Future<QuerySnapshot<Map<String, dynamic>>> cacheFirstFresh(
    Query<Map<String, dynamic>> query,
  ) =>
      query.get(const GetOptions(source: Source.serverAndCache));
}
