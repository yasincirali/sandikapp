/// Kullanıcının adlandırdığı portföy (`public.portfoyler`, 0133).
///
/// ## Neden yalnız AD ve SIRA
/// Portföy bir lot kümesinin etiketidir; değeri, maliyeti, getirisi lotlardan
/// hesaplanır (`gorunum_kapsami.dart`). Tabloya toplam ya da dağılım
/// yazılmaz: iki kaynaktan beslenen bir toplam "Σ parça == bütün"
/// değişmezini er geç kırar (bkz. kırılım değişmezi).
///
/// "Ana portföy" bir satır DEĞİLDİR: `assets.portfoy_id IS NULL` olan
/// lotlardır. Böylece çoklu portföy öncesi bütün defter ve eski sürümün
/// yazdığı her satır, hiçbir göç koşmadan Ana'da durur; portföy silinince
/// lotları da (FK `on delete set null`) Ana'ya döner — veri kaybı yok.
class Portfoy {
  const Portfoy({
    required this.id,
    required this.userId,
    required this.ad,
    this.sira = 0,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String ad;

  /// Seçicideki sıra (küçük önce). Eşitlikte oluşturulma anı.
  final int sira;
  final DateTime? createdAt;

  /// Ad sınırı — sunucudaki `check (char_length(btrim(ad)) between 1 and 40)`
  /// ile AYNI. Form basmadan önce gösterir (girdi kuralları istemcide).
  static const adAzami = 40;

  /// Ad geçerli mi: kırpılmış hâli 1–40 karakter.
  static bool adGecerli(String ad) {
    final t = ad.trim();
    return t.isNotEmpty && t.length <= adAzami;
  }

  Portfoy kopya({String? ad, int? sira}) => Portfoy(
        id: id,
        userId: userId,
        ad: ad ?? this.ad,
        sira: sira ?? this.sira,
        createdAt: createdAt,
      );

  /// Yalnız istemcinin yazdığı sütunlar; `user_id` varsayılanı
  /// `auth.uid()`, zaman damgaları sunucuda.
  Map<String, dynamic> toSupabase() => {
        'id': id,
        'user_id': userId,
        'ad': ad.trim(),
        'sira': sira,
      };

  factory Portfoy.fromSupabase(Map<String, dynamic> m) => Portfoy(
        id: m['id'] as String,
        userId: (m['user_id'] as String?) ?? '',
        ad: (m['ad'] as String?) ?? '',
        sira: (m['sira'] as num?)?.toInt() ?? 0,
        createdAt: m['created_at'] != null
            ? DateTime.parse(m['created_at'] as String).toLocal()
            : null,
      );

  /// Seçici sırası: [sira], sonra oluşturulma.
  static int karsilastir(Portfoy a, Portfoy b) {
    final s = a.sira.compareTo(b.sira);
    if (s != 0) return s;
    final ta = a.createdAt, tb = b.createdAt;
    if (ta == null || tb == null) return a.ad.compareTo(b.ad);
    return ta.compareTo(tb);
  }
}
