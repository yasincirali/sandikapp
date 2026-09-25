/// Sunucudaki kripto fiyat satırı (`kripto_fiyat`, 0074).
///
/// TL fiyatı sunucu hesaplar (TRY paritesi ya da USDT × USDTTRY, aynı
/// borsa); istemci ikinci bir çevrim YAPMAZ.
class KriptoFiyat {
  const KriptoFiyat({
    required this.kod,
    required this.fiyatTry,
    required this.gunAcilisTry,
    required this.guncellendi,
  });

  final String kod;
  final double fiyatTry;

  /// İstanbul gününün (00:00) açılışı. `null`: sunucu ölçemedi (ör. yedek
  /// kaynak) — günlük yüzde gösterilmez, uydurulmaz.
  final double? gunAcilisTry;
  final DateTime guncellendi;

  /// Sunucu dakikada bir yazar. Bundan eski satır "gecikmeli" sayılır:
  /// fiyat yine ölçülmüş bir değerdir, ama kullanıcı bilmeli.
  static const bayatlikEsigi = Duration(minutes: 10);

  bool bayatMi(DateTime simdi) => simdi.difference(guncellendi) > bayatlikEsigi;

  /// Günlük değişim yüzdesi (İstanbul günü) — açılış yoksa `null`.
  double? get gunlukYuzde {
    final a = gunAcilisTry;
    if (a == null || a <= 0) return null;
    return (fiyatTry / a - 1) * 100;
  }

  /// Bozuk/eksik satırda `null` — sıfır fiyatlı nesne kurulmaz.
  static KriptoFiyat? fromMap(Map<String, dynamic> m) {
    final kod = (m['kod'] as String?)?.trim().toUpperCase();
    final fiyat = (m['fiyat_try'] as num?)?.toDouble();
    final zaman = DateTime.tryParse(m['guncellendi']?.toString() ?? '');
    if (kod == null || kod.isEmpty || fiyat == null || fiyat <= 0 || zaman == null) {
      return null;
    }
    final acilis = (m['gun_acilis_try'] as num?)?.toDouble();
    return KriptoFiyat(
      kod: kod,
      fiyatTry: fiyat,
      gunAcilisTry: acilis != null && acilis > 0 ? acilis : null,
      guncellendi: zaman,
    );
  }
}
