import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';
import 'package:nebras_mobile_app/features/home/domain/home_repository.dart';

/// Thin use case wrapping HomeRepository
class GetHomeDataUseCase {
  final HomeRepository repository;

  GetHomeDataUseCase(this.repository);

  Future<List<HomeSection>> call({int page = 1}) {
    return repository.getHomeData(page: page);
  }

  /// Real-time stream — تمرير مباشر دون منطق إضافي حتى يبقى UseCase نحيفاً.
  Stream<List<HomeSection>> watch({int page = 1}) {
    return repository.watchHomeData(page: page);
  }

  /// لقطة محفوظة محليّاً (Hive) تُعرض فوراً عند الإقلاع.
  List<HomeSection> cached() => repository.cachedHomeSections();
}
