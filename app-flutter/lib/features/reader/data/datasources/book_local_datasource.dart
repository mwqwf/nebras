import 'dart:io';

import 'package:path_provider/path_provider.dart';

class BookLocalDatasource {
  Future<bool> isDownloaded(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName.pdf');
    return file.exists();
  }

  Future<String> getFilePath(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$fileName.pdf';
  }

  /// Get the size of a partial download file
  Future<int> getPartialFileSize(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName.pdf.part');
    
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  /// Check if a partial download exists
  Future<bool> hasPartialDownload(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName.pdf.part');
    return file.exists();
  }

  /// Rename partial file to final file after successful download
  Future<void> finalizeDownload(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final partFile = File('${dir.path}/$fileName.pdf.part');
    final finalFile = File('${dir.path}/$fileName.pdf');

    if (await partFile.exists()) {
      await partFile.rename(finalFile.path);
    }
  }

  /// Delete partial download file
  Future<void> deletePartialFile(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName.pdf.part');
    
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Validate file integrity by checking size
  Future<bool> validateFileSize(String fileName, int expectedSize) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName.pdf');
    
    if (await file.exists()) {
      final actualSize = await file.length();
      return actualSize == expectedSize;
    }
    return false;
  }
}
