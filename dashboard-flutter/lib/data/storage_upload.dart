import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// نتيجة الرفع — نظير `SmartUploadResult` في `smartUpload.js`.
class UploadResult {
  UploadResult({
    required this.url,
    required this.path,
    required this.contentType,
    required this.size,
    required this.filename,
  });

  final String url;
  final String path;
  final String contentType;
  final int size;
  final String filename;
}

String _sanitizeSegment(String name) {
  // إزالة أحرف التحكّم (0x00-0x1F و 0x7F) دون regex لتفادي مشاكل الترميز.
  final buffer = StringBuffer();
  for (final cu in name.trim().codeUnits) {
    if (cu <= 0x1F || cu == 0x7F) continue;
    buffer.writeCharCode(cu);
  }
  var s = buffer.toString();
  s = s.replaceAll(RegExp(r'[#$\[\]./\\:*?"<>|]+'), '_');
  if (s.length > 180) s = s.substring(0, 180);
  return s.isEmpty ? 'file' : s;
}

/// رفع ملفّ إلى دلو Nebras (مثل `smartUpload` → Storage). الترتيب الثابت:
/// Storage أولاً ثم نُعيد رابط التنزيل ليُكتب في Firestore.
///
/// [onProgress] نسبة مئويّة 0..100. [isAborted] لإلغاء الرفع.
Future<UploadResult> smartUpload({
  required Uint8List bytes,
  required String filename,
  String contentType = 'application/octet-stream',
  String folder = 'dashboard/uploads',
  void Function(double pct)? onProgress,
  bool Function()? isAborted,
  void Function(UploadTask task)? onTaskCreated,
}) async {
  final storage = FirebaseStorage.instance;
  final safeName = _sanitizeSegment(filename);
  final cleanFolder = folder.replaceAll(RegExp(r'^/+|/+$'), '');
  final path =
      '$cleanFolder/${DateTime.now().millisecondsSinceEpoch}_$safeName';
  final ref = storage.ref(path);
  final ct =
      contentType.trim().isEmpty ? 'application/octet-stream' : contentType;

  final task = ref.putData(bytes, SettableMetadata(contentType: ct));
  onTaskCreated?.call(task);

  task.snapshotEvents.listen((snap) {
    if (isAborted != null && isAborted()) {
      task.cancel();
      return;
    }
    final total = snap.totalBytes <= 0 ? bytes.length : snap.totalBytes;
    onProgress?.call((snap.bytesTransferred / total) * 100);
  });

  try {
    await task;
  } on FirebaseException catch (e) {
    if (e.code == 'canceled') {
      throw Exception('تمّ إلغاء الرفع.');
    }
    rethrow;
  }

  if (isAborted != null && isAborted()) {
    throw Exception('تمّ إلغاء الرفع.');
  }

  final url = await ref.getDownloadURL();
  return UploadResult(
    url: url,
    path: path,
    contentType: ct,
    size: bytes.length,
    filename: safeName,
  );
}

/// رفع ملفّ من المسار (بثّ — لا يُحمَّل كاملاً في الذاكرة). يُستعمل للملفّات
/// الكبيرة في الرفع المتعدّد لتفادي OOM.
Future<UploadResult> smartUploadFile({
  required File file,
  required String filename,
  String contentType = 'application/octet-stream',
  String folder = 'dashboard/uploads',
  void Function(double pct)? onProgress,
  bool Function()? isAborted,
  void Function(UploadTask task)? onTaskCreated,
}) async {
  final storage = FirebaseStorage.instance;
  final safeName = _sanitizeSegment(filename);
  final cleanFolder = folder.replaceAll(RegExp(r'^/+|/+$'), '');
  final path =
      '$cleanFolder/${DateTime.now().millisecondsSinceEpoch}_$safeName';
  final ref = storage.ref(path);
  final ct =
      contentType.trim().isEmpty ? 'application/octet-stream' : contentType;
  final size = await file.length();

  final task = ref.putFile(file, SettableMetadata(contentType: ct));
  onTaskCreated?.call(task);

  task.snapshotEvents.listen((snap) {
    if (isAborted != null && isAborted()) {
      task.cancel();
      return;
    }
    final total = snap.totalBytes <= 0 ? size : snap.totalBytes;
    onProgress?.call((snap.bytesTransferred / total) * 100);
  });

  try {
    await task;
  } on FirebaseException catch (e) {
    if (e.code == 'canceled') {
      throw Exception('تمّ إلغاء الرفع.');
    }
    rethrow;
  }

  if (isAborted != null && isAborted()) {
    throw Exception('تمّ إلغاء الرفع.');
  }

  final url = await ref.getDownloadURL();
  return UploadResult(
    url: url,
    path: path,
    contentType: ct,
    size: size,
    filename: safeName,
  );
}
