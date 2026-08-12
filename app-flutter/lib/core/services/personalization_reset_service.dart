import 'package:nebras_mobile_app/core/services/continue_watching_service.dart';
import 'package:nebras_mobile_app/core/services/interest_profile_service.dart';
import 'package:nebras_mobile_app/core/services/user_behavior_tracker.dart';

/// مسح إشارات التخصيص **المحليّة** فقط.
///
/// لا يمسّ `view_count` / `play_count` على Firestore — تبقى مجهولة وعامّة.
/// يُستدعى من «نسيان اهتماماتي» ومن `signOut`.
class PersonalizationResetService {
  PersonalizationResetService._();

  static final PersonalizationResetService instance =
      PersonalizationResetService._();

  Future<void> forgetAllLocalSignals() async {
    await Future.wait([
      InterestProfileService.instance.clearProfile(),
      UserBehaviorTracker.instance.clear(),
      ContinueWatchingService.instance.clearAll(),
    ]);
  }
}
