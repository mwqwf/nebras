import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'auth/auth_provider.dart';
import 'services/notifications_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // على Android نعتمد على google-services.json (الموصول عبر مُلحق Gradle)
  // فيُختار التطبيق المطابق لـ applicationId تلقائيّاً.
  await Firebase.initializeApp();
  // رسائل FCM في الخلفيّة (data-only — يعرضها التطبيق محليّاً).
  FirebaseMessaging.onBackgroundMessage(nebrasFcmBackgroundHandler);

  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: const NebrasDashboardApp(),
    ),
  );
}
