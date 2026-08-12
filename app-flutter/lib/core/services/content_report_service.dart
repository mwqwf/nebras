import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nebras_mobile_app/core/firebase/firestore_sync_config.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';

/// تصنيفات البلاغ المتاحة للمستخدم. القيمة النصّيّة (code) تُخزَّن في
/// Firestore وتظهر للمالك في لوحة الإشراف.
enum ReportReason {
  copyright, // ملكية فكرية / حقوق نشر (الأهمّ)
  sexual, // محتوى جنسيّ صريح
  childSafety, // محتوى يضرّ بالأطفال
  violence, // عنف
  terrorism, // إرهاب / تطرّف
  other, // أخرى
}

extension ReportReasonCode on ReportReason {
  String get code {
    switch (this) {
      case ReportReason.copyright:
        return 'copyright';
      case ReportReason.sexual:
        return 'sexual';
      case ReportReason.childSafety:
        return 'child_safety';
      case ReportReason.violence:
        return 'violence';
      case ReportReason.terrorism:
        return 'terrorism';
      case ReportReason.other:
        return 'other';
    }
  }

  /// مفتاح الترجمة المعروض للمستخدم.
  String get labelKey {
    switch (this) {
      case ReportReason.copyright:
        return 'report_reason_copyright';
      case ReportReason.sexual:
        return 'report_reason_sexual';
      case ReportReason.childSafety:
        return 'report_reason_child_safety';
      case ReportReason.violence:
        return 'report_reason_violence';
      case ReportReason.terrorism:
        return 'report_reason_terrorism';
      case ReportReason.other:
        return 'report_reason_other';
    }
  }
}

/// يكتب بلاغات المستخدمين عن المحتوى إلى مجموعة `content_reports` في
/// Firestore. القراءة والحذف محصوران بالمالك عبر قواعد الأمان؛ الإنشاء
/// متاح لأيّ مستخدم (موقَّع أو ضيف) ليبلّغ عن أيّ مخالفة.
class ContentReportService {
  ContentReportService._();
  static final ContentReportService instance = ContentReportService._();

  static const String _collection = 'content_reports';

  Future<void> submit({
    required Content content,
    required ReportReason reason,
    String? note,
  }) async {
    final db = FirestoreSyncConfig.instance;
    await db.collection(_collection).add(<String, dynamic>{
      'contentId': content.id,
      'contentTitle': content.title,
      'contentType': content.type.name,
      'sourceUrl': content.sourceUrl ?? '',
      'section': content.section,
      'subSection': content.subSection ?? '',
      'reasonCode': reason.code,
      'note': (note ?? '').trim(),
      'reporterUid': FirebaseAuth.instance.currentUser?.uid ?? '',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// يحذف كلّ بلاغات المستخدم الحاليّ من السحابة. يُستدعى عند حذف الحساب
  /// لإزالة البيانات الشخصيّة الوحيدة المرتبطة بالـ uid (متطلَّب سياسة حذف
  /// بيانات Google Play). يجب استدعاؤه **قبل** حذف حساب Firebase Auth
  /// لأنّ قاعدة الأمان تسمح بالحذف فقط حين `reporterUid == request.auth.uid`.
  /// أيّ فشل (قاعدة/شبكة) يُبتلع بهدوء كي لا يُعطّل حذف الحساب نفسه.
  Future<void> deleteReportsForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    final db = FirestoreSyncConfig.instance;
    final snapshot = await db
        .collection(_collection)
        .where('reporterUid', isEqualTo: uid)
        .get();
    if (snapshot.docs.isEmpty) return;
    final batch = db.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
