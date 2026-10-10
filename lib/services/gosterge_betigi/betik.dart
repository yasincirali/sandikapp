/// Kendi göstergeni yaz — Pine Script yorumlayıcısı (2026-10-10).
///
/// Kullanıcı isteği (yasin, 2026-10-10): *"traderlar TradingView'e kendi
/// kodlarını ekleyerek kendi generic göstergelerini kullanabiliyorlar …
/// paywall arkasına ekleyelim."* Aynı gün: *"direkt pine kodu verdirebiliyor
/// muyuz, benzeri değil de birebir olsun."* → İlk sürümdeki "Pine benzeri"
/// küçük dil bırakıldı; TradingView'den kopyalanan gösterge kodu OLDUĞU GİBİ
/// yapıştırılıp çalışsın diye Pine Script v4/v5/v6'nın gösterge alt kümesi
/// yazıldı.
///
/// ## Ne çalışır
/// `//@version=4/5/6`, `indicator()`/`study()`, `input.*`, `var`/`varip`,
/// tip bildirimleri (`float x = …`), `:=` ve `+=` gibi atamalar, `if/else`,
/// `for … to … by`, `while`, `switch`, `break/continue`, kullanıcı
/// fonksiyonları (`f(x) => …`, çok satırlı gövde, demet dönüşü `[a, b]`),
/// geçmiş operatörü `x[n]` (her ifadede), `ta.*` (sma, ema, rsi, macd, bb,
/// atr, stoch, supertrend, dmi, pivothigh, valuewhen …), `math.*`, `color.*`
/// (`color.new`, `#rrggbb`), `plot`, `hline`, `plotshape`, `plotchar`,
/// `plotarrow`, `fill`. v4'ün öneksiz adları (`sma`, `study`, `security`,
/// `iff`) da çalışır.
///
/// ## Bilerek çalışmayan (ve neden)
/// - `request.security` ile BAŞKA sembol/zaman aralığı: cihaz yalnız açık
///   grafiğin çubuklarını bilir; aynı sembol + aynı aralık çalışır.
/// - `array/matrix/map`, `type`, `method`, `import`/`library`: dili iki kat
///   büyütür, gösterge betiklerinin azı kullanır. Satırıyla söylenir.
/// - `label/line/box/table` çizim nesneleri, `bgcolor`, `barcolor`: kod
///   çalışır, bu çizimler GÖSTERİLMEZ ([BetikSonucu.notlar] söyler).
/// - `strategy()` betikleri gösterge gibi çalışır; emirler (`strategy.entry`
///   …) yürütülmez — uygulama işlem yapmaz.
///
/// ## Neden Python değil / neden kendi yorumlayıcımız
/// Cihazda Python yok (App Store 2.5.2: indirilen kod çalıştırılamaz;
/// yorumlayıcı gömmek ~30 MB ve dosya/ağ erişimini kapatmak bizim işimiz
/// olur). Sunucuda çalıştırmak her kullanıcının kodunu bizim makinemizde
/// koşturmak demek. TradingView de Pine'ı kendi kapalı yorumlayıcısında
/// çalıştırır; biz de öyle yapıyoruz.
///
/// ## Güvenlik modeli
/// - Dilde dosya, ağ, saat okuma, rastgelelik, başka varlık YOK — yazacak
///   sözdizimi bile yok; ayrıştırıcı ya da yorumlayıcı reddeder.
/// - Her düğüm değerlendirmesi ve her pencere adımı [_kIslemButcesi]'nden
///   düşer; sonsuz `while` bile bütçede durur. Fonksiyon özyinelemesi ve
///   iç içe çağrı derinliği sınırlı.
/// - Çıktı yalnız sayı dizisi + renk ADI; ekranda token renge çevrilir
///   (`#ff0000` en yakın tasarım rengine düşer — tasarım sistemi korunur).
///
/// ## Veri
/// Betik grafiğin O AN çizdiği çubuklar üzerinde, Pine gibi çubuk çubuk
/// çalışır. Açılış/yüksek/düşük/hacim gelmeyen seride bunlar `na`dır
/// (uydurma yok, CLAUDE.md "Fiyat kaynağı" madde 3); betik onları
/// kullanıyorsa [BetikSonucu.eksikVeri] söyler.
library;

import 'dart:math' as math;

part 'pine_sozcuk.dart';
part 'pine_agac.dart';
part 'pine_yorumlayici.dart';
part 'pine_ta.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sınırlar
// ─────────────────────────────────────────────────────────────────────────────

/// Kod en fazla bu kadar karakter (sunucuda da aynı kısıt, 0141).
/// TradingView'den gelen topluluk göstergeleri çoğunlukla 2-15 bin karakter.
const int kBetikAzamiKarakter = 20000;
const int _kAzamiSatir = 1500;
const int _kAzamiDerinlik = 64;

/// Pencere uzunluğu (`ta.sma(close, N)`) ve geçmiş indeksi (`x[N]`) üst
/// sınırı. Betik zaten en fazla [kBetikAzamiCubuk] çubuk görür.
const int kBetikAzamiUzunluk = 5000;

/// Betiğin işleyeceği en fazla çubuk (sondan).
const int kBetikAzamiCubuk = 5000;

/// Çizilen en fazla `plot`; fazlası atlanır ve not düşülür (betik kırılmaz).
const int kBetikAzamiCizgi = 16;
const int _kAzamiYatay = 8;
const int _kAzamiIsaret = 8;

/// Tek çalıştırmada yapılacak temel işlem sayısı üst sınırı.
const int _kIslemButcesi = 40 * 1000 * 1000;

/// İç içe kullanıcı fonksiyonu çağrısı derinliği.
const int _kAzamiCagriDerinligi = 24;

// ─────────────────────────────────────────────────────────────────────────────
// Dış yüz
// ─────────────────────────────────────────────────────────────────────────────

/// Kullanıcıya gösterilecek hata — satır/sütun ile.
class BetikHatasi implements Exception {
  const BetikHatasi(this.mesaj, this.mesajEn, {this.satir = 0, this.sutun = 0});
  final String mesaj;
  final String mesajEn;

  /// 1'den başlar; 0 = yere bağlı değil.
  final int satir;
  final int sutun;

  String metin(bool ingilizce) => ingilizce ? mesajEn : mesaj;

  @override
  String toString() => 'BetikHatasi($satir:$sutun) $mesaj';
}

/// Betiğin çalışacağı çubuklar. Bütün listeler aynı uzunlukta; bilinmeyen
/// değer `NaN`. [x] çizimin X'i (grafiğin ekseni); [zaman] çubuğun zamanı
/// (epoch ms, Pine'daki `time`) — verilmezse [x] zaman sayılır.
class BetikVerisi {
  BetikVerisi({
    required this.x,
    this.zaman,
    required this.acilis,
    required this.yuksek,
    required this.dusuk,
    required this.kapanis,
    required this.hacim,
    this.zamanDilimi = 'D',
    this.sembol = '',
  }) : assert(x.length == kapanis.length);

  /// Yalnız kapanış taşıyan seri (bugünkü çizgi verisi). Açılış/yüksek/
  /// düşük/hacim `na`.
  factory BetikVerisi.yalnizKapanis(
    List<double> x,
    List<double> kapanis, {
    List<double>? zaman,
    String zamanDilimi = 'D',
    String sembol = '',
  }) {
    final bos = List<double>.filled(kapanis.length, double.nan);
    return BetikVerisi(
      x: x,
      zaman: zaman,
      acilis: bos,
      yuksek: bos,
      dusuk: bos,
      kapanis: kapanis,
      hacim: bos,
      zamanDilimi: zamanDilimi,
      sembol: sembol,
    );
  }

  final List<double> x;
  final List<double>? zaman;
  List<double> get zamanlar => zaman ?? x;
  final List<double> acilis;
  final List<double> yuksek;
  final List<double> dusuk;
  final List<double> kapanis;
  final List<double> hacim;

  /// Pine `timeframe.period` biçiminde: '1', '60', '240', 'D', 'W', 'M'.
  final String zamanDilimi;

  /// `syminfo.ticker` (ör. 'THYAO').
  final String sembol;

  int get uzunluk => kapanis.length;

  /// Zaman damgalarının sıklığından Pine aralık dizisi ('5', '60', 'D',
  /// 'W', 'M'). Grafik verisi aralığı söylemiyor; çubuk arası ortanca süre
  /// yeterince kesin.
  static String aralikTahmini(List<double> zamanMs) {
    if (zamanMs.length < 3) return 'D';
    final farklar = [
      for (var i = 1; i < zamanMs.length; i++) zamanMs[i] - zamanMs[i - 1]
    ]..sort();
    final dk = farklar[farklar.length ~/ 2] / 60000;
    if (dk < 1) return '1';
    if (dk < 20 * 60) {
      const adimlar = [1, 3, 5, 15, 30, 60, 120, 240];
      return adimlar
          .reduce((a, b) => (a - dk).abs() <= (b - dk).abs() ? a : b)
          .toString();
    }
    if (dk < 5 * 1440) return 'D';
    if (dk < 20 * 1440) return 'W';
    return 'M';
  }

  bool get ohlcVar => yuksek.any((v) => !v.isNaN);
  bool get hacimVar => hacim.any((v) => !v.isNaN);

  BetikVerisi _sonN(int n) {
    if (uzunluk <= n) return this;
    List<double> k(List<double> l) => l.sublist(l.length - n);
    return BetikVerisi(
      x: k(x),
      zaman: zaman == null ? null : k(zaman!),
      acilis: k(acilis),
      yuksek: k(yuksek),
      dusuk: k(dusuk),
      kapanis: k(kapanis),
      hacim: k(hacim),
      zamanDilimi: zamanDilimi,
      sembol: sembol,
    );
  }
}

/// `plot.style_*` karşılığı. Pine'daki onlarca stil dört çizime iner.
enum BetikCizgiStili {
  /// line, linebr, stepline
  cizgi,

  /// histogram, columns — sıfırdan çubuk
  histogram,

  /// area, areabr — çizgi + altı dolu
  alan,

  /// circles, cross — yalnız nokta
  nokta,
}

/// `plot(...)` çıktısı. [renk] dilin renk adı (`yesil`, `kirmizi`, `mavi`,
/// `turuncu`, `sari`, `gri`, `mor`); null → ekran sıradaki rengi verir.
/// [eksiRenk]: histogramda sıfırın altındaki çubukların rengi (MACD
/// histogramı gibi iki renkli çizimler); null → [renk].
class BetikCizgi {
  const BetikCizgi(
    this.ad,
    this.degerler, {
    this.renk,
    this.eksiRenk,
    this.kalinlik = 1.6,
    this.stil = BetikCizgiStili.cizgi,
    this.gizli = false,
  });
  final String ad;
  final List<double> degerler;
  final String? renk;
  final String? eksiRenk;
  final double kalinlik;
  final BetikCizgiStili stil;

  /// Çizilmez, lejantta yazılmaz; yalnız `fill` için değer taşır (Pine'da
  /// `color.new(c, 100)` ya da `display=display.none` ile çizilen plot).
  final bool gizli;
}

/// `hline(...)` çıktısı — sabit seviye (ör. RSI 70/30).
class BetikYatay {
  const BetikYatay(this.ad, this.deger, {this.renk});
  final String ad;
  final double deger;
  final String? renk;
}

/// `plotshape` / `plotchar` / `plotarrow` çıktısı — koşulun doğru olduğu
/// çubuklar.
class BetikIsaret {
  const BetikIsaret(this.ad, this.indeksler, {this.renk});
  final String ad;
  final List<int> indeksler;
  final String? renk;
}

/// `fill(p1, p2)` — iki çizgi arası. [a]/[b] [BetikSonucu.cizgiler] indeksi.
/// İki yatay seviye arası (`fill(h1, h2)`) [yatayA]/[yatayB].
class BetikDolgu {
  const BetikDolgu({this.a, this.b, this.yatayA, this.yatayB, this.renk});
  final int? a;
  final int? b;
  final double? yatayA;
  final double? yatayB;
  final String? renk;
}

/// Kodun çalıştığı ama ekranda karşılığı olmayan kısımlar. Düzenleyici bunu
/// kısa bir notla söyler — sessizce yutulmaz.
enum BetikNotu {
  /// label/line/box/table/linefill/polyline
  cizimNesnesi,

  /// bgcolor, barcolor, plotcandle, plotbar
  boyama,

  /// strategy.entry/exit/close …
  strateji,

  /// [kBetikAzamiCizgi]'den fazla plot
  fazlaCizgi,

  /// Ayrı paneldeki plotshape (işaretler fiyatın üstüne konur)
  paneldeIsaret,
}

class BetikSonucu {
  const BetikSonucu({
    required this.x,
    required this.fiyatUstunde,
    required this.cizgiler,
    required this.yataylar,
    required this.isaretler,
    required this.eksikVeri,
    this.dolgular = const [],
    this.notlar = const {},
    this.baslik,
  });

  /// Çıktı dizilerinin X'leri (girdinin son [kBetikAzamiCubuk] çubuğu).
  final List<double> x;

  /// `indicator(overlay=...)`: true → fiyat grafiğinin üstüne, false →
  /// grafiğin altında ayrı panel.
  final bool fiyatUstunde;
  final String? baslik;
  final List<BetikCizgi> cizgiler;
  final List<BetikYatay> yataylar;
  final List<BetikIsaret> isaretler;
  final List<BetikDolgu> dolgular;

  /// Betiğin kullandığı ama bu seride gelmeyen veriler (`acilis`, `yuksek`,
  /// `dusuk`, `hacim`). Boş değilse ekran kısa bir not düşer.
  final Set<String> eksikVeri;

  final Set<BetikNotu> notlar;

  bool get bos =>
      cizgiler.every((c) => c.degerler.every((v) => v.isNaN)) &&
      isaretler.every((i) => i.indeksler.isEmpty) &&
      yataylar.isEmpty;
}

/// Derlenmiş betik — aynı kodu her zoom/pan'de yeniden ayrıştırmamak için.
class DerlenmisBetik {
  DerlenmisBetik._(this._program);

  final _Program _program;

  bool get fiyatUstunde => _program.fiyatUstunde;
  String? get baslik => _program.baslik;

  /// Çizgi sayısı (önizleme özeti için).
  int get cizgiSayisi => _program.cizgiSayisi;

  BetikSonucu calistir(BetikVerisi veri) =>
      _Yorumlayici(veri._sonN(kBetikAzamiCubuk), _program).calistir();
}

/// Dilin girişi.
abstract final class GostergeBetigi {
  /// Ayrıştırır ve durağan denetimleri yapar. Hata → [BetikHatasi].
  static DerlenmisBetik derle(String kod) {
    if (kod.length > kBetikAzamiKarakter) {
      throw const BetikHatasi(
        'Betik çok uzun (en fazla $kBetikAzamiKarakter karakter).',
        'Script is too long (max $kBetikAzamiKarakter characters).',
      );
    }
    final jetonlar = _Sozcukleyici(kod).hepsi();
    return DerlenmisBetik._(_Ayristirici(jetonlar).program());
  }

  /// Derle + çalıştır.
  static BetikSonucu calistir(String kod, BetikVerisi veri) =>
      derle(kod).calistir(veri);
}
