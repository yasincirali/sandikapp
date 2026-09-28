class AppUser {
  final String id;
  final String email;
  final String displayName;
  final DateTime createdAt;
  final bool onboardingCompleted;

  /// Seçilmiş kullanıcı adı (0079). `null` = henüz seçilmedi; seçilince
  /// sunucu `displayName`'i buna eşitler, ortak da bu adı görür.
  final String? username;

  /// Profil sunucudan/önbellekten değil, yalnız oturum token'ından
  /// kuruldu ([AppUser.fromSession]). Böyle bir kullanıcının
  /// [username]'i BİLİNMİYOR demektir, boş değil.
  final bool eksikProfil;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
    this.onboardingCompleted = false,
    this.username,
    this.eksikProfil = false,
  });

  /// Zorunlu kullanıcı adı ekranı açılmalı mı? Ağ yokken kurulan eksik
  /// profilde açılmaz: adı zaten seçmiş kullanıcıya bağlantı gelene kadar
  /// yanlışlıkla sorulur, kaydetme de ağsız başarısız olurdu.
  bool get kullaniciAdiGerekli => username == null && !eksikProfil;

  AppUser copyWith({bool? onboardingCompleted, String? username}) => AppUser(
        id: id,
        email: email,
        // Sunucu tetikleyicisiyle aynı kural: kullanıcı adı görünen addır.
        displayName: username ?? displayName,
        createdAt: createdAt,
        onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
        username: username ?? this.username,
        eksikProfil: eksikProfil,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        'onboarding_completed': onboardingCompleted,
        'created_at': createdAt.millisecondsSinceEpoch,
        'username': username,
      };

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        id: m['id'] as String,
        email: m['email'] as String,
        displayName: m['display_name'] as String,
        onboardingCompleted: (m['onboarding_completed'] as bool?) ?? false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        username: m['username'] as String?,
        // 0079 öncesi yazılmış önbellek kaydında anahtar yok: ad seçilmiş
        // de olabilir, bilinmiyor. Gerçek profil arkadan gelip karar verir
        // (yoksa adı başka cihazda seçmiş kullanıcıya ekran bir an açılırdı).
        eksikProfil: !m.containsKey('username'),
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
        eksikProfil: true,
      );

  factory AppUser.fromSupabase(Map<String, dynamic> m) => AppUser(
        id: m['id'] as String,
        email: m['email'] as String,
        displayName: m['display_name'] as String,
        onboardingCompleted: (m['onboarding_completed'] as bool?) ?? false,
        username: m['username'] as String?,
        // Kolon yoksa (0079 henüz o sunucuya deploy edilmemiş) ad
        // BİLİNMİYOR sayılır: yeni sürüm migration'dan önce yayına çıkarsa
        // herkes kaydedemeyeceği bir zorunlu ekrana kilitlenmesin.
        eksikProfil: !m.containsKey('username'),
        createdAt: m['created_at'] != null
            ? DateTime.parse(m['created_at'] as String)
            : DateTime.now(),
      );
}
