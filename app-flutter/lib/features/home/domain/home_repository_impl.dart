import 'package:nebras_mobile_app/features/home/data/home_datasource.dart';
import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';
import 'package:nebras_mobile_app/features/home/domain/home_repository.dart';

/// Home Repository Implementation
/// Delegates to HomeDatasource — no UI logic
class HomeRepositoryImpl implements HomeRepository {
  final HomeDatasource datasource;

  HomeRepositoryImpl(this.datasource);

  @override
  Future<List<HomeSection>> getHomeData({int page = 1}) {
    return datasource.getHomeData(page: page);
  }

  @override
  Stream<List<HomeSection>> watchHomeData({int page = 1}) {
    // نبقي واجهة الريبو كما هي، لكن نمرر fallback أوفلاين من datasource
    // حتى تعرض الشاشة آخر ميتادات محفوظة إذا فشل listener قبل أول لقطة.
    return datasource.watchHomeDataWithOfflineFallback(page: page);
  }

  @override
  List<HomeSection> cachedHomeSections() => datasource.cachedHomeSections();
}
