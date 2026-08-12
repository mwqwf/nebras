import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import 'config.dart';

/// أسماء مجموعات Firestore — تطابق ما تكتبه لوحة الويب ويقرأه تطبيق الجوال.
class FsPaths {
  FsPaths._();

  static const String sections = 'sections_unified';
  static const String uploads = 'dashboard_uploads';
  static const String contentFiles = 'content_unified_files';
  static const String contentYoutube = 'content_unified_youtube';
}

/// الوصول إلى قاعدة Firestore المسمّاة `default` (مثل `getFirestore(app,'default')`
/// في الويب و`FirebaseFirestore.instanceFor(databaseId:'default')` في الجوال).
FirebaseFirestore nebrasFirestore() => FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: AppConfig.firestoreDatabaseId,
    );
