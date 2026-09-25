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

  /// İstanbul gününün (00:00) açılışı. `null`: sunucu ölçemedi (ör. USDT
  /// paritesinde açılış kuru gelmedi) — günlük yüzde gösterilmez, uydurulmaz.
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

/// Kripto kataloğundan bir satır (`kripto_varlik` + son fiyat), seçicide
/// ve takip listesi aramasında gösterilir.
///
/// Katalog ~350 satırdır (TRY pariteleri + hacimce ilk 250); bir kez
/// çekilip istemcide süzülür. Her tuşta sunucuya gitmek hem gecikme hem
/// istek demekti, liste zaten küçük.
class KriptoKatalogOgesi {
  const KriptoKatalogOgesi({
    required this.kod,
    this.ad,
    this.logoUrl,
    this.hacimSirasi,
    this.fiyat,
  });

  final String kod;

  /// Binance varlık adı; o tur gelmediyse `null`, arayüz kodu gösterir.
  final String? ad;

  /// Yalnız `https://` (0074 CHECK'i); aksi `null`.
  final String? logoUrl;
  final int? hacimSirasi;

  /// Henüz fiyatlanmamış coin'de `null` — seçilebilir, fiyat boş kalır.
  final KriptoFiyat? fiyat;

  String get gorunenAd => (ad == null || ad!.trim().isEmpty) ? kod : ad!;

  static KriptoKatalogOgesi? fromMap(Map<String, dynamic> m) {
    final kod = (m['kod'] as String?)?.trim().toUpperCase();
    if (kod == null || kod.isEmpty) return null;
    final logo = m['logo_url'] as String?;
    // PostgREST bire-bir gömmeyi nesne döner; eski sürüm liste dönebilir.
    final gomulu = m['kripto_fiyat'];
    final fiyatMap = gomulu is Map<String, dynamic>
        ? gomulu
        : (gomulu is List && gomulu.isNotEmpty && gomulu.first is Map<String, dynamic>)
            ? gomulu.first as Map<String, dynamic>
            : null;
    return KriptoKatalogOgesi(
      kod: kod,
      ad: (m['ad'] as String?)?.trim(),
      logoUrl: logo != null && logo.startsWith('https://') ? logo : null,
      hacimSirasi: (m['hacim_sirasi'] as num?)?.toInt(),
      fiyat: fiyatMap == null ? null : KriptoFiyat.fromMap({...fiyatMap, 'kod': kod}),
    );
  }
}

/// Katalogda arama. Sıra: kod tam eşleşme → kod öneki → ad öneki → ad/kod
/// içinde geçen; her grup kendi içinde hacim sırasını korur. "ETH" yazan
/// kullanıcı ETH'yi ilk sırada görmeli, ETHFI'yi değil.
List<KriptoKatalogOgesi> kriptoAra(List<KriptoKatalogOgesi> katalog, String sorgu) {
  final q = sorgu.trim().toUpperCase();
  if (q.isEmpty) return katalog;
  final tam = <KriptoKatalogOgesi>[];
  final kodOnek = <KriptoKatalogOgesi>[];
  final adOnek = <KriptoKatalogOgesi>[];
  final icinde = <KriptoKatalogOgesi>[];
  for (final o in katalog) {
    final ad = (o.ad ?? '').toUpperCase();
    if (o.kod == q) {
      tam.add(o);
    } else if (o.kod.startsWith(q)) {
      kodOnek.add(o);
    } else if (ad.startsWith(q)) {
      adOnek.add(o);
    } else if (o.kod.contains(q) || ad.contains(q)) {
      icinde.add(o);
    }
  }
  return [...tam, ...kodOnek, ...adOnek, ...icinde];
}
