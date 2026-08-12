/// نموذج موحّد لبيانات الحساب بعد نجاح الدخول عبر Google.
///
/// تعمّدنا فصله عن `GoogleSignInAccount` مباشرةً حتى تبقى بقيّة أجزاء
/// التطبيق (Providers/Widgets) غير مشدودة لحزمة بعينها، ويسهل لاحقًا
/// ترقية المصادقة إلى Firebase Auth أو أي مزوّد ثالث بدون تغيير
/// الواجهات الأعلى.
class UserProfile {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final DateTime signedInAt;

  const UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    required this.signedInAt,
    this.photoUrl,
  });

  UserProfile copyWith({
    String? id,
    String? email,
    String? displayName,
    String? photoUrl,
    DateTime? signedInAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      signedInAt: signedInAt ?? this.signedInAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'signedInAt': signedInAt.toIso8601String(),
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: (json['id'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      photoUrl: json['photoUrl']?.toString(),
      signedInAt:
          DateTime.tryParse(json['signedInAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  @override
  String toString() => 'UserProfile($email)';
}
