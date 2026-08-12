import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/firestore_refs.dart';

/// عدّادات مساهمة المشرفين — تغذّي «لوحة الشرف» 🏆.
///
/// `admin_stats/{uid}`: {name, photo, uploads, edits, weekly.{yyyy_ww},
/// lastUploadAt}. كلّ مشرف يزيد عدّاداته هو فقط (قاعدة أمان مطابقة)،
/// والكتابة أفضل-جهد: فشلها لا يعطّل الرفع أبداً.
class AdminStats {
  AdminStats._();

  static CollectionReference<Map<String, dynamic>> get _coll =>
      nebrasFirestore().collection('admin_stats');

  /// مفتاح أسبوع بصيغة `yyyy_ww` (أسبوع تقريبي من مطلع السنة — ثابت
  /// ومتّسق بين الأعضاء، والغرض ترتيب نسبي لا تقويم دقيق).
  static String weekKey([DateTime? at]) {
    final d = at ?? DateTime.now();
    final startOfYear = DateTime(d.year, 1, 1);
    final week = (d.difference(startOfYear).inDays ~/ 7) + 1;
    return '${d.year}_${week.toString().padLeft(2, '0')}';
  }

  static Map<String, dynamic> _identity() {
    final u = FirebaseAuth.instance.currentUser;
    final name = (u?.displayName?.trim().isNotEmpty == true)
        ? u!.displayName!
        : (u?.email?.split('@').first ?? 'مستخدم');
    return {'name': name, 'photo': u?.photoURL ?? ''};
  }

  /// +1 رفع (إجمالي + أسبوعي).
  static Future<void> bumpUpload() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _coll.doc(uid).set({
        ..._identity(),
        'uploads': FieldValue.increment(1),
        // خريطة متداخلة (لا مفتاحاً منقوطاً): set+merge يدمجها بدون مسح
        // أسابيع سابقة.
        'weekly': {weekKey(): FieldValue.increment(1)},
        'lastUploadAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// +1 تعديل محتوى.
  static Future<void> bumpEdit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _coll.doc(uid).set({
        ..._identity(),
        'edits': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// بثّ لوحة الشرف (تنازلياً حسب إجمالي الرفعات).
  static Stream<List<Map<String, dynamic>>> boardStream() => _coll
      .orderBy('uploads', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map((d) {
            final m = Map<String, dynamic>.from(d.data());
            m['uid'] = d.id;
            return m;
          }).toList());
}
