package com.nebras.mobile

import com.ryanheise.audioservice.AudioServiceActivity

// نرث من AudioServiceActivity (بدلاً من FlutterActivity الافتراضية) لأنّ
// مكتبة just_audio_background تعتمد على audio_service للتحكّم بإشعارات
// المشغّل وشاشة القفل. استخدام FlutterActivity يُطلق الاستثناء:
//   "The Activity class declared in your AndroidManifest.xml is wrong"
// عند استدعاء JustAudioBackground.init في main.dart.
//
// AudioServiceActivity نفسها ترث من FlutterActivity، فنحتفظ بكلّ وظائف
// Flutter الطبيعيّة (PiP، Deep Linking، FCM، ...) دون أيّ تغيير إضافيّ.
class MainActivity : AudioServiceActivity()
