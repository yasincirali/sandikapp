/// Yapay zekâ varlık notu (Balina F2, 0117 `varlik_analizi`, 2026-10-05) —
/// saf modeller.
///
/// Notu sunucu üretir ve kapıdan geçirir (`_shared/analiz.ts`
/// `kapidanGecir`): metindeki her sayı `girdi.olcumler[].gosterim`'de aynen
/// geçmek zorunda. İstemci bu yüzden sayıyı YENİDEN biçimlemez; kanıt
/// çipi sunucunun yazdığı gösterimi olduğu gibi çizer. İki yer aynı sayıyı
/// iki farklı biçimde yazmasın.
library;

/// Ücretsiz katman: başlık cümlesi + rozet + madde sayısı (`analiz_ozetleri`).
class AnalizOzeti {
  const AnalizOzeti({
    required this.ticker,
    required this.donem,
    required this.baslik,
    required this.rozet,
    required this.maddeSayisi,
  });

  final String ticker;

  /// Haftalık: anlatılan haftanın Pazartesi'si; aylık: ayın 1'i.
  final DateTime donem;
  final String baslik;
  final String? rozet;
  final int maddeSayisi;

  static AnalizOzeti? satirdan(Map<String, dynamic> r) {
    final ticker = r['ticker'] as String?;
    final donem = _gun(r['donem']);
    final baslik = (r['baslik'] as String?)?.trim();
    if (ticker == null || donem == null || baslik == null || baslik.isEmpty) {
      return null;
    }
    return AnalizOzeti(
      ticker: ticker,
      donem: donem,
      baslik: baslik,
      rozet: r['rozet'] as String?,
      maddeSayisi: (r['madde_sayisi'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Kanıt çipinin dayandığı ölçüm.
class NotOlcumu {
  const NotOlcumu({
    required this.anahtar,
    required this.ad,
    required this.gosterim,
    required this.kaynak,
    required this.tarih,
  });

  final String anahtar;
  final String ad;
  final String gosterim;
  final String kaynak;
  final DateTime? tarih;

  static NotOlcumu? satirdan(Object? ham) {
    if (ham is! Map) return null;
    final anahtar = ham['anahtar'];
    final gosterim = ham['gosterim'];
    if (anahtar is! String || gosterim is! String) return null;
    return NotOlcumu(
      anahtar: anahtar,
      ad: (ham['ad'] as String?) ?? anahtar,
      gosterim: gosterim,
      kaynak: (ham['kaynak'] as String?) ?? '',
      tarih: _gun(ham['tarih']),
    );
  }
}

class NotMaddesi {
  const NotMaddesi({required this.metin, required this.kanitlar});

  final String metin;

  /// Kanıt anahtarlarından ÇÖZÜLEBİLENLER; girdide olmayan anahtar düşer
  /// (sunucu kapısı zaten geçirmez, burada yalnız savunma).
  final List<NotOlcumu> kanitlar;
}

/// Notun tamamı (Premium). `girdi` sunucunun modele verdiği paket.
class VarlikNotu {
  const VarlikNotu({
    required this.ticker,
    required this.tur,
    required this.donem,
    required this.baslik,
    required this.maddeler,
    required this.rozet,
    required this.kod,
    required this.kaynaklar,
    required this.baslangic,
    required this.bitis,
  });

  final String ticker;
  final String tur;
  final DateTime donem;
  final String baslik;
  final List<NotMaddesi> maddeler;
  final String? rozet;

  /// Ekrandaki kısa ad ('TTE', 'THYAO', 'BTC').
  final String kod;

  /// Girdinin kaynakları, tekrarsız ('TEFAS', 'Binance'…).
  final List<String> kaynaklar;
  final DateTime? baslangic;
  final DateTime? bitis;

  static VarlikNotu? satirdan(Map<String, dynamic> r) {
    final ticker = r['ticker'] as String?;
    final tur = r['tur'] as String?;
    final donem = _gun(r['donem']);
    final baslik = (r['baslik'] as String?)?.trim();
    if (ticker == null ||
        tur == null ||
        donem == null ||
        baslik == null ||
        baslik.isEmpty) {
      return null;
    }
    final girdi = r['girdi'] is Map
        ? Map<String, dynamic>.from(r['girdi'] as Map)
        : const <String, dynamic>{};
    final olcumler = <String, NotOlcumu>{
      for (final o in (girdi['olcumler'] as List? ?? const []))
        if (NotOlcumu.satirdan(o) case final NotOlcumu n) n.anahtar: n,
    };
    final maddeler = <NotMaddesi>[];
    for (final m in (r['maddeler'] as List? ?? const [])) {
      if (m is! Map) continue;
      final metin = (m['metin'] as String?)?.trim();
      if (metin == null || metin.isEmpty) continue;
      maddeler.add(NotMaddesi(
        metin: metin,
        kanitlar: [
          for (final k in (m['kanit'] as List? ?? const []))
            if (olcumler[k] case final NotOlcumu o) o,
        ],
      ));
    }
    final kaynaklar = <String>{
      for (final o in olcumler.values)
        if (o.kaynak.isNotEmpty) o.kaynak,
    }.toList();
    return VarlikNotu(
      ticker: ticker,
      tur: tur,
      donem: donem,
      baslik: baslik,
      maddeler: maddeler,
      rozet: r['rozet'] as String?,
      kod: (girdi['kod'] as String?) ?? ticker,
      kaynaklar: kaynaklar,
      baslangic: _gun(girdi['baslangic']),
      bitis: _gun(girdi['bitis']),
    );
  }
}

DateTime? _gun(Object? ham) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${ham ?? ''}');
  if (m == null) return null;
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}
