import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';
import 'package:nebras_mobile_app/features/home/domain/get_home_data_usecase.dart';
import 'package:nebras_mobile_app/features/home/domain/home_repository.dart';
import 'package:nebras_mobile_app/features/home/providers/home_provider.dart';

void main() {
  test('home live watch falls back after weak network timeout', () async {
    final repo = _SlowHomeRepository();
    final provider = HomeProvider(GetHomeDataUseCase(repo));

    provider.startWatching();
    await Future<void>.delayed(
      HomeProvider.weakNetworkBootTimeout + const Duration(milliseconds: 100),
    );

    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
  });
}

class _SlowHomeRepository implements HomeRepository {
  @override
  Future<List<HomeSection>> getHomeData({int page = 1}) async => const [];

  @override
  Stream<List<HomeSection>> watchHomeData({int page = 1}) {
    return const Stream<List<HomeSection>>.empty().asyncExpand((_) async* {});
  }

  @override
  List<HomeSection> cachedHomeSections() => const [];
}
