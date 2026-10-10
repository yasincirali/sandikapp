import 'package:flutter/foundation.dart';

import '../utils/tr_format.dart' show dayKey;

/// Fon X-Ray (Premium, yasin 2026-10-10) — fonun içindeki varlık sınıfları.
///
/// ## Kaynak
/// Katman B: TEFAS `dagilimSiraliGetirT`, günlük, sınıf başına yüzde. Sunucu
/// (`fon-dagilim`, 0131) fon başına en yeni günü `fon_dagilimlari`'na yazar;
/// istemci yalnız okur. Katman A (bayrak `fon_xray_kalem`): KAP aylık
/// Portföy Dağılım Raporu'nun kalemleri (0132), beş kontrolden geçenler.
/// Araştırma: tmp/arastirma/reports/Fon XRay veri kaynakları.md.
///
/// ## Neden kaba kova
/// TEFAS'ın ~57 sınıf kodu resmî olarak belgelenmemiş ve kütüphaneler
/// birbiriyle çelişiyor: pytefas `kba`'yı "döviz cinsi kamu İÇ borçlanma",
/// `kibd`'yi "kamu DIŞ borçlanma" okuyor; borsapy (~330 fonda TEFAS
/// ekranıyla ampirik eşleştirme) tam tersini. İki kod da hangi yönde
/// okunursa okunsun "döviz / dış borçlanma" kovasına düşer — çelişki ekrana
/// hiç yansımaz. Kullanıcı "hisse mi tahvil mi altın mı" sorusunu sorar;
/// "kamu kira sertifikası (TL) mi devlet tahvili mi" ayrımı ona bir şey
/// söylemez.
///
/// ## Uydurma sayı yok (fiyat kaynağı sözleşmesi madde 3)
/// Yüzdeler kaynaktan AYNEN gelir; kova yalnız aynı kovadaki kodları
/// TOPLAR. Toplam 100 değilse fark hiçbir kovaya (ne "Diğer"e ne en büyük
/// dilime) eklenmez: kart toplamı olduğu gibi söyler, portföy düzeyinde
/// fark "X-Ray dışı" kalır. Haritada olmayan kod "Diğer" değil
/// [XrayKova.etiketsiz]: bilinmeyen bir şey bilinen gibi görünmesin.
///
/// Saf: ağ yok, `BuildContext` yok. Okuma `SupabaseService.fonDagilimlari`,
/// sağlayıcı `fon_xray_provider.dart`, çizim `fon_dagilimi_karti.dart`.

/// Varlık sınıfı kovası. İlk on iki fonun içinden gelir; son üçü (döviz,
/// kripto, emtia) yalnız portföy düzeyinde, doğrudan tutulan varlıktan.
/// Sıra ekrandaki varsayılan sıradır (eşit payda).
enum XrayKova {
  bistHisse,
  yabanciHisse,
  devletBorclanma,
  ozelBorclanma,
  dovizBorclanma,
  paraPiyasasi,
  mevduat,
  kiymetliMaden,
  fon,
  gayrimenkulGirisim,
  diger,
  etiketsiz,
  doviz,
  kripto,
  emtia,
}

/// TEFAS sınıf kodu → kova. Etiketler pytefas `schema.py` ve borsapy
/// `ASSET_TYPE_LABELS` (2026-08-07); iki kaynağın çeliştiği kodlar
/// (`kba`/`kibd`) aynı kovada. Notlar yalnız açık olmayanlar için.
const Map<String, XrayKova> tefasKodKovasi = {
  // Hisse
  'hs': XrayKova.bistHisse,
  'yhs': XrayKova.yabanciHisse,
  // TL kamu borçlanması
  'dt': XrayKova.devletBorclanma, // devlet tahvili
  'hb': XrayKova.devletBorclanma, // hazine bonosu
  'kks': XrayKova.devletBorclanma, // kamu kira sertifikası
  'kkstl': XrayKova.devletBorclanma, // kamu kira sertifikası (TL)
  // Özel sektör borçlanması (TL)
  'fb': XrayKova.ozelBorclanma, // finansman bonosu
  'ost': XrayKova.ozelBorclanma, // özel sektör tahvili
  'bb': XrayKova.ozelBorclanma, // banka bonosu
  'vdm': XrayKova.ozelBorclanma, // varlığa dayalı menkul kıymet (borsapy)
  'osks': XrayKova.ozelBorclanma, // özel sektör kira sertifikası
  // Döviz cinsi / dış borçlanma — `kba`/`kibd` çelişkisi burada erir.
  'eut': XrayKova.dovizBorclanma, // eurobond
  'kba': XrayKova.dovizBorclanma,
  'kibd': XrayKova.dovizBorclanma,
  'osdb': XrayKova.dovizBorclanma, // özel sektör dış borçlanma
  'dot': XrayKova.dovizBorclanma, // döviz ödemeli bono
  'db': XrayKova.dovizBorclanma, // döviz ödemeli tahvil
  'kksd': XrayKova.dovizBorclanma, // kamu kira sertifikası (döviz)
  'kksyd': XrayKova.dovizBorclanma, // kamu yurt dışı kira sertifikası
  'oksyd': XrayKova.dovizBorclanma, // özel sektör yurt dışı kira sertifikası
  'yba': XrayKova.dovizBorclanma, // yabancı borçlanma aracı
  'ybkb': XrayKova.dovizBorclanma, // yabancı kamu borçlanma
  'ybosb': XrayKova.dovizBorclanma, // yabancı özel sektör borçlanma
  // Para piyasası
  'tpp': XrayKova.paraPiyasasi, // Takasbank para piyasası (borsapy)
  'bpp': XrayKova.paraPiyasasi, // BİST para piyasası
  'btaa': XrayKova.paraPiyasasi, // BİST taahhütlü alım
  'btas': XrayKova.paraPiyasasi, // BİST taahhütlü satım
  'r': XrayKova.paraPiyasasi, // repo
  'tr': XrayKova.paraPiyasasi, // ters repo
  // Mevduat / katılma hesabı (altın hesabı dahil: banka hesabıdır)
  'vm': XrayKova.mevduat,
  'vmtl': XrayKova.mevduat,
  'vmd': XrayKova.mevduat,
  'vmau': XrayKova.mevduat,
  'kh': XrayKova.mevduat,
  'khtl': XrayKova.mevduat,
  'khd': XrayKova.mevduat,
  'khau': XrayKova.mevduat,
  // Kıymetli maden (maden cinsinden kira sertifikası/borçlanma ve maden
  // BYF'si dahil: getirisi madenin fiyatıdır)
  'km': XrayKova.kiymetliMaden,
  'kmbyf': XrayKova.kiymetliMaden,
  'kmkba': XrayKova.kiymetliMaden,
  'kmkks': XrayKova.kiymetliMaden,
  // Fon payları
  'fkb': XrayKova.fon,
  'yyf': XrayKova.fon,
  'byf': XrayKova.fon,
  'ybyf': XrayKova.fon,
  // Gayrimenkul / girişim sermayesi
  'gykb': XrayKova.gayrimenkulGirisim,
  'gyy': XrayKova.gayrimenkulGirisim,
  'gsykb': XrayKova.gayrimenkulGirisim,
  'gsyy': XrayKova.gayrimenkulGirisim,
  'gas': XrayKova.gayrimenkulGirisim, // gayrimenkul sertifikası
  // Diğer: TEFAS'ın kendi "Diğer"i, türev, VİOP teminatı ve anlamı genel
  // "yabancı menkul kıymet" (`ymk`: hisse de olabilir borçlanma da —
  // yanlış kovaya koymaktansa "Diğer").
  'd': XrayKova.diger,
  't': XrayKova.diger,
  'vint': XrayKova.diger,
  'ymk': XrayKova.diger,
};

/// [kod]'un kovası; haritada yoksa [XrayKova.etiketsiz].
XrayKova kovaOf(String kod) =>
    tefasKodKovasi[kod.trim().toLowerCase()] ?? XrayKova.etiketsiz;

/// Kodları kovalara TOPLAR (yalnız toplama; yuvarlama, tamamlama yok).
/// Sıfır/sonsuz değerler atlanır.
Map<XrayKova, double> kovalaraTopla(Map<String, double> dagilim) {
  final out = <XrayKova, double>{};
  dagilim.forEach((kod, yuzde) {
    if (!yuzde.isFinite || yuzde == 0) return;
    final k = kovaOf(kod);
    out[k] = (out[k] ?? 0) + yuzde;
  });
  return out;
}

@immutable
class KovaPayi {
  const KovaPayi(this.kova, this.yuzde);

  final XrayKova kova;

  /// Fonun yüzdesi (kaynaktaki kodların toplamı).
  final double yuzde;
}

/// Bir fonun TEFAS sınıf dağılımı (0131 `fon_dagilimlari` satırı).
@immutable
class FonDagilimi {
  const FonDagilimi({
    required this.fonKodu,
    required this.fonTipi,
    required this.tarih,
    required this.dagilim,
  });

  final String fonKodu;

  /// YAT, EMK (BES) ya da BYF.
  final String fonTipi;

  /// Verinin ait olduğu TEFAS günü.
  final DateTime tarih;

  /// {sınıf kodu: yüzde}, kaynaktan aynen.
  final Map<String, double> dagilim;

  /// Sunucu satırından. Kod/tarih okunmuyorsa ya da hiç geçerli sınıf
  /// yoksa `null` — kart çizilmez.
  static FonDagilimi? satirdan(Map<String, dynamic> r) {
    final kod = (r['fon_kodu'] as String?)?.trim().toUpperCase() ?? '';
    final tarih = DateTime.tryParse('${r['tarih'] ?? ''}');
    final ham = r['dagilim'];
    if (kod.isEmpty || tarih == null || ham is! Map) return null;
    final dagilim = <String, double>{};
    ham.forEach((k, v) {
      final d = v is num ? v.toDouble() : null;
      if (k is String && d != null && d.isFinite && d != 0) dagilim[k] = d;
    });
    if (dagilim.isEmpty) return null;
    return FonDagilimi(
      fonKodu: kod,
      fonTipi: (r['fon_tipi'] as String?) ?? '',
      tarih: dayKey(tarih),
      dagilim: Map.unmodifiable(dagilim),
    );
  }

  /// Kovalar, büyükten küçüğe (eşitlikte [XrayKova] sırası).
  List<KovaPayi> get kovalar {
    final l = [
      for (final e in kovalaraTopla(dagilim).entries) KovaPayi(e.key, e.value),
    ]..sort((a, b) {
        final f = b.yuzde.compareTo(a.yuzde);
        return f != 0 ? f : a.kova.index.compareTo(b.kova.index);
      });
    return l;
  }

  /// Kaynaktaki yüzdelerin toplamı (100 olmak zorunda değil).
  double get toplam => dagilim.values.fold(0.0, (t, v) => t + v);

  /// Toplam 100'den yarım puandan fazla saparsa kart bunu söyler (iki
  /// ondalıklı kaynakta yuvarlama farkı ±0,1 civarı; daha büyüğü veri).
  bool get toplamSapiyor => (toplam - 100).abs() > 0.5;
}

// ── Katman A: KAP kalemleri ─────────────────────────────────────────────────

@immutable
class FonKalemi {
  const FonKalemi({
    required this.ad,
    required this.kod,
    required this.tur,
    required this.agirlik,
  });

  final String ad;

  /// Borsa kodu (ASELS, AAPL US) ya da ISIN; yoksa boş.
  final String kod;

  /// Sunucunun kalem türü (`_shared/fon_kalem.ts` `KALEM_TURLERI`).
  final String tur;

  /// Fon portföy değerine göre %, PDF'te yazdığı gibi.
  final double agirlik;

  /// Ekranda gösterilecek kısa ad: kod varsa kod (ISIN değilse), yoksa ad.
  String get etiket =>
      kod.isNotEmpty && !RegExp(r'^[A-Z]{2}[A-Z0-9]{9}\d$').hasMatch(kod)
          ? kod
          : ad;

  /// Örtüşme anahtarı: hissede borsa kodu (büyük harf), değilse null —
  /// tahvil/repo "aynı kalem" sayılmaz (farklı vade/ihraç).
  String? get hisseAnahtari {
    if (tur != 'hisse' && tur != 'yabanci_hisse') return null;
    final k = kod.trim().toUpperCase();
    return k.isEmpty ? null : k;
  }

  static FonKalemi? satirdan(Object? r) {
    if (r is! Map) return null;
    final ad = (r['ad'] as String?)?.trim() ?? '';
    final agirlik = r['agirlik'];
    if (ad.isEmpty || agirlik is! num) return null;
    final a = agirlik.toDouble();
    if (!a.isFinite || a <= 0) return null;
    return FonKalemi(
      ad: ad,
      kod: (r['kod'] as String?)?.trim() ?? '',
      tur: (r['tur'] as String?) ?? 'diger',
      agirlik: a,
    );
  }
}

/// Bir fonun bir aylık kalem listesi (0132 `fon_kalemleri`, yalnız
/// `durum = gecti` satırları RLS'ten geçer).
@immutable
class FonKalemleri {
  const FonKalemleri({
    required this.fonKodu,
    required this.donem,
    required this.kalemler,
    this.kaynakUrl,
  });

  final String fonKodu;

  /// Raporun ay sonu.
  final DateTime donem;

  /// Ağırlığa göre büyükten küçüğe.
  final List<FonKalemi> kalemler;
  final String? kaynakUrl;

  static FonKalemleri? satirdan(Map<String, dynamic> r) {
    final kod = (r['fon_kodu'] as String?)?.trim().toUpperCase() ?? '';
    final donem = DateTime.tryParse('${r['donem'] ?? ''}');
    final ham = r['kalemler'];
    if (kod.isEmpty || donem == null || ham is! List) return null;
    final kalemler = ham.map(FonKalemi.satirdan).nonNulls.toList()
      ..sort((a, b) => b.agirlik.compareTo(a.agirlik));
    if (kalemler.isEmpty) return null;
    final url = r['kaynak_url'] as String?;
    return FonKalemleri(
      fonKodu: kod,
      donem: dayKey(donem),
      kalemler: List.unmodifiable(kalemler),
      // Yalnız KAP adresi açılır (sunucu kısıtı da aynı, 0132).
      kaynakUrl:
          url != null && url.startsWith('https://www.kap.org.tr/') ? url : null,
    );
  }

  /// Kartta gösterilen ilk [n] kalem.
  List<FonKalemi> ilk(int n) => kalemler.take(n).toList();
}
