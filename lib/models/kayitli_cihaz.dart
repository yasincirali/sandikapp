/// E-posta koduyla doğrulanmış (güvenilen) bir cihaz — `kayitli_cihazlar`
/// satırı (migration 0098).
class KayitliCihaz {
  final String cihazId;
  final String ad;
  final String platform;
  final DateTime ilkKayit;
  final DateTime sonGorulme;

  const KayitliCihaz({
    required this.cihazId,
    required this.ad,
    required this.platform,
    required this.ilkKayit,
    required this.sonGorulme,
  });

  factory KayitliCihaz.fromSupabase(Map<String, dynamic> r) => KayitliCihaz(
        cihazId: r['cihaz_id'] as String,
        ad: (r['ad'] as String?) ?? '',
        platform: (r['platform'] as String?) ?? 'unknown',
        ilkKayit: DateTime.parse(r['ilk_kayit'] as String).toLocal(),
        sonGorulme: DateTime.parse(r['son_gorulme'] as String).toLocal(),
      );
}

/// `cihaz_durumu` RPC yanıtı.
enum CihazDurumu {
  /// Mağaza inceleme hesabı vb. — tek cihaz kuralı uygulanmaz.
  muaf,

  /// Daha önce kodla doğrulanmış cihaz — kod sorulmaz.
  kayitli,

  /// Hesabın hiç kayıtlı cihazı yok — ilk cihaz kodsuz kaydedilir (geçiş).
  ilk,

  /// Kayıtlı olmayan cihaz — e-posta kodu istenir.
  yeni;

  static CihazDurumu? parse(Object? v) => switch (v) {
        'muaf' => muaf,
        'kayitli' => kayitli,
        'ilk' => ilk,
        'yeni' => yeni,
        _ => null,
      };
}
