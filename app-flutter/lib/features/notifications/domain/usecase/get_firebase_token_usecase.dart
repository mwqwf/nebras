// domain/usecase/get_firebase_token_usecase.dart
import '../repos/firebase_token_repo.dart';

class GetFirebaseTokenUseCase {
  final FirebaseTokenRepo repository;

  GetFirebaseTokenUseCase(this.repository);

  Future<String?> call() async {
    return await repository.getDeviceToken();
  }
}