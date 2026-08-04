class AppUser {
  final String id;
  final String email;
  final String displayName;
  final DateTime createdAt;
  final bool onboardingCompleted;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
    this.onboardingCompleted = false,
  });

  AppUser copyWith({bool? onboardingCompleted}) => AppUser(
        id: id,
        email: email,
        displayName: displayName,
        createdAt: createdAt,
        onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        'onboarding_completed': onboardingCompleted,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        id: m['id'] as String,
        email: m['email'] as String,
        displayName: m['display_name'] as String,
        onboardingCompleted: (m['onboarding_completed'] as bool?) ?? false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );

  /// Ağ yokken profil tablosu okunamadığında, yerel oturum token'ındaki
  /// bilgiden kurulan minimal kullanıcı.
  ///
  /// `displayName` boş kalır — çağıran taraf bunu "profil henüz gelmedi"
  /// olarak yorumlayıp e-postaya düşebilir. `onboardingCompleted` burada
  /// anlamlı değildir; onboarding kapısı `OnboardingScreen.isCompleted`
  /// üzerinden ayrıca karar verir.
  factory AppUser.fromSession({
    required String id,
    String? email,
    String? displayName,
    String? createdAt,
  }) =>
      AppUser(
        id: id,
        email: email ?? '',
        displayName: displayName ?? '',
        createdAt:
            (createdAt != null ? DateTime.tryParse(createdAt) : null) ??
                DateTime.now(),
      );

  factory AppUser.fromSupabase(Map<String, dynamic> m) => AppUser(
        id: m['id'] as String,
        email: m['email'] as String,
        displayName: m['display_name'] as String,
        onboardingCompleted: (m['onboarding_completed'] as bool?) ?? false,
        createdAt: m['created_at'] != null
            ? DateTime.parse(m['created_at'] as String)
            : DateTime.now(),
      );
}
