import '../../models/abd_hisseleri.dart';
import '../../models/asset_categories.dart';
import '../../models/asset_type.dart';
import '../../utils/tr_katla.dart';
import '../bist_hisse_katalogu.dart';
import '../csv_import_service.dart';
import 'ekstre_tablosu.dart';
import 'tablo_anlama.dart';

/// Yalnız TUTAR yazan varlık listesi — SAF, ağ yok.
///
/// ## Neden (2026-10-15, DenizBank "Varlık Geçmişi Formu")
/// Bankanın aylık "Varlık Geçmişi" belgesi varlığı adıyla ve yalnız TL
/// karşılığıyla yazar; adet ve birim fiyat yoktur:
///
/// ```
/// Yatırım Fonları                                         320.719,49 TRY
/// YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE---TRMYK9…   86.520,05 TRY
/// ```
///
/// Önceki sürüm bunu elle eşleme yedeğine düşürüyordu ("Adet ← Sütun 2",
/// "emin değiliz"); yapay zekâ da adet sütunu bulamıyordu çünkü yok
/// (yasin: "varlık tablosu bulamadı diyor"). Adet = tutar ÷ belge günündeki
/// birim fiyat. Fiyat UYDURULMAZ: o günün (ya da birkaç gün öncesinin son)
/// fiyatı alınamazsa satır eklenmez ve önizleme nedenini söyler.
///
/// İlk sürüm yalnız fonu tanıyordu; yasin aynı gün: "sadece fonlar için
/// değil, altın hisse döviz vs tüm varlıklar için olmalı". Tanıma yine
/// dar ve kesin işarete bağlı ([tutarKalemiCoz]); işaretsiz ad (hesap
/// numarası, "Vadesiz Mevduat") eklenmez.
enum EkstreTutarTuru { fon, hisse, abd, altin, doviz, kripto }

class EkstreTutarKalemi {
  const EkstreTutarKalemi({
    required this.ad,
    required this.tutar,
    this.para = 'TRY',
    this.tur = EkstreTutarTuru.fon,
    this.sembol,
  });

  /// Belgedeki ad (fonda ISIN ekiyle birlikte; anahtar `fonAdiAnahtari`).
  final String ad;

  /// Belgedeki tutar, [para] cinsinden.
  final double tutar;

  /// Tutarın para birimi (TRY, USD, EUR…).
  final String para;

  final EkstreTutarTuru tur;

  /// Kanonik satıra yazılan sembol (`AKBNK`, `ALTIN_GRAM24`, `USD`,
  /// `KRIPTO:BTC`, `AAPL`). Fonda `null`: kod TEFAS unvanından çözülür
  /// (`fonKoduBul`, tek aday).
  final String? sembol;

  /// Fiyatın soruluş sembolü (`PriceService.fetchHistoricalClose`).
  /// Fonda kod çözülünce `TEFAS:KOD` olur; burada `null`.
  String? get fiyatSembolu => switch (tur) {
        EkstreTutarTuru.fon => null,
        EkstreTutarTuru.hisse => '$sembol.IS',
        EkstreTutarTuru.doviz => '${sembol}TRY=X',
        _ => sembol,
      };

  /// Fiyatın para birimi: ABD hissesi dolar, gerisi TL (döviz satırında
  /// fiyat kurun kendisidir — `normalizeTicker` dövizi TRY yazar).
  String get fiyatPara => tur == EkstreTutarTuru.abd ? 'USD' : 'TRY';

  /// Kanonik metnin "tür" hücresi (`CsvImportService` tanır).
  String get turMetni => switch (tur) {
        EkstreTutarTuru.fon => 'Fon',
        EkstreTutarTuru.hisse => 'Hisse',
        EkstreTutarTuru.abd => 'ABD hissesi',
        EkstreTutarTuru.altin => 'Altın',
        EkstreTutarTuru.doviz => 'Döviz',
        EkstreTutarTuru.kripto => 'Kripto',
      };
}

/// Para birimi kodu → TL kurunun sembolü. TRY için `null` (kur 1).
String? kurSembolu(String para) => para == 'TRY' ? null : '${para}TRY=X';

final _isin = RegExp(r'(?:---|\s)\s*(TR[A-Z0-9]{10})\s*$');
final _fonKelimesi = RegExp(r'\bfonu?\b');

/// Tutar hücresi: "86.520,05 TRY", "$1,234.56", "1.234,56 USD".
final _tutarHucresi = RegExp(
    r'^(?:(\$|€|£|₺)\s*)?([0-9][0-9.,]*)\s*(try|tl|usd|eur|gbp|chf|\$|€|£|₺)?$');

const _sembolPara = {r'$': 'USD', '€': 'EUR', '£': 'GBP', '₺': 'TRY'};
const _paraKodlari = {'try': 'TRY', 'tl': 'TRY', 'usd': 'USD', 'eur': 'EUR',
  'gbp': 'GBP', 'chf': 'CHF'};

/// Grup başlıkları ("Yatırım Fonları 320.719,49 TRY") varlık değildir.
final _grupBasligi = RegExp(
    r'^(yatirim fonlari|fonlar|hisse senetleri|hisseler|pay senetleri|'
    r'altin hesaplari|kiymetli madenler?|doviz hesaplari|kripto varliklar|'
    r'vadesiz mevduat|vadeli mevduat|yabanci hisse senetleri)$');

/// Döviz adları → kod. Yalnız tam kelime; "dolar" fon adında da geçer, o
/// yüzden fon işareti önce bakılır ([tutarKalemiCoz]).
const _dovizAdlari = {
  'usd': 'USD', 'dolar': 'USD', 'abd dolari': 'USD', 'amerikan dolari': 'USD',
  'eur': 'EUR', 'euro': 'EUR', 'avro': 'EUR',
  'gbp': 'GBP', 'sterlin': 'GBP', 'ingiliz sterlini': 'GBP',
  'chf': 'CHF', 'isvicre frangi': 'CHF',
};

const _kriptoAdlari = {'bitcoin': 'BTC', 'ethereum': 'ETH'};

/// Altının alt türü (tam kelimeyle). Ayarı ya da sikkesi yazılmamış banka
/// altın hesabı 24 ayar gramdır ("gram altın" piyasada 24 ayardır); CSV'nin
/// eski 22 ayar varsayılanı burada kullanılmaz.
GoldSubCategory _altinTuru(String katli) {
  bool k(String s) => RegExp('\\b$s\\b').hasMatch(katli);
  if (k('gremse')) return GoldSubCategory.gremse;
  if (k('ikibucuk')) return GoldSubCategory.ikibucuk;
  if (k('besli')) return GoldSubCategory.besli;
  if (k('hamit')) return GoldSubCategory.hamit;
  if (k('resat')) return GoldSubCategory.resat;
  if (k('cumhuriyet')) return GoldSubCategory.cumhuriyet;
  if (k('ceyrek')) return GoldSubCategory.ceyrek;
  if (k('yarim')) return GoldSubCategory.yarim;
  if (k('ata')) return GoldSubCategory.ata;
  if (k('tam')) return GoldSubCategory.tam;
  if (k('has')) return GoldSubCategory.has;
  if (RegExp(r'\b22\b').hasMatch(katli)) return GoldSubCategory.gr22;
  if (RegExp(r'\b18\b').hasMatch(katli)) return GoldSubCategory.gr18;
  if (RegExp(r'\b14\b').hasMatch(katli)) return GoldSubCategory.gr14;
  return GoldSubCategory.gr24;
}

/// Adın kesin işareti varsa türü ve sembolü; yoksa `null` (eklenmez).
///
/// Sıra önemlidir: ISIN ve "fon" kelimesi önce ("… Altın Fonu" fondur,
/// "… (USD) Fonu" döviz değildir); BIST kodu ABD sembolünden önce.
({EkstreTutarTuru tur, String? sembol})? tutarKalemiCoz(String ad,
    String para) {
  final katli = trKatla(ad).trim();
  final isin = _isin.firstMatch(ad.toUpperCase())?.group(1);
  if (isin != null) {
    // Pay ISIN'i "TRA" + kod (W ile 5'e tamamlanır) + 4 hane: TRAAKBNK91N6.
    if (isin.startsWith('TRA')) {
      final kod = isin.substring(3, 8).replaceAll(RegExp(r'W+$'), '');
      if (BistHisseKatalogu.instance.kodMu(kod)) {
        return (tur: EkstreTutarTuru.hisse, sembol: kod);
      }
    }
    return (tur: EkstreTutarTuru.fon, sembol: null);
  }
  if (_fonKelimesi.hasMatch(katli)) {
    return (tur: EkstreTutarTuru.fon, sembol: null);
  }
  if (RegExp(r'\baltin\b').hasMatch(katli) &&
      !RegExp(r'\b(gumus|ons)\b').hasMatch(katli)) {
    final alt = _altinTuru(katli);
    return (tur: EkstreTutarTuru.altin, sembol: goldTickerMap[alt.label]);
  }
  for (final e in _kriptoAdlari.entries) {
    if (RegExp('\\b${e.key}\\b').hasMatch(katli)) {
      return (tur: EkstreTutarTuru.kripto, sembol: kriptoSembolu(e.value));
    }
  }
  final ilk = CsvImportService.sembolAyikla(ad).toUpperCase();
  final kripto = CsvImportService.kriptoKodunuCoz(ilk);
  if (kripto != null && ilk.contains(RegExp(r'[-/:]|USDT$'))) {
    return (tur: EkstreTutarTuru.kripto, sembol: kriptoSembolu(kripto));
  }
  if (RegExp(r'^[A-Z0-9]{3,6}$').hasMatch(ilk) &&
      BistHisseKatalogu.instance.kodMu(ilk)) {
    return (tur: EkstreTutarTuru.hisse, sembol: ilk);
  }
  for (final e in _dovizAdlari.entries) {
    if (RegExp('\\b${e.key}\\b').hasMatch(katli)) {
      return (tur: EkstreTutarTuru.doviz, sembol: e.value);
    }
  }
  if (para == 'USD' && CsvImportService.abdSatiriMi(ilk, null, 'USD')) {
    return (tur: EkstreTutarTuru.abd, sembol: abdSembolu(ilk));
  }
  return null;
}

/// Satırın (ad, tutar, para) üçlüsü — iki hücre ("ad", "86.520,05 TRY")
/// ya da üç hücre ("ad", "1,234.56", "USD"). Başka biçim `null`.
({String ad, double tutar, String para})? _tutarSatiri(List<String> satir) {
  final dolu = [
    for (final h in satir)
      if (h.trim().isNotEmpty) h.trim(),
  ];
  String? para;
  String tutarHam;
  if (dolu.length == 2) {
    tutarHam = dolu[1];
  } else if (dolu.length == 3 && _paraKodlari.containsKey(trKatla(dolu[2]))) {
    tutarHam = dolu[1];
    para = _paraKodlari[trKatla(dolu[2])];
  } else {
    return null;
  }
  final m = _tutarHucresi.firstMatch(trKatla(tutarHam));
  if (m == null) return null;
  final isaret = m.group(1) ?? m.group(3);
  final hucrePara = isaret == null
      ? null
      : _sembolPara[isaret] ?? _paraKodlari[isaret];
  if (para != null && hucrePara != null && para != hucrePara) return null;
  para ??= hucrePara;
  // Para birimi yazmayan tutar kabul edilmez: hangi paranın kaç birimi
  // olduğu bilinmeden adet hesaplanamaz.
  if (para == null) return null;
  final tutar = sayiCoz(m.group(2)!, turkce: para == 'TRY');
  if (tutar == null) return null;
  return (ad: dolu[0], tutar: tutar, para: para);
}

/// Tablolardaki yalnız-tutarlı varlık satırları (belge sırasıyla, tekil ad).
List<EkstreTutarKalemi> tutarliKalemler(List<EkstreTablosu> tablolar) {
  final out = <EkstreTutarKalemi>[];
  final gorulen = <String>{};
  for (final t in tablolar) {
    final satirlar = [for (final s in t.satirlar) _tutarSatiri(s)];
    for (var i = 0; i < satirlar.length; i++) {
      final s = satirlar[i];
      if (s == null || s.tutar <= 0) continue;
      final katli = trKatla(s.ad).trim();
      if (katli.contains('toplam') || _grupBasligi.hasMatch(katli)) continue;
      final coz = tutarKalemiCoz(s.ad, s.para);
      if (coz == null) continue;
      // İşaretsiz grup başlığı ("Altın 12.000 TRY" ve altında "Gram Altın
      // 12.000 TRY"): tutarı hemen altındaki satırların toplamıysa başlıktır.
      if (coz.tur != EkstreTutarTuru.fon &&
          coz.tur != EkstreTutarTuru.hisse &&
          _altToplamMi(satirlar, i)) {
        continue;
      }
      if (!gorulen.add(katli)) continue;
      out.add(EkstreTutarKalemi(
        ad: s.ad,
        tutar: s.tutar,
        para: s.para,
        tur: coz.tur,
        sembol: coz.sembol,
      ));
    }
  }
  return out;
}

bool _altToplamMi(List<({String ad, double tutar, String para})?> s, int i) {
  final hedef = s[i]!.tutar;
  var top = 0.0;
  for (var j = i + 1; j < s.length; j++) {
    final x = s[j];
    if (x == null || x.para != s[i]!.para) return false;
    top += x.tutar;
    if ((top - hedef).abs() <= 0.05) return true;
    if (top > hedef) return false;
  }
  return false;
}

/// [seri] (zaman, fiyat; artan) içinden [gun]ün fiyatı: o gün ya da en çok
/// 7 gün öncesinin son fiyatı (hafta sonu, bayram). Yoksa `null`.
double? gunFiyati(List<(int, double)> seri, DateTime gun) {
  final gunSonu =
      DateTime(gun.year, gun.month, gun.day + 1).millisecondsSinceEpoch;
  final enEski =
      DateTime(gun.year, gun.month, gun.day - 7).millisecondsSinceEpoch;
  double? f;
  for (final (t, p) in seri) {
    if (t >= gunSonu) break;
    if (t >= enEski && p > 0) f = p;
  }
  return f;
}

/// Tutar ÷ fiyat → adet. Banka tutarı kuruşa yuvarlar; tam sayıya
/// yuvarlanmış adet tutarı kuruş içinde veriyorsa adet odur (TEFAS
/// yatırım fonu payı, hisse lotu tam sayıdır). Değilse 4 ondalık
/// (emeklilik fonu payı, gram altın, kripto kesirlidir).
double tutardanAdet(double tutar, double fiyat) {
  final q = tutar / fiyat;
  final tam = q.roundToDouble();
  final pay = tutar.abs() * 1e-6;
  if (tam > 0 && (tam * fiyat - tutar).abs() <= (pay > 0.02 ? pay : 0.02)) {
    return tam;
  }
  return (q * 10000).roundToDouble() / 10000;
}
