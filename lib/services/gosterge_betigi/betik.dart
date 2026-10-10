/// Kendi göstergeni yaz — kullanıcı betiği dili ve yorumlayıcısı (2026-10-10).
///
/// Kullanıcı isteği (yasin, 2026-10-10): *"traderlar TradingView'e kendi
/// kodlarını ekleyerek kendi generic göstergelerini kullanabiliyorlar; bu
/// grafiğin çizim frekansı ile kombine kullanılabilecek bir özellik. Paywall
/// arkasına ekleyelim."*
///
/// ## Neden Python değil
/// Cihazda Python yorumlayıcısı yok (App Store 2.5.2: indirilen kod
/// çalıştırılamaz; yorumlayıcı gömmek uygulamayı ~30 MB büyütür ve dosya/ağ
/// erişimini kapatmak bizim işimiz olur). Sunucuda çalıştırmak ise her
/// kullanıcının kodunu bizim makinemizde koşturmak demek: güvenlik yüzeyi,
/// maliyet ve her zoom'da ağ gecikmesi. Bunun yerine TradingView'in kendi
/// yaptığını yapıyoruz: Pine Script benzeri, KÜÇÜK ve KAPALI bir dil.
///
/// ## Güvenlik modeli (neden bu dil kaçamaz)
/// - Dil yalnız SAYI SERİSİ hesaplar. Döngü, `if` bloğu, fonksiyon tanımı,
///   dosya, ağ, saat, rastgelelik, başka varlıktan veri YOK — yazacak sözdizimi
///   bile yok; ayrıştırıcı reddeder.
/// - Her ifade bütün seri üstünde bir kez çalışır (vektörel); süre
///   `çubuk sayısı × ifade sayısı × pencere` ile sınırlı ve önceden bilinir.
///   Yine de [_kIslemButcesi] aşılırsa durur.
/// - Kod uzunluğu, satır, derinlik, çizgi sayısı ve pencere uzunluğu sınırlı.
/// - Çıktı yalnız sayı dizisi + sabit renk adı; ekranda token renge çevrilir
///   (ham renk kodu yazılamaz — tasarım sistemi korunur).
///
/// ## Veri
/// Betik grafiğin O AN çizdiği çubuklar üzerinde çalışır — TradingView'deki
/// gibi gösterge, seçili zaman aralığının (1 dk / 1 sa / 4 sa / gün / hafta /
/// ay) çubuklarıdır. Açılış/yüksek/düşük/hacim verisi gelmeyen seride bu
/// seriler `na`dır (uydurma yok, CLAUDE.md "Fiyat kaynağı" madde 3); betik
/// onları kullanıyorsa sonuç [BetikSonucu.eksikVeri]'de söylenir.
library;

import 'dart:math' as math;

// ─────────────────────────────────────────────────────────────────────────────
// Sınırlar
// ─────────────────────────────────────────────────────────────────────────────

/// Kod en fazla bu kadar karakter (sunucuda da aynı kısıt, 0141).
const int kBetikAzamiKarakter = 4000;
const int _kAzamiSatir = 200;
const int _kAzamiDerinlik = 48;

/// Pencere uzunluğu (sma(close, N) içindeki N) ve geçmiş indeksi ([N]) üst
/// sınırı. TradingView'de de pratikte 500'ü geçen ortalama nadirdir.
const int kBetikAzamiUzunluk = 500;

/// Betiğin işleyeceği en fazla çubuk (sondan). Gün içi 1 dk × birkaç gün
/// bile bunun altında kalır.
const int kBetikAzamiCubuk = 5000;

const int kBetikAzamiCizgi = 8;
const int _kAzamiYatay = 4;
const int _kAzamiIsaret = 2;

/// Tek çalıştırmada yapılacak temel işlem sayısı üst sınırı.
const int _kIslemButcesi = 30 * 1000 * 1000;

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
/// değer `NaN`.
class BetikVerisi {
  BetikVerisi({
    required this.x,
    required this.acilis,
    required this.yuksek,
    required this.dusuk,
    required this.kapanis,
    required this.hacim,
  }) : assert(x.length == kapanis.length);

  /// Yalnız kapanış taşıyan seri (bugünkü çizgi verisi). Açılış/yüksek/
  /// düşük/hacim `na`.
  factory BetikVerisi.yalnizKapanis(List<double> x, List<double> kapanis) {
    final bos = List<double>.filled(kapanis.length, double.nan);
    return BetikVerisi(
      x: x,
      acilis: bos,
      yuksek: bos,
      dusuk: bos,
      kapanis: kapanis,
      hacim: bos,
    );
  }

  final List<double> x;
  final List<double> acilis;
  final List<double> yuksek;
  final List<double> dusuk;
  final List<double> kapanis;
  final List<double> hacim;

  int get uzunluk => kapanis.length;

  bool get ohlcVar => yuksek.any((v) => !v.isNaN);
  bool get hacimVar => hacim.any((v) => !v.isNaN);

  BetikVerisi _sonN(int n) {
    if (uzunluk <= n) return this;
    List<double> k(List<double> l) => l.sublist(l.length - n);
    return BetikVerisi(
      x: k(x),
      acilis: k(acilis),
      yuksek: k(yuksek),
      dusuk: k(dusuk),
      kapanis: k(kapanis),
      hacim: k(hacim),
    );
  }
}

/// `plot(...)` çıktısı. [renk] dilin renk adı (`yesil`, `kirmizi`, `mavi`,
/// `turuncu`, `sari`, `gri`, `mor`); null → ekran sıradaki rengi verir.
class BetikCizgi {
  const BetikCizgi(this.ad, this.degerler, {this.renk, this.kalinlik = 1.6});
  final String ad;
  final List<double> degerler;
  final String? renk;
  final double kalinlik;
}

/// `hline(...)` çıktısı — ayrı panelde sabit seviye (ör. RSI 70/30).
class BetikYatay {
  const BetikYatay(this.ad, this.deger, {this.renk});
  final String ad;
  final double deger;
  final String? renk;
}

/// `plotshape(...)` çıktısı — koşulun doğru olduğu çubuklar.
class BetikIsaret {
  const BetikIsaret(this.ad, this.indeksler, {this.renk});
  final String ad;
  final List<int> indeksler;
  final String? renk;
}

class BetikSonucu {
  const BetikSonucu({
    required this.x,
    required this.fiyatUstunde,
    required this.cizgiler,
    required this.yataylar,
    required this.isaretler,
    required this.eksikVeri,
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

  /// Betiğin kullandığı ama bu seride gelmeyen veriler (`acilis`, `yuksek`,
  /// `dusuk`, `hacim`). Boş değilse ekran kısa bir not düşer.
  final Set<String> eksikVeri;

  bool get bos =>
      cizgiler.every((c) => c.degerler.every((v) => v.isNaN)) &&
      isaretler.every((i) => i.indeksler.isEmpty);
}

/// Derlenmiş betik — aynı kodu her zoom/pan'de yeniden ayrıştırmamak için.
class DerlenmisBetik {
  DerlenmisBetik._(this._ifadeler, this.fiyatUstunde, this.baslik);

  final List<_Deyim> _ifadeler;
  final bool fiyatUstunde;
  final String? baslik;

  /// Çizgi sayısı (önizleme özeti için).
  int get cizgiSayisi =>
      _ifadeler.where((d) => d is _Cikti && d.tur == _CiktiTuru.cizgi).length;

  BetikSonucu calistir(BetikVerisi veri) =>
      _Yorumlayici(veri._sonN(kBetikAzamiCubuk), this).calistir();
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
    return _Ayristirici(jetonlar).program();
  }

  /// Derle + çalıştır.
  static BetikSonucu calistir(String kod, BetikVerisi veri) =>
      derle(kod).calistir(veri);
}

// ─────────────────────────────────────────────────────────────────────────────
// Sözcükleyici
// ─────────────────────────────────────────────────────────────────────────────

enum _J { sayi, ad, metin, isaret, satirSonu, son }

class _Jeton {
  const _Jeton(this.tur, this.deger, this.satir, this.sutun);
  final _J tur;
  final String deger;
  final int satir;
  final int sutun;
}

BetikHatasi _hata(String tr, String en, [_Jeton? j]) =>
    BetikHatasi(tr, en, satir: j?.satir ?? 0, sutun: j?.sutun ?? 0);

class _Sozcukleyici {
  _Sozcukleyici(this.kod);
  final String kod;
  int _i = 0;
  int _satir = 1;
  int _satirBasi = 0;
  int _parantez = 0;

  static final _harf = RegExp(r'[A-Za-z_çğıöşüÇĞİÖŞÜ]');
  static final _harfRakam = RegExp(r'[A-Za-z0-9_çğıöşüÇĞİÖŞÜ]');
  static const _ikili = {'==', '!=', '<=', '>=', '&&', '||', ':='};
  static const _tekli = '+-*/%()[],=<>?:!.;';

  List<_Jeton> hepsi() {
    final out = <_Jeton>[];
    while (_i < kod.length) {
      final c = kod[_i];
      final sutun = _i - _satirBasi + 1;
      if (c == '\n') {
        if (_parantez == 0) {
          out.add(_Jeton(_J.satirSonu, '\n', _satir, sutun));
        }
        _i++;
        _satir++;
        _satirBasi = _i;
        if (_satir > _kAzamiSatir) {
          throw const BetikHatasi('Betik en fazla $_kAzamiSatir satır olabilir.',
              'Script can have at most $_kAzamiSatir lines.');
        }
        continue;
      }
      if (c == ' ' || c == '\t' || c == '\r') {
        _i++;
        continue;
      }
      if (c == '/' && _i + 1 < kod.length && kod[_i + 1] == '/') {
        while (_i < kod.length && kod[_i] != '\n') {
          _i++;
        }
        continue;
      }
      if (_rakam(c) || (c == '.' && _i + 1 < kod.length && _rakam(kod[_i + 1]))) {
        final b = _i;
        while (_i < kod.length && (_rakam(kod[_i]) || kod[_i] == '.')) {
          _i++;
        }
        out.add(_Jeton(_J.sayi, kod.substring(b, _i), _satir, sutun));
        continue;
      }
      if (_harf.hasMatch(c)) {
        final b = _i;
        while (_i < kod.length && _harfRakam.hasMatch(kod[_i])) {
          _i++;
        }
        out.add(_Jeton(_J.ad, kod.substring(b, _i), _satir, sutun));
        continue;
      }
      if (c == '"' || c == "'") {
        final b = ++_i;
        while (_i < kod.length && kod[_i] != c && kod[_i] != '\n') {
          _i++;
        }
        if (_i >= kod.length || kod[_i] != c) {
          throw BetikHatasi('Tırnak kapanmamış.', 'Unterminated string.',
              satir: _satir, sutun: sutun);
        }
        out.add(_Jeton(_J.metin, kod.substring(b, _i), _satir, sutun));
        _i++;
        continue;
      }
      if (_i + 1 < kod.length && _ikili.contains(kod.substring(_i, _i + 2))) {
        out.add(_Jeton(_J.isaret, kod.substring(_i, _i + 2), _satir, sutun));
        _i += 2;
        continue;
      }
      if (_tekli.contains(c)) {
        if (c == '(' || c == '[') _parantez++;
        if ((c == ')' || c == ']') && _parantez > 0) _parantez--;
        out.add(c == ';'
            ? _Jeton(_J.satirSonu, ';', _satir, sutun)
            : _Jeton(_J.isaret, c, _satir, sutun));
        _i++;
        continue;
      }
      throw BetikHatasi("Tanınmayan karakter: '$c'", "Unknown character: '$c'",
          satir: _satir, sutun: sutun);
    }
    out.add(_Jeton(_J.satirSonu, '\n', _satir, 1));
    out.add(_Jeton(_J.son, '', _satir, 1));
    return out;
  }

  static bool _rakam(String c) {
    final k = c.codeUnitAt(0);
    return k >= 48 && k <= 57;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sözdizimi ağacı
// ─────────────────────────────────────────────────────────────────────────────

sealed class _Ifade {
  const _Ifade(this.j);
  final _Jeton j;
}

class _SayiI extends _Ifade {
  const _SayiI(super.j, this.v);
  final double v;
}

class _MetinI extends _Ifade {
  const _MetinI(super.j, this.v);
  final String v;
}

class _RenkI extends _Ifade {
  const _RenkI(super.j, this.ad);
  final String ad;
}

class _AdI extends _Ifade {
  const _AdI(super.j, this.ad);
  final String ad;
}

class _TekliI extends _Ifade {
  const _TekliI(super.j, this.op, this.e);
  final String op;
  final _Ifade e;
}

class _IkiliI extends _Ifade {
  const _IkiliI(super.j, this.op, this.a, this.b);
  final String op;
  final _Ifade a;
  final _Ifade b;
}

class _KosulI extends _Ifade {
  const _KosulI(super.j, this.k, this.a, this.b);
  final _Ifade k;
  final _Ifade a;
  final _Ifade b;
}

class _IndeksI extends _Ifade {
  const _IndeksI(super.j, this.e, this.n);
  final _Ifade e;
  final _Ifade n;
}

class _CagriI extends _Ifade {
  const _CagriI(super.j, this.ad, this.arg, this.adli);
  final String ad;
  final List<_Ifade> arg;
  final Map<String, _Ifade> adli;
}

sealed class _Deyim {
  const _Deyim();
}

class _Atama extends _Deyim {
  const _Atama(this.ad, this.e);
  final String ad;
  final _Ifade e;
}

enum _CiktiTuru { cizgi, yatay, isaret }

class _Cikti extends _Deyim {
  const _Cikti(this.tur, this.cagri);
  final _CiktiTuru tur;
  final _CagriI cagri;
}

// ─────────────────────────────────────────────────────────────────────────────
// Adlar: yerleşik seriler, fonksiyonlar, renkler (Türkçe takma adlarla)
// ─────────────────────────────────────────────────────────────────────────────

/// Yerleşik seriler → kanonik ad.
const Map<String, String> _seriAdlari = {
  'open': 'open', 'acilis': 'open', 'açılış': 'open',
  'high': 'high', 'yuksek': 'high', 'yüksek': 'high',
  'low': 'low', 'dusuk': 'low', 'düşük': 'low',
  'close': 'close', 'kapanis': 'close', 'kapanış': 'close',
  'volume': 'volume', 'hacim': 'volume',
  'hl2': 'hl2', 'hlc3': 'hlc3', 'ohlc4': 'ohlc4',
  'bar_index': 'bar_index', 'cubuk': 'bar_index',
  'tr': 'tr',
};

/// Fonksiyon takma adları → kanonik ad. `ta.` ve `math.` önekleri atılır.
const Map<String, String> _fonksiyonAdlari = {
  'sma': 'sma', 'ema': 'ema', 'wma': 'wma', 'rma': 'rma', 'vwma': 'vwma',
  'rsi': 'rsi', 'stdev': 'stdev', 'highest': 'highest', 'lowest': 'lowest',
  'enyuksek': 'highest', 'endusuk': 'lowest',
  'change': 'change', 'degisim': 'change', 'mom': 'mom', 'roc': 'roc',
  'crossover': 'crossover', 'yukarikesti': 'crossover',
  'crossunder': 'crossunder', 'asagikesti': 'crossunder',
  'cross': 'cross', 'kesti': 'cross',
  'atr': 'atr', 'sum': 'sum', 'toplam': 'sum', 'cum': 'cum',
  'abs': 'abs', 'sqrt': 'sqrt', 'log': 'log', 'log10': 'log10',
  'exp': 'exp', 'pow': 'pow', 'round': 'round', 'floor': 'floor',
  'ceil': 'ceil', 'sign': 'sign', 'max': 'max', 'min': 'min', 'avg': 'avg',
  'nz': 'nz', 'na': 'na',
};

/// Çıktı fonksiyonları (yalnız satır başında).
const Map<String, _CiktiTuru?> _ciktiAdlari = {
  'plot': _CiktiTuru.cizgi, 'ciz': _CiktiTuru.cizgi, 'çiz': _CiktiTuru.cizgi,
  'hline': _CiktiTuru.yatay, 'yatay': _CiktiTuru.yatay,
  'plotshape': _CiktiTuru.isaret, 'isaret': _CiktiTuru.isaret,
  'işaret': _CiktiTuru.isaret,
  'indicator': null, 'study': null, 'gosterge': null, 'gösterge': null,
};

/// Renk adları → dilin kanonik rengi (ekranda tasarım token'ına çevrilir).
const Map<String, String> kBetikRenkleri = {
  'green': 'yesil', 'yesil': 'yesil', 'yeşil': 'yesil', 'lime': 'yesil',
  'red': 'kirmizi', 'kirmizi': 'kirmizi', 'kırmızı': 'kirmizi',
  'maroon': 'kirmizi',
  'blue': 'mavi', 'mavi': 'mavi', 'aqua': 'mavi', 'teal': 'mavi',
  'navy': 'mavi',
  'orange': 'turuncu', 'turuncu': 'turuncu', 'amber': 'turuncu',
  'yellow': 'sari', 'sari': 'sari', 'sarı': 'sari', 'gold': 'sari',
  'altin': 'sari',
  'gray': 'gri', 'grey': 'gri', 'gri': 'gri', 'silver': 'gri',
  'white': 'gri', 'black': 'gri',
  'purple': 'mor', 'mor': 'mor', 'fuchsia': 'mor',
};

/// Dilde OLMAYAN ve kullanıcının Pine/Python'dan getirebileceği sözcükler —
/// neden olmadığını söyleyen mesajla.
const Map<String, (String, String)> _yasakSozcukler = {
  'for': ('Döngü yok: her ifade zaten bütün çubuklarda çalışır.',
      'No loops: every expression already runs over all bars.'),
  'while': ('Döngü yok: her ifade zaten bütün çubuklarda çalışır.',
      'No loops: every expression already runs over all bars.'),
  'if': ("'if' yok; koşul için  a ? b : c  yaz.",
      "No 'if'; write  a ? b : c  instead."),
  'import': ('Kütüphane eklenemez; yerleşik fonksiyonları kullan.',
      'Imports are not available; use the built-in functions.'),
  'request': ('Başka varlıktan ya da zaman aralığından veri çekilemez.',
      'Cannot fetch other symbols or timeframes.'),
  'security': ('Başka varlıktan ya da zaman aralığından veri çekilemez.',
      'Cannot fetch other symbols or timeframes.'),
  'var': ("'var' yok; değişkeni  ad = ifade  ile tanımla.",
      "No 'var'; define with  name = expression."),
  'def': ('Fonksiyon tanımlanamaz.', 'Functions cannot be defined.'),
  'function': ('Fonksiyon tanımlanamaz.', 'Functions cannot be defined.'),
  'strategy': ('Strateji/emir yok; yalnız gösterge çizilir.',
      'No strategies/orders; indicators only.'),
};

/// Yakın adı bul (öneri için) — küçük Levenshtein.
String? _yakinAd(String ad) {
  final adaylar = {
    ..._seriAdlari.keys,
    ..._fonksiyonAdlari.keys,
    ..._ciktiAdlari.keys,
  };
  String? en;
  var enIyi = 3;
  for (final a in adaylar) {
    final d = _mesafe(ad.toLowerCase(), a);
    if (d < enIyi) {
      enIyi = d;
      en = a;
    }
  }
  return en;
}

int _mesafe(String a, String b) {
  if ((a.length - b.length).abs() > 2) return 99;
  var onceki = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final simdi = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      simdi[j] = [
        onceki[j] + 1,
        simdi[j - 1] + 1,
        onceki[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      ].reduce(math.min);
    }
    onceki = simdi;
  }
  return onceki[b.length];
}

// ─────────────────────────────────────────────────────────────────────────────
// Ayrıştırıcı
// ─────────────────────────────────────────────────────────────────────────────

class _Ayristirici {
  _Ayristirici(this._j);
  final List<_Jeton> _j;
  int _p = 0;
  int _derinlik = 0;
  final Set<String> _tanimli = {};

  _Jeton get _su => _j[_p];
  _Jeton _al() => _j[_p++];
  bool _isaretMi(String s) => _su.tur == _J.isaret && _su.deger == s;
  bool _adMi(String s) => _su.tur == _J.ad && _su.deger == s;

  void _bekle(String s) {
    if (!_isaretMi(s)) {
      throw _hata("'$s' bekleniyordu.", "Expected '$s'.", _su);
    }
    _p++;
  }

  DerlenmisBetik program() {
    final deyimler = <_Deyim>[];
    var fiyatUstunde = true;
    String? baslik;
    var cizgi = 0, yatay = 0, isaret = 0;
    var gostergeGoruldu = false;
    while (_su.tur != _J.son) {
      if (_su.tur == _J.satirSonu) {
        _p++;
        continue;
      }
      final bas = _su;
      if (bas.tur == _J.ad && _yasakSozcukler.containsKey(bas.deger)) {
        final m = _yasakSozcukler[bas.deger]!;
        throw _hata(m.$1, m.$2, bas);
      }
      // Atama: ad = ifade
      if (bas.tur == _J.ad &&
          _j[_p + 1].tur == _J.isaret &&
          (_j[_p + 1].deger == '=' || _j[_p + 1].deger == ':=')) {
        final ad = bas.deger;
        if (_j[_p + 1].deger == ':=') {
          throw _hata(
              "':=' (yeniden atama) yok; yeni bir ad kullan.",
              "':=' (reassignment) is not supported; use a new name.",
              _j[_p + 1]);
        }
        if (_seriAdlari.containsKey(ad) ||
            _fonksiyonAdlari.containsKey(ad) ||
            _ciktiAdlari.containsKey(ad) ||
            ad == 'true' ||
            ad == 'false') {
          throw _hata("'$ad' yerleşik bir ad; başka bir ad seç.",
              "'$ad' is a built-in name; pick another.", bas);
        }
        if (_tanimli.contains(ad)) {
          throw _hata("'$ad' zaten tanımlı; yeni bir ad kullan.",
              "'$ad' is already defined; use a new name.", bas);
        }
        _p += 2;
        final e = _ifade();
        _tanimli.add(ad);
        deyimler.add(_Atama(ad, e));
      } else {
        final e = _ifade();
        if (e is! _CagriI || !_ciktiAdlari.containsKey(e.ad)) {
          throw _hata(
              'Bu satır bir şey yapmıyor. Çizmek için plot(...) kullan.',
              'This line does nothing. Use plot(...) to draw.',
              bas);
        }
        final tur = _ciktiAdlari[e.ad];
        if (tur == null) {
          if (gostergeGoruldu) {
            throw _hata('indicator(...) bir kez yazılır.',
                'indicator(...) may appear only once.', bas);
          }
          gostergeGoruldu = true;
          final g = _gostergeAyari(e);
          fiyatUstunde = g.$1;
          baslik = g.$2;
        } else {
          switch (tur) {
            case _CiktiTuru.cizgi:
              cizgi++;
            case _CiktiTuru.yatay:
              yatay++;
            case _CiktiTuru.isaret:
              isaret++;
          }
          if (cizgi > kBetikAzamiCizgi) {
            throw _hata('En fazla $kBetikAzamiCizgi çizgi çizilebilir.',
                'At most $kBetikAzamiCizgi plots.', bas);
          }
          if (yatay > _kAzamiYatay) {
            throw _hata('En fazla $_kAzamiYatay yatay çizgi.',
                'At most $_kAzamiYatay hlines.', bas);
          }
          if (isaret > _kAzamiIsaret) {
            throw _hata('En fazla $_kAzamiIsaret işaret serisi.',
                'At most $_kAzamiIsaret plotshapes.', bas);
          }
          deyimler.add(_Cikti(tur, e));
        }
      }
      if (_su.tur != _J.satirSonu && _su.tur != _J.son) {
        throw _hata('Satır sonu bekleniyordu.', 'Expected end of line.', _su);
      }
    }
    if (cizgi + yatay + isaret == 0) {
      throw const BetikHatasi(
          'Çizilecek bir şey yok. Sonuna plot(...) ekle.',
          'Nothing to draw. Add plot(...) at the end.');
    }
    if (!fiyatUstunde && isaret > 0) {
      // İşaretler fiyatın üstüne konur; ayrı panelde anlamı yok.
      throw const BetikHatasi(
          'plotshape yalnız fiyatın üstündeki göstergede (overlay=true).',
          'plotshape only works with overlay=true.');
    }
    return DerlenmisBetik._(deyimler, fiyatUstunde, baslik);
  }

  (bool, String?) _gostergeAyari(_CagriI c) {
    var ust = true;
    String? baslik;
    if (c.arg.isNotEmpty) {
      final a = c.arg.first;
      if (a is! _MetinI) {
        throw _hata('indicator ilk değeri bir ad olmalı: "Adım".',
            'indicator first argument must be a title: "Name".', a.j);
      }
      baslik = a.v;
    }
    if (c.arg.length > 1) {
      ust = _mantiksalSabit(c.arg[1]);
    }
    for (final e in c.adli.entries) {
      switch (e.key) {
        case 'overlay' || 'ustte' || 'üstte':
          ust = _mantiksalSabit(e.value);
        case 'title' || 'shorttitle' || 'ad':
          if (e.value is _MetinI) baslik = (e.value as _MetinI).v;
        default:
          throw _hata("indicator içinde bilinmeyen ayar: '${e.key}'",
              "Unknown indicator option: '${e.key}'", e.value.j);
      }
    }
    return (ust, baslik);
  }

  bool _mantiksalSabit(_Ifade e) {
    if (e is _AdI && (e.ad == 'true' || e.ad == 'false')) {
      return e.ad == 'true';
    }
    throw _hata('Burada true ya da false yazılmalı.',
        'Expected true or false here.', e.j);
  }

  _Ifade _ifade() {
    if (++_derinlik > _kAzamiDerinlik) {
      throw _hata('İfade çok iç içe.', 'Expression is nested too deeply.', _su);
    }
    try {
      return _kosul();
    } finally {
      _derinlik--;
    }
  }

  _Ifade _kosul() {
    final k = _veya();
    if (_isaretMi('?')) {
      final j = _al();
      final a = _ifade();
      _bekle(':');
      final b = _ifade();
      return _KosulI(j, k, a, b);
    }
    return k;
  }

  _Ifade _veya() {
    var a = _ve();
    while (_adMi('or') || _isaretMi('||') || _adMi('veya')) {
      final j = _al();
      a = _IkiliI(j, 'or', a, _ve());
    }
    return a;
  }

  _Ifade _ve() {
    var a = _degil();
    while (_adMi('and') || _isaretMi('&&') || _adMi('ve')) {
      final j = _al();
      a = _IkiliI(j, 'and', a, _degil());
    }
    return a;
  }

  _Ifade _degil() {
    if (_adMi('not') || _isaretMi('!') || _adMi('degil')) {
      final j = _al();
      return _TekliI(j, 'not', _degil());
    }
    return _karsilastir();
  }

  _Ifade _karsilastir() {
    final a = _topla();
    for (final op in const ['==', '!=', '<=', '>=', '<', '>']) {
      if (_isaretMi(op)) {
        final j = _al();
        return _IkiliI(j, op, a, _topla());
      }
    }
    return a;
  }

  _Ifade _topla() {
    var a = _carp();
    while (_isaretMi('+') || _isaretMi('-')) {
      final j = _al();
      a = _IkiliI(j, j.deger, a, _carp());
    }
    return a;
  }

  _Ifade _carp() {
    var a = _tekli();
    while (_isaretMi('*') || _isaretMi('/') || _isaretMi('%')) {
      final j = _al();
      a = _IkiliI(j, j.deger, a, _tekli());
    }
    return a;
  }

  _Ifade _tekli() {
    if (_isaretMi('-') || _isaretMi('+')) {
      final j = _al();
      if (++_derinlik > _kAzamiDerinlik) {
        throw _hata('İfade çok iç içe.', 'Expression is nested too deeply.', j);
      }
      try {
        final e = _tekli();
        return j.deger == '-' ? _TekliI(j, '-', e) : e;
      } finally {
        _derinlik--;
      }
    }
    var e = _birincil();
    while (_isaretMi('[')) {
      final j = _al();
      final n = _ifade();
      _bekle(']');
      e = _IndeksI(j, e, n);
    }
    return e;
  }

  _Ifade _birincil() {
    final j = _su;
    switch (j.tur) {
      case _J.sayi:
        _p++;
        final v = double.tryParse(j.deger);
        if (v == null) {
          throw _hata("Geçersiz sayı: '${j.deger}' (ondalık için nokta kullan).",
              "Invalid number: '${j.deger}' (use a dot for decimals).", j);
        }
        return _SayiI(j, v);
      case _J.metin:
        _p++;
        return _MetinI(j, j.deger);
      case _J.ad:
        return _adVeyaCagri();
      case _J.isaret when j.deger == '(':
        _p++;
        final e = _ifade();
        _bekle(')');
        return e;
      default:
        throw _hata(
            j.tur == _J.satirSonu || j.tur == _J.son
                ? 'Satır yarım kaldı.'
                : "Burada '${j.deger}' beklenmiyordu.",
            j.tur == _J.satirSonu || j.tur == _J.son
                ? 'Line is incomplete.'
                : "Unexpected '${j.deger}'.",
            j);
    }
  }

  _Ifade _adVeyaCagri() {
    final j = _al();
    if (_yasakSozcukler.containsKey(j.deger)) {
      final m = _yasakSozcukler[j.deger]!;
      throw _hata(m.$1, m.$2, j);
    }
    var ad = j.deger;
    // Noktalı ad: ta.sma, math.max, color.green
    while (_isaretMi('.')) {
      _p++;
      if (_su.tur != _J.ad) {
        throw _hata("'.' sonrası bir ad bekleniyordu.",
            "Expected a name after '.'.", _su);
      }
      ad = '$ad.${_al().deger}';
    }
    final parcalar = ad.split('.');
    if (parcalar.length == 2 &&
        (parcalar[0] == 'color' || parcalar[0] == 'renk')) {
      final r = kBetikRenkleri[parcalar[1]];
      if (r == null) {
        throw _hata("Bilinmeyen renk: '${parcalar[1]}'",
            "Unknown color: '${parcalar[1]}'", j);
      }
      return _RenkI(j, r);
    }
    if (parcalar.length == 2 &&
        (parcalar[0] == 'ta' || parcalar[0] == 'math')) {
      ad = parcalar[1];
    } else if (parcalar.length > 1) {
      throw _hata("Bilinmeyen ad: '$ad'", "Unknown name: '$ad'", j);
    }
    if (_isaretMi('(')) {
      _p++;
      final arg = <_Ifade>[];
      final adli = <String, _Ifade>{};
      if (!_isaretMi(')')) {
        while (true) {
          if (_su.tur == _J.ad &&
              _j[_p + 1].tur == _J.isaret &&
              _j[_p + 1].deger == '=') {
            final anahtar = _al().deger;
            _p++;
            adli[anahtar] = _ifade();
          } else {
            if (adli.isNotEmpty) {
              throw _hata('Adlı değerlerden sonra sıralı değer yazılamaz.',
                  'Positional argument after named argument.', _su);
            }
            arg.add(_ifade());
          }
          if (_isaretMi(',')) {
            _p++;
            continue;
          }
          break;
        }
      }
      _bekle(')');
      if (!_fonksiyonAdlari.containsKey(ad) && !_ciktiAdlari.containsKey(ad)) {
        final oneri = _yakinAd(ad);
        throw _hata(
            "Bilinmeyen fonksiyon: '$ad'${oneri != null ? " — '$oneri' mi demek istedin?" : ''}",
            "Unknown function: '$ad'${oneri != null ? " — did you mean '$oneri'?" : ''}",
            j);
      }
      return _CagriI(j, ad, arg, adli);
    }
    if (ad == 'true' || ad == 'false' || ad == 'na') return _AdI(j, ad);
    if (_seriAdlari.containsKey(ad) || _tanimli.contains(ad)) {
      return _AdI(j, ad);
    }
    if (_fonksiyonAdlari.containsKey(ad) && ad != 'tr') {
      throw _hata("'$ad' bir fonksiyon; parantezle çağır: $ad(...)",
          "'$ad' is a function; call it: $ad(...)", j);
    }
    final oneri = _yakinAd(ad);
    throw _hata(
        "Tanımsız ad: '$ad'${oneri != null ? " — '$oneri' mi demek istedin?" : ''}",
        "Undefined name: '$ad'${oneri != null ? " — did you mean '$oneri'?" : ''}",
        j);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Yorumlayıcı (vektörel)
// ─────────────────────────────────────────────────────────────────────────────

sealed class _D {
  const _D();
}

class _Seri extends _D {
  const _Seri(this.v);
  final List<double> v;
}

class _Sabit extends _D {
  const _Sabit(this.v);
  final double v;
}

class _Metin extends _D {
  const _Metin(this.v);
  final String v;
}

class _Renk extends _D {
  const _Renk(this.ad);
  final String ad;
}

class _Yorumlayici {
  _Yorumlayici(this.veri, this.betik) : n = veri.uzunluk;
  final BetikVerisi veri;
  final DerlenmisBetik betik;
  final int n;
  final Map<String, _D> _degisken = {};
  final Set<String> _eksik = {};
  int _islem = 0;

  void _harca(int k, _Jeton j) {
    _islem += k;
    if (_islem > _kIslemButcesi) {
      throw _hata('Betik çok ağır; pencere uzunluklarını küçült.',
          'Script is too heavy; use shorter lengths.', j);
    }
  }

  BetikSonucu calistir() {
    final cizgiler = <BetikCizgi>[];
    final yataylar = <BetikYatay>[];
    final isaretler = <BetikIsaret>[];
    for (final d in betik._ifadeler) {
      switch (d) {
        case _Atama():
          _degisken[d.ad] = _deger(d.e);
        case _Cikti():
          final c = d.cagri;
          final ayar = _ciktiAyari(c);
          switch (d.tur) {
            case _CiktiTuru.cizgi:
              final s = _seriYap(_sayisal(c.arg.first), c.j);
              cizgiler.add(BetikCizgi(
                ayar.ad ?? 'Çizgi ${cizgiler.length + 1}',
                s,
                renk: ayar.renk,
                kalinlik: ayar.kalinlik,
              ));
            case _CiktiTuru.yatay:
              final v = _sayisal(c.arg.first);
              if (v is! _Sabit) {
                throw _hata('hline sabit bir sayı ister (ör. hline(70)).',
                    'hline needs a constant (e.g. hline(70)).', c.j);
              }
              yataylar.add(BetikYatay(ayar.ad ?? '', v.v, renk: ayar.renk));
            case _CiktiTuru.isaret:
              final s = _seriYap(_sayisal(c.arg.first), c.j);
              isaretler.add(BetikIsaret(
                ayar.ad ?? 'İşaret ${isaretler.length + 1}',
                [
                  for (var i = 0; i < n; i++)
                    if (_dogru(s[i])) i
                ],
                renk: ayar.renk,
              ));
          }
      }
    }
    return BetikSonucu(
      x: veri.x,
      fiyatUstunde: betik.fiyatUstunde,
      baslik: betik.baslik,
      cizgiler: cizgiler,
      yataylar: yataylar,
      isaretler: isaretler,
      eksikVeri: _eksik,
    );
  }

  ({String? ad, String? renk, double kalinlik}) _ciktiAyari(_CagriI c) {
    if (c.arg.isEmpty) {
      throw _hata('${c.ad}(...) içine çizilecek değeri yaz.',
          'Put the value to draw inside ${c.ad}(...).', c.j);
    }
    String? ad;
    String? renk;
    var kalinlik = 1.6;
    void metin(_Ifade e) {
      final d = _deger(e);
      if (d is! _Metin) {
        throw _hata('Başlık tırnak içinde yazılır: "Ad".',
            'Title must be quoted: "Name".', e.j);
      }
      ad = d.v;
    }

    void renkAl(_Ifade e) {
      final d = _deger(e);
      if (d is! _Renk) {
        throw _hata('Renk color.green gibi yazılır.',
            'Color is written like color.green.', e.j);
      }
      renk = d.ad;
    }

    if (c.arg.length > 1) metin(c.arg[1]);
    if (c.arg.length > 2) renkAl(c.arg[2]);
    if (c.arg.length > 3) {
      throw _hata('${c.ad} için fazla değer.', 'Too many values for ${c.ad}.',
          c.arg[3].j);
    }
    for (final e in c.adli.entries) {
      switch (e.key) {
        case 'title' || 'ad' || 'baslik':
          metin(e.value);
        case 'color' || 'renk':
          renkAl(e.value);
        case 'linewidth' || 'kalinlik':
          final d = _deger(e.value);
          if (d is! _Sabit || d.v < 1 || d.v > 4) {
            throw _hata('linewidth 1 ile 4 arasında bir sayı.',
                'linewidth must be 1 to 4.', e.value.j);
          }
          kalinlik = 1.2 + (d.v - 1) * 0.6;
        // Pine uyumluluğu: anlamı bizde sabit olan ayarlar yok sayılır.
        case 'style' || 'location' || 'size' || 'linestyle' || 'text':
          break;
        default:
          throw _hata("${c.ad} içinde bilinmeyen ayar: '${e.key}'",
              "Unknown ${c.ad} option: '${e.key}'", e.value.j);
      }
    }
    return (ad: ad, renk: renk, kalinlik: kalinlik);
  }

  // ── Değerler ──────────────────────────────────────────────────────────────

  static bool _dogru(double v) => !v.isNaN && v != 0;

  List<double> _seriYap(_D d, _Jeton j) {
    switch (d) {
      case _Seri():
        return d.v;
      case _Sabit():
        return List<double>.filled(n, d.v);
      default:
        throw _hata('Burada sayı ya da seri bekleniyordu.',
            'Expected a number or series here.', j);
    }
  }

  _D _sayisal(_Ifade e) {
    final d = _deger(e);
    if (d is _Metin || d is _Renk) {
      throw _hata('Burada sayı ya da seri bekleniyordu.',
          'Expected a number or series here.', e.j);
    }
    return d;
  }

  List<double> _yerlesik(String kanonik, _Jeton j) {
    List<double> eksikse(String ad, List<double> l, bool var_) {
      if (!var_) _eksik.add(ad);
      return l;
    }

    final ohlc = veri.ohlcVar;
    switch (kanonik) {
      case 'open':
        return eksikse('acilis', veri.acilis, ohlc);
      case 'high':
        return eksikse('yuksek', veri.yuksek, ohlc);
      case 'low':
        return eksikse('dusuk', veri.dusuk, ohlc);
      case 'close':
        return veri.kapanis;
      case 'volume':
        return eksikse('hacim', veri.hacim, veri.hacimVar);
      case 'hl2':
        return eksikse('yuksek',
            [for (var i = 0; i < n; i++) (veri.yuksek[i] + veri.dusuk[i]) / 2],
            ohlc);
      case 'hlc3':
        return eksikse(
            'yuksek',
            [
              for (var i = 0; i < n; i++)
                (veri.yuksek[i] + veri.dusuk[i] + veri.kapanis[i]) / 3
            ],
            ohlc);
      case 'ohlc4':
        return eksikse(
            'yuksek',
            [
              for (var i = 0; i < n; i++)
                (veri.acilis[i] +
                        veri.yuksek[i] +
                        veri.dusuk[i] +
                        veri.kapanis[i]) /
                    4
            ],
            ohlc);
      case 'bar_index':
        return [for (var i = 0; i < n; i++) i.toDouble()];
      case 'tr':
        return eksikse('yuksek', _gercekAralik(), ohlc);
    }
    throw _hata("Tanımsız ad: '$kanonik'", "Undefined name: '$kanonik'", j);
  }

  List<double> _gercekAralik() => [
        for (var i = 0; i < n; i++)
          i == 0
              ? veri.yuksek[i] - veri.dusuk[i]
              : [
                  veri.yuksek[i] - veri.dusuk[i],
                  (veri.yuksek[i] - veri.kapanis[i - 1]).abs(),
                  (veri.dusuk[i] - veri.kapanis[i - 1]).abs(),
                ].reduce(math.max)
      ];

  _D _deger(_Ifade e) {
    switch (e) {
      case _SayiI():
        return _Sabit(e.v);
      case _MetinI():
        return _Metin(e.v);
      case _RenkI():
        return _Renk(e.ad);
      case _AdI():
        if (e.ad == 'true') return const _Sabit(1);
        if (e.ad == 'false') return const _Sabit(0);
        if (e.ad == 'na') return const _Sabit(double.nan);
        final d = _degisken[e.ad];
        if (d != null) return d;
        final k = _seriAdlari[e.ad];
        if (k != null) {
          _harca(n, e.j);
          return _Seri(_yerlesik(k, e.j));
        }
        throw _hata("Tanımsız ad: '${e.ad}'", "Undefined name: '${e.ad}'", e.j);
      case _TekliI():
        final d = _sayisal(e.e);
        double f(double v) => e.op == '-' ? -v : (_dogru(v) ? 0 : 1);
        if (d is _Sabit) return _Sabit(f(d.v));
        _harca(n, e.j);
        return _Seri([for (final v in (d as _Seri).v) f(v)]);
      case _IkiliI():
        return _ikili(e);
      case _KosulI():
        final k = _sayisal(e.k);
        final a = _sayisal(e.a);
        final b = _sayisal(e.b);
        if (k is _Sabit) return _dogru(k.v) ? a : b;
        _harca(n, e.j);
        final ks = (k as _Seri).v;
        final as_ = _seriYap(a, e.a.j);
        final bs = _seriYap(b, e.b.j);
        return _Seri([for (var i = 0; i < n; i++) _dogru(ks[i]) ? as_[i] : bs[i]]);
      case _IndeksI():
        final g = _tamSayi(e.n, 0, kBetikAzamiUzunluk, 'geçmiş indeksi');
        final d = _sayisal(e.e);
        if (d is _Sabit || g == 0) return d;
        _harca(n, e.j);
        final s = (d as _Seri).v;
        return _Seri(
            [for (var i = 0; i < n; i++) i - g >= 0 ? s[i - g] : double.nan]);
      case _CagriI():
        return _cagri(e);
    }
  }

  _D _ikili(_IkiliI e) {
    final a = _sayisal(e.a);
    final b = _sayisal(e.b);
    double f(double x, double y) {
      switch (e.op) {
        case '+':
          return x + y;
        case '-':
          return x - y;
        case '*':
          return x * y;
        case '/':
          return y == 0 ? double.nan : x / y;
        case '%':
          return y == 0 ? double.nan : x % y;
        // Karşılaştırmada na → false (Pine ile aynı).
        case '==':
          return !x.isNaN && !y.isNaN && x == y ? 1 : 0;
        case '!=':
          return !x.isNaN && !y.isNaN && x != y ? 1 : 0;
        case '<':
          return x < y ? 1 : 0;
        case '<=':
          return x <= y ? 1 : 0;
        case '>':
          return x > y ? 1 : 0;
        case '>=':
          return x >= y ? 1 : 0;
        case 'and':
          return _dogru(x) && _dogru(y) ? 1 : 0;
        case 'or':
          return _dogru(x) || _dogru(y) ? 1 : 0;
      }
      return double.nan;
    }

    if (a is _Sabit && b is _Sabit) return _Sabit(f(a.v, b.v));
    _harca(n, e.j);
    final as_ = _seriYap(a, e.a.j);
    final bs = _seriYap(b, e.b.j);
    return _Seri([for (var i = 0; i < n; i++) f(as_[i], bs[i])]);
  }

  int _tamSayi(_Ifade e, int alt, int ust, String ne) {
    final d = _deger(e);
    if (d is! _Sabit || d.v.isNaN || d.v != d.v.roundToDouble()) {
      throw _hata('$ne sabit bir tam sayı olmalı (ör. 14).',
          '$ne must be a constant whole number (e.g. 14).', e.j);
    }
    final v = d.v.toInt();
    if (v < alt || v > ust) {
      throw _hata('$ne $alt ile $ust arasında olmalı.',
          '$ne must be between $alt and $ust.', e.j);
    }
    return v;
  }

  // ── Fonksiyonlar ──────────────────────────────────────────────────────────

  _D _cagri(_CagriI c) {
    final ad = _fonksiyonAdlari[c.ad];
    if (ad == null) {
      throw _hata('${c.ad}(...) yalnız satır başında kullanılır.',
          '${c.ad}(...) can only start a line.', c.j);
    }
    if (c.adli.isNotEmpty) {
      throw _hata('$ad adlı değer almaz; sırayla yaz: $ad(close, 14)',
          '$ad takes positional arguments: $ad(close, 14)',
          c.adli.values.first.j);
    }
    void sayi(int az, [int? cok]) {
      final c0 = c.arg.length;
      if (c0 < az || c0 > (cok ?? az)) {
        throw _hata(
            '$ad ${cok == null || cok == az ? '$az' : '$az-$cok'} değer alır.',
            '$ad takes ${cok == null || cok == az ? '$az' : '$az-$cok'} arguments.',
            c.j);
      }
    }

    List<double> seri(int i) => _seriYap(_sayisal(c.arg[i]), c.arg[i].j);
    int uzunluk(int i) =>
        _tamSayi(c.arg[i], 1, kBetikAzamiUzunluk, 'Uzunluk');

    switch (ad) {
      case 'sma' || 'ema' || 'wma' || 'rma' || 'rsi' || 'stdev' || 'sum':
        sayi(2);
        final s = seri(0);
        final l = uzunluk(1);
        _harca(n * (ad == 'stdev' || ad == 'wma' ? l : 2), c.j);
        return _Seri(switch (ad) {
          'sma' => _sma(s, l),
          'ema' => _ema(s, l, 2 / (l + 1)),
          'rma' => _ema(s, l, 1 / l),
          'wma' => _wma(s, l),
          'rsi' => _rsi(s, l),
          'stdev' => _stdev(s, l),
          _ => _toplam(s, l),
        });
      case 'vwma':
        sayi(2);
        final s = seri(0);
        final l = uzunluk(1);
        _harca(n * 4, c.j);
        final h = _yerlesik('volume', c.j);
        final pay = _sma([for (var i = 0; i < n; i++) s[i] * h[i]], l);
        final payda = _sma(h, l);
        return _Seri([
          for (var i = 0; i < n; i++)
            payda[i] == 0 ? double.nan : pay[i] / payda[i]
        ]);
      case 'highest' || 'lowest':
        sayi(1, 2);
        final enY = ad == 'highest';
        final List<double> s;
        final int l;
        if (c.arg.length == 1) {
          s = _yerlesik(enY ? 'high' : 'low', c.j);
          l = uzunluk(0);
        } else {
          s = seri(0);
          l = uzunluk(1);
        }
        _harca(n * l, c.j);
        return _Seri(_uc(s, l, enY));
      case 'change' || 'mom' || 'roc':
        sayi(1, 2);
        final s = seri(0);
        final l = c.arg.length > 1 ? uzunluk(1) : 1;
        _harca(n, c.j);
        return _Seri([
          for (var i = 0; i < n; i++)
            i - l < 0
                ? double.nan
                : ad == 'roc'
                    ? (s[i - l] == 0
                        ? double.nan
                        : 100 * (s[i] - s[i - l]) / s[i - l])
                    : s[i] - s[i - l]
        ]);
      case 'crossover' || 'crossunder' || 'cross':
        sayi(2);
        final a = seri(0);
        final b = seri(1);
        _harca(n, c.j);
        return _Seri([
          for (var i = 0; i < n; i++)
            i == 0
                ? 0
                : (switch (ad) {
                    'crossover' => a[i] > b[i] && a[i - 1] <= b[i - 1],
                    'crossunder' => a[i] < b[i] && a[i - 1] >= b[i - 1],
                    _ => (a[i] > b[i] && a[i - 1] <= b[i - 1]) ||
                        (a[i] < b[i] && a[i - 1] >= b[i - 1]),
                  })
                    ? 1
                    : 0
        ]);
      case 'atr':
        sayi(1);
        final l = uzunluk(0);
        _harca(n * 3, c.j);
        _yerlesik('high', c.j);
        return _Seri(_ema(_gercekAralik(), l, 1 / l));
      case 'cum':
        sayi(1);
        final s = seri(0);
        _harca(n, c.j);
        var t = 0.0;
        return _Seri([
          for (final v in s) v.isNaN ? double.nan : (t += v)
        ]);
      case 'nz':
        sayi(1, 2);
        final d = _sayisal(c.arg[0]);
        final r = c.arg.length > 1 ? _sayisal(c.arg[1]) : const _Sabit(0);
        return _eleman([d, r], c.j, (v) => v[0].isNaN ? v[1] : v[0]);
      case 'na':
        sayi(1);
        return _eleman(
            [_sayisal(c.arg[0])], c.j, (v) => v[0].isNaN ? 1 : 0);
      case 'max' || 'min' || 'avg':
        if (c.arg.length < 2 || c.arg.length > 8) {
          throw _hata('$ad 2-8 değer alır.', '$ad takes 2-8 arguments.', c.j);
        }
        return _eleman([for (final a in c.arg) _sayisal(a)], c.j, (v) {
          if (v.any((x) => x.isNaN)) return double.nan;
          return switch (ad) {
            'max' => v.reduce(math.max),
            'min' => v.reduce(math.min),
            _ => v.reduce((a, b) => a + b) / v.length,
          };
        });
      case 'pow':
        sayi(2);
        return _eleman([_sayisal(c.arg[0]), _sayisal(c.arg[1])], c.j,
            (v) => math.pow(v[0], v[1]).toDouble());
      default:
        sayi(1);
        double f(double v) => switch (ad) {
              'abs' => v.abs(),
              'sqrt' => v < 0 ? double.nan : math.sqrt(v),
              'log' => v <= 0 ? double.nan : math.log(v),
              'log10' => v <= 0 ? double.nan : math.log(v) / math.ln10,
              'exp' => math.exp(v),
              'round' => v.isNaN ? v : v.roundToDouble(),
              'floor' => v.isNaN ? v : v.floorToDouble(),
              'ceil' => v.isNaN ? v : v.ceilToDouble(),
              'sign' => v.isNaN ? v : v.sign,
              _ => double.nan,
            };
        return _eleman([_sayisal(c.arg[0])], c.j, (v) => f(v[0]));
    }
  }

  /// Eleman eleman uygulama; hepsi sabitse sabit döner.
  _D _eleman(List<_D> girdiler, _Jeton j, double Function(List<double>) f) {
    if (girdiler.every((d) => d is _Sabit)) {
      return _Sabit(f([for (final d in girdiler) (d as _Sabit).v]));
    }
    _harca(n * girdiler.length, j);
    final seriler = [for (final d in girdiler) _seriYap(d, j)];
    return _Seri([
      for (var i = 0; i < n; i++) f([for (final s in seriler) s[i]])
    ]);
  }

  // ── Seri hesapları (saf) ──────────────────────────────────────────────────
  //
  // Sözleşme `TechnicalAnalysisService.smaSeries/emaSeries` ile aynı:
  // pencere dolmadan değer yok (NaN); penceresinde na olan çubuk na.

  static List<double> _sma(List<double> s, int l) {
    final n = s.length;
    final out = List<double>.filled(n, double.nan);
    var toplam = 0.0;
    var gecerli = 0;
    for (var i = 0; i < n; i++) {
      if (!s[i].isNaN) {
        toplam += s[i];
        gecerli++;
      }
      if (i >= l && !s[i - l].isNaN) {
        toplam -= s[i - l];
        gecerli--;
      }
      if (i >= l - 1 && gecerli == l) out[i] = toplam / l;
    }
    return out;
  }

  static List<double> _toplam(List<double> s, int l) {
    final o = _sma(s, l);
    return [for (final v in o) v * l];
  }

  /// EMA/RMA: ilk dolu penceredeki basit ortalamayla tohumlanır (TradingView
  /// ve `TechnicalAnalysisService.emaSeries` ile aynı). Arada na gelirse o
  /// çubuk na kalır, durum korunur.
  static List<double> _ema(List<double> s, int l, double alfa) {
    final n = s.length;
    final out = List<double>.filled(n, double.nan);
    final sma = _sma(s, l);
    double? e;
    for (var i = 0; i < n; i++) {
      if (e == null) {
        if (!sma[i].isNaN) {
          e = sma[i];
          out[i] = e;
        }
        continue;
      }
      if (s[i].isNaN) continue;
      e = alfa * s[i] + (1 - alfa) * e;
      out[i] = e;
    }
    return out;
  }

  static List<double> _wma(List<double> s, int l) {
    final n = s.length;
    final payda = l * (l + 1) / 2;
    return [
      for (var i = 0; i < n; i++)
        if (i < l - 1)
          double.nan
        else
          () {
            var t = 0.0;
            for (var k = 0; k < l; k++) {
              t += s[i - k] * (l - k);
            }
            return t / payda;
          }()
    ];
  }

  static List<double> _stdev(List<double> s, int l) {
    final ort = _sma(s, l);
    return [
      for (var i = 0; i < s.length; i++)
        if (ort[i].isNaN)
          double.nan
        else
          () {
            var t = 0.0;
            for (var k = 0; k < l; k++) {
              final d = s[i - k] - ort[i];
              t += d * d;
            }
            return math.sqrt(t / l);
          }()
    ];
  }

  static List<double> _uc(List<double> s, int l, bool enYuksek) => [
        for (var i = 0; i < s.length; i++)
          if (i < l - 1)
            double.nan
          else
            () {
              var m = s[i];
              for (var k = 1; k < l; k++) {
                final v = s[i - k];
                if (v.isNaN || m.isNaN) return double.nan;
                if (enYuksek ? v > m : v < m) m = v;
              }
              return m;
            }()
      ];

  /// Wilder RSI (TradingView `ta.rsi`): kazanç/kayıp RMA'sı.
  static List<double> _rsi(List<double> s, int l) {
    final n = s.length;
    final yukari = <double>[double.nan];
    final asagi = <double>[double.nan];
    for (var i = 1; i < n; i++) {
      final d = s[i] - s[i - 1];
      yukari.add(d.isNaN ? double.nan : math.max(d, 0));
      asagi.add(d.isNaN ? double.nan : math.max(-d, 0));
    }
    if (n == 0) return const [];
    final u = _ema(yukari, l, 1 / l);
    final a = _ema(asagi, l, 1 / l);
    return [
      for (var i = 0; i < n; i++)
        if (u[i].isNaN || a[i].isNaN)
          double.nan
        else if (a[i] == 0)
          100
        else if (u[i] == 0)
          0
        else
          100 - 100 / (1 + u[i] / a[i])
    ];
  }
}
