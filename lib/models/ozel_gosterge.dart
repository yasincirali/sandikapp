/// Kullanıcının yazdığı gösterge (`public.kullanici_gostergeleri`, 0141).
///
/// Sunucuda yalnız METİN durur; betik cihazda derlenip çalışır
/// (`services/gosterge_betigi/betik.dart`). Sınırlar sunucudaki `check`
/// kısıtlarıyla AYNI — form göndermeden önce söyler.
class OzelGosterge {
  const OzelGosterge({
    required this.id,
    required this.userId,
    required this.ad,
    required this.kod,
    this.grafikte = true,
    this.olusturuldu,
  });

  final String id;
  final String userId;
  final String ad;
  final String kod;

  /// Grafikte açık mı (çip sayfasındaki anahtar).
  final bool grafikte;
  final DateTime? olusturuldu;

  static const adAzami = 40;

  /// Kullanıcı başına üst sınır — sunucu tetikleyicisi (0141) ile aynı.
  static const azamiSayi = 20;

  static bool adGecerli(String ad) {
    final t = ad.trim();
    return t.isNotEmpty && t.length <= adAzami;
  }

  OzelGosterge kopya({String? ad, String? kod, bool? grafikte}) =>
      OzelGosterge(
        id: id,
        userId: userId,
        ad: ad ?? this.ad,
        kod: kod ?? this.kod,
        grafikte: grafikte ?? this.grafikte,
        olusturuldu: olusturuldu,
      );

  factory OzelGosterge.fromSupabase(Map<String, dynamic> r) => OzelGosterge(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        ad: r['ad'] as String,
        kod: r['kod'] as String,
        grafikte: r['grafikte'] as bool? ?? true,
        olusturuldu: DateTime.tryParse(r['olusturuldu'] as String? ?? ''),
      );

  Map<String, dynamic> toSupabase() => {
        'id': id,
        'user_id': userId,
        'ad': ad.trim(),
        'kod': kod,
        'grafikte': grafikte,
      };
}
