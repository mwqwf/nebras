import 'package:hive/hive.dart';

part 'notification_model.g.dart';

/// Hive-persisted notification model
@HiveType(typeId: 2)
class NotificationModel {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String body;

  @HiveField(3)
  final String type; // 'video', 'audio', 'book'

  @HiveField(4)
  final String contentId;

  @HiveField(5)
  final DateTime createdAt;

  @HiveField(6)
  final bool isRead;
  @HiveField(7) // ← new field
  final String? sourceUrl;

  const NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.contentId,
    required this.createdAt,
    this.isRead = false,
    this.sourceUrl,
  });

  NotificationModel copyWith({bool? isRead}) {
    return NotificationModel(
      id: id,
      title: title,
      body: body,
      type: type,
      contentId: contentId,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      sourceUrl: sourceUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'type': type,
      'contentId': contentId,
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead,
    };
  }
}
