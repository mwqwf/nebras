import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';

/// Abstract contract for Home Repository
abstract class HomeRepository {
  Future<List<HomeSection>> getHomeData({int page = 1});

  /// Real-time stream — يتدفّق لحظياً عند أيّ تغيير في Firebase RTDB.
  /// يُستخدم في HomeProvider لضمان ظهور المحتوى الجديد فوراً دون إعادة
  /// تشغيل التطبيق أو مسح التخزين.
  Stream<List<HomeSection>> watchHomeData({int page = 1});

  /// لقطة محفوظة محليّاً تُعرض فوراً عند الإقلاع قبل وصول أوّل لقطة حيّة.
  List<HomeSection> cachedHomeSections();
}
