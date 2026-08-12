import 'package:hive/hive.dart';

part 'saved_item_model.g.dart';

/// Saved item content types — mirrors ContentType enum
enum SavedContentType { video, audio, book }

/// Model representing a saved content item
/// Persisted locally using Hive
@HiveType(typeId: 0)
class SavedItemModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String? imageUrl;

  @HiveField(3)
  final String contentType; // 'video', 'audio', 'book'

  @HiveField(4)
  final DateTime savedAt;

  SavedItemModel({
    required this.id,
    required this.title,
    this.imageUrl,
    required this.contentType,
    required this.savedAt,
  });

  /// Parse contentType string to enum
  SavedContentType get type {
    switch (contentType) {
      case 'video':
      case 'youtube':
        return SavedContentType.video;
      case 'audio':
        return SavedContentType.audio;
      case 'book':
      case 'document':
        return SavedContentType.book;
      default:
        return SavedContentType.video;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedItemModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
