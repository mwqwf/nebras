// data/repositories/firebase_token_repo_impl.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../domain/repos/firebase_token_repo.dart';

class FirebaseTokenRepoImpl implements FirebaseTokenRepo {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  @override
  Future<String?> getDeviceToken() async {
    try {
      final token = await _firebaseMessaging.getToken();
      // الـ token حسّاس: لا يُطبع إلا في وضع التطوير.
      if (kDebugMode) {
        debugPrint('Firebase Device Token: $token');
      }
      return token;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting Firebase token: $e');
      }
      return null;
    }
  }
}
