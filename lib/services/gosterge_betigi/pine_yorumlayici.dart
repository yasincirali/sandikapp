part of 'betik.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Yorumlayıcı — Pine'ın yürütme modeli
//
// Betik her çubukta baştan sona bir kez çalışır (Pine gibi). Durum taşıyan
// her şey — `var` değişkenleri, `ta.*` çağrılarının iç durumu, `x[n]`
// tamponları — ÇAĞRI BAĞLAMI başına saklanır: anahtar, düğüm kimliği + o
// düğüme hangi kullanıcı fonksiyonu çağrılarından gelindiği ([_yol]). Böylece
// aynı fonksiyonun iki yerden çağrılması iki ayrı EMA durumu tutar; Pine'da
// da öyledir.
// ─────────────────────────────────────────────────────────────────────────────

/// Pine rengi. Ekrana çıkarken [token] en yakın tasarım rengine düşer;
/// `color.r()` gibi okumalar için asıl RGB saklanır.
class _PineRenk {
  const _PineRenk(this.r, this.g, this.b, [this.t = 0]);
  final int r;
  final int g;
  final int b;

  /// Saydamlık 0-100 (Pine'daki `transp`).
  final double t;

  factory _PineRenk.onaltilik(String h) {
    final v = int.parse(h.substring(0, 6), radix: 16);
    var t = 0.0;
    if (h.length == 8) {
      final a = int.parse(h.substring(6, 8), radix: 16);
      t = (1 - a / 255) * 100;
    }
    return _PineRenk((v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff, t);
  }

  _PineRenk saydam(double t) =>
      _PineRenk(r, g, b, t.isNaN ? this.t : t.clamp(0, 100).toDouble());

  bool get gorunmez => t >= 100;

  /// En yakın tasarım rengi adı (`gosterge_cizimi.betikRengi` çevirir).
  String get token {
    final rr = r / 255, gg = g / 255, bb = b / 255;
    final mx = math.max(rr, math.max(gg, bb));
    final mn = math.min(rr, math.min(gg, bb));
    final d = mx - mn;
    if (mx < 0.15 || (mx == 0 ? 0 : d / mx) < 0.18) return 'gri';
    double h;
    if (mx == rr) {
      h = 60 * (((gg - bb) / d) % 6);
    } else if (mx == gg) {
      h = 60 * ((bb - rr) / d + 2);
    } else {
      h = 60 * ((rr - gg) / d + 4);
    }
    if (h < 0) h += 360;
    if (h < 15 || h >= 330) return 'kirmizi';
    if (h < 40) return 'turuncu';
    if (h < 70) return 'sari';
    if (h < 170) return 'yesil';
    if (h < 255) return 'mavi';
    return 'mor';
  }

  @override
  bool operator ==(Object o) =>
      o is _PineRenk && o.r == r && o.g == g && o.b == b && o.t == t;

  @override
  int get hashCode => Object.hash(r, g, b, t);
}

/// `plot()` / `hline()` dönüş değeri — `fill()` bununla çizgiyi bulur.
class _CizimKimligi {
  const _CizimKimligi(this.tur, this.id);
  final String tur;
  final int id;
}

/// Değişken hücresi: güncel değer + çubuk başına son değer (`x[n]` için).
class _Hucre {
  _Hucre(int n) : gecmis = List<Object?>.filled(n, double.nan);
  Object? deger = double.nan;
  final List<Object?> gecmis;
  bool basladi = false;
}

class _Kapsam {
  _Kapsam(this.ust);
  final _Kapsam? ust;
  final Map<String, _Hucre> adlar = {};

  _Hucre? bul(String ad) {
    for (_Kapsam? k = this; k != null; k = k.ust) {
      final h = k.adlar[ad];
      if (h != null) return h;
    }
    return null;
  }
}

enum _Akis { normal, kir, devam }

class _CizgiKaydi {
  _CizgiKaydi(int n)
      : degerler = List<double>.filled(n, double.nan),
        renkler = List<String?>.filled(n, null);
  String? ad;
  final List<double> degerler;
  final List<String?> renkler;
  bool renkVerildi = false;
  bool hepsiSaydam = true;
  bool gizli = false;
  double kalinlik = 1.6;
  BetikCizgiStili stil = BetikCizgiStili.cizgi;
  int kayma = 0;
}

class _YatayKaydi {
  _YatayKaydi(this.ad, this.deger, this.renk);
  final String ad;
  final double deger;
  final String? renk;
}

class _IsaretKaydi {
  _IsaretKaydi(this.ad);
  final String ad;
  final List<int> indeksler = [];
  final Map<String, int> renkler = {};
}

class _DolguKaydi {
  _DolguKaydi(this.a, this.b, this.renk);
  final _CizimKimligi a;
  final _CizimKimligi b;
  final String? renk;
}

/// Eksik argüman işareti (Pine'da verilmemiş parametre).
class _Yok {
  const _Yok();
}

const _yok = _Yok();

class _Yorumlayici {
  _Yorumlayici(this.veri, this.program)
      : n = veri.uzunluk,
        _ohlc = veri.ohlcVar,
        _hacimVar = veri.hacimVar;

  final BetikVerisi veri;
  final _Program program;
  final int n;
  final bool _ohlc;
  final bool _hacimVar;

  int _i = 0;
  String _yol = '';
  int _cagriDerinligi = 0;
  late _Kapsam _global;
  _Akis _akis = _Akis.normal;
  int _islem = 0;

  final Map<Object, Object> _durum = {};
  final List<_Hucre> _kalicilar = [];
  final Set<String> _eksik = {};
  final Set<BetikNotu> _notlar = {};
  final Map<int, _CizgiKaydi> _cizgiler = {};
  final Map<int, _YatayKaydi> _yataylar = {};
  final Map<int, _IsaretKaydi> _isaretler = {};
  final Map<int, _DolguKaydi> _dolgular = {};
  final Map<String, List<double>> _onHesap = {};

  Object _anahtar(int id) => _yol.isEmpty ? id : '$_yol:$id';

  T _durumAl<T extends Object>(int id, T Function() yeni) =>
      _durum.putIfAbsent(_anahtar(id), yeni) as T;

  _Hucre _hucre(Object anahtar) =>
      _durum.putIfAbsent(anahtar, () => _Hucre(n)) as _Hucre;

  void _yaz(_Hucre h, Object? v) {
    h.deger = v;
    h.gecmis[_i] = v;
  }

  void _harca(int k, _Jeton j) {
    _islem += k;
    if (_islem > _kIslemButcesi) {
      throw _hata('Betik bu grafik için çok ağır; döngüleri ya da uzunlukları küçült.',
          'Script is too heavy for this chart; shorten loops or lengths.', j);
    }
  }

  BetikSonucu calistir() {
    for (_i = 0; _i < n; _i++) {
      _global = _Kapsam(null);
      _akis = _Akis.normal;
      _blok(program.deyimler, _global);
      for (final h in _kalicilar) {
        h.gecmis[_i] = h.deger;
      }
    }
    if (n == 0) _i = 0;
    return _sonuc();
  }

  // ── Tip dönüşümleri ───────────────────────────────────────────────────────

  static double _sayi(Object? v) => switch (v) {
        double() => v,
        int() => v.toDouble(),
        bool() => v ? 1 : 0,
        _ => double.nan,
      };

  static bool _bool(Object? v) => switch (v) {
        bool() => v,
        double() => !v.isNaN && v != 0,
        int() => v != 0,
        _ => false,
      };

  static String _metin(Object? v) => switch (v) {
        String() => v,
        double() when v.isNaN => '',
        double() => v == v.roundToDouble() && v.abs() < 1e15
            ? v.toInt().toString()
            : v.toString(),
        bool() => v.toString(),
        _ => '',
      };

  static _PineRenk? _renk(Object? v) => v is _PineRenk ? v : null;

  static bool _na(Object? v) =>
      v == null || (v is double && v.isNaN) || v is _Yok;

  // ── Deyimler ──────────────────────────────────────────────────────────────

  Object? _blok(List<_D> b, _Kapsam k) {
    Object? son = double.nan;
    for (final d in b) {
      son = _deyim(d, k);
      if (_akis != _Akis.normal) break;
    }
    return son;
  }

  Object? _deyim(_D d, _Kapsam k) {
    _harca(1, d.j);
    switch (d) {
      case _DBildir():
        final h = _hucre(_anahtar(d.id));
        if (d.kalici) {
          if (!h.basladi) {
            h.basladi = true;
            h.deger = _e(d.e, k);
            _kalicilar.add(h);
          }
        } else {
          _yaz(h, _e(d.e, k));
        }
        k.adlar[d.ad] = h;
        return h.deger;
      case _DDemet():
        final v = _e(d.e, k);
        if (v is! List) {
          throw _hata('Sağ taraf birden çok değer döndürmüyor.',
              'The right side does not return multiple values.', d.j);
        }
        if (v.length != d.adlar.length) {
          throw _hata('${v.length} değer dönüyor, ${d.adlar.length} ad yazılmış.',
              '${v.length} values returned, ${d.adlar.length} names given.',
              d.j);
        }
        final kok = _anahtar(d.id);
        for (var i = 0; i < d.adlar.length; i++) {
          final h = _hucre('$kok#$i');
          _yaz(h, v[i]);
          k.adlar[d.adlar[i]] = h;
        }
        return v;
      case _DAta():
        final h = k.bul(d.ad);
        if (h == null) {
          throw _hata("'${d.ad}' bu kapsamda tanımlı değil.",
              "'${d.ad}' is not declared in this scope.", d.j);
        }
        var v = _e(d.e, k);
        if (d.op != ':=') {
          v = _aritmetik(d.op[0], h.deger, v);
        }
        _yaz(h, v);
        return v;
      case _DIfade():
        return _e(d.e, k);
      case _DFor():
        return _for(d, k);
      case _DWhile():
        Object? son = double.nan;
        while (_bool(_e(d.kosul, k))) {
          _harca(1, d.j);
          son = _blok(d.blok, _Kapsam(k));
          if (_akis == _Akis.kir) {
            _akis = _Akis.normal;
            break;
          }
          if (_akis == _Akis.devam) _akis = _Akis.normal;
        }
        return son;
      case _DKir():
        _akis = _Akis.kir;
        return double.nan;
      case _DDevam():
        _akis = _Akis.devam;
        return double.nan;
    }
  }

  Object? _for(_DFor d, _Kapsam k) {
    final bas = _sayi(_e(d.bas, k));
    final son = _sayi(_e(d.son, k));
    final adim = d.adim == null ? 1.0 : _sayi(_e(d.adim!, k)).abs();
    if (bas.isNaN || son.isNaN || adim.isNaN) return double.nan;
    if (adim == 0) {
      throw _hata('for adımı 0 olamaz.', 'for step cannot be 0.', d.j);
    }
    final yon = son >= bas ? 1.0 : -1.0;
    final h = _hucre('${_anahtar(d.id)}#i');
    final dis = _Kapsam(k)..adlar[d.ad] = h;
    Object? sonDeger = double.nan;
    for (var v = bas; yon > 0 ? v <= son : v >= son; v += yon * adim) {
      _harca(1, d.j);
      _yaz(h, v);
      sonDeger = _blok(d.blok, _Kapsam(dis));
      if (_akis == _Akis.kir) {
        _akis = _Akis.normal;
        break;
      }
      if (_akis == _Akis.devam) _akis = _Akis.normal;
    }
    return sonDeger;
  }

  // ── İfadeler ──────────────────────────────────────────────────────────────

  Object? _e(_I e, _Kapsam k) {
    _harca(1, e.j);
    switch (e) {
      case _ISayi():
        return e.v;
      case _IMetin():
        return e.v;
      case _IBool():
        return e.v;
      case _INa():
        return double.nan;
      case _IRenk():
        return e.renk;
      case _IAd():
        final h = k.bul(e.ad);
        if (h != null) return h.deger;
        final kan = _degiskenKanonik(e.ad);
        if (kan != null) return _yerlesikDeger(kan, _i, e.j);
        if (_sabitAdMi(e.ad)) return _sabitDeger(e.ad);
        throw _hata("'${e.ad}' bu noktada tanımlı değil.",
            "'${e.ad}' is not defined at this point.", e.j);
      case _ITekli():
        final v = _e(e.e, k);
        if (e.op == 'not') return !_bool(v);
        return -_sayi(v);
      case _IIkili():
        return _ikili(e, k);
      case _IKosul():
        return _bool(_e(e.k, k)) ? _e(e.a, k) : _e(e.b, k);
      case _IGecmis():
        return _gecmis(e, k);
      case _ICagri():
        return e.kullanici ? _kullaniciCagri(e, k) : _yerlesikCagri(e, k);
      case _IDizi():
        return [for (final x in e.elemanlar) _e(x, k)];
      case _IEger():
        for (var i = 0; i < e.kosullar.length; i++) {
          if (_bool(_e(e.kosullar[i], k))) {
            return _blok(e.bloklar[i], _Kapsam(k));
          }
        }
        if (e.degilse != null) return _blok(e.degilse!, _Kapsam(k));
        return double.nan;
      case _ISec():
        final konu = e.konu == null ? null : _e(e.konu!, k);
        List<_D>? varsayilan;
        for (final (kosul, blok) in e.durumlar) {
          if (kosul == null) {
            varsayilan = blok;
            continue;
          }
          final v = _e(kosul, k);
          final tutar = e.konu == null ? _bool(v) : _esit(konu, v);
          if (tutar) return _blok(blok, _Kapsam(k));
        }
        if (varsayilan != null) return _blok(varsayilan, _Kapsam(k));
        return double.nan;
    }
  }

  static bool _esit(Object? a, Object? b) {
    if (a is String || b is String) return a == b;
    if (a is _PineRenk || b is _PineRenk) return a == b;
    final x = _sayi(a), y = _sayi(b);
    return !x.isNaN && !y.isNaN && x == y;
  }

  Object? _ikili(_IIkili e, _Kapsam k) {
    final a = _e(e.a, k);
    final b = _e(e.b, k);
    switch (e.op) {
      case 'and':
        return _bool(a) && _bool(b);
      case 'or':
        return _bool(a) || _bool(b);
      case '==':
        return _esit(a, b);
      case '!=':
        if (_na(a) || _na(b)) return false;
        return !_esit(a, b);
      case '<':
        return _sayi(a) < _sayi(b);
      case '>':
        return _sayi(a) > _sayi(b);
      case '<=':
        return _sayi(a) <= _sayi(b);
      case '>=':
        return _sayi(a) >= _sayi(b);
    }
    return _aritmetik(e.op, a, b);
  }

  static Object? _aritmetik(String op, Object? a, Object? b) {
    if (op == '+' && (a is String || b is String)) {
      return _metin(a) + _metin(b);
    }
    final x = _sayi(a), y = _sayi(b);
    switch (op) {
      case '+':
        return x + y;
      case '-':
        return x - y;
      case '*':
        return x * y;
      case '/':
        return y == 0 ? double.nan : x / y;
      case '%':
        return y == 0 ? double.nan : x.remainder(y);
    }
    return double.nan;
  }

  Object? _gecmis(_IGecmis e, _Kapsam k) {
    final nv = _sayi(_e(e.n, k));
    if (nv.isNaN) return double.nan;
    final g = nv.toInt();
    if (g < 0 || g > kBetikAzamiUzunluk) {
      throw _hata('Geçmiş indeksi 0 ile $kBetikAzamiUzunluk arasında olmalı.',
          'History index must be between 0 and $kBetikAzamiUzunluk.', e.j);
    }
    final hedef = _i - g;
    final taban = e.e;
    if (taban is _IAd) {
      final h = k.bul(taban.ad);
      if (h != null) {
        if (g == 0) return h.deger;
        return hedef >= 0 ? h.gecmis[hedef] : double.nan;
      }
      final kan = _degiskenKanonik(taban.ad);
      if (kan != null) {
        return hedef >= 0 ? _yerlesikDeger(kan, hedef, taban.j) : double.nan;
      }
    }
    final tampon = _durumAl<List<Object?>>(
        e.id, () => List<Object?>.filled(n, double.nan));
    final v = _e(taban, k);
    tampon[_i] = v;
    return hedef >= 0 ? tampon[hedef] : double.nan;
  }

  Object? _kullaniciCagri(_ICagri c, _Kapsam k) {
    final f = program.fonksiyonlar[c.ad]!;
    final p = f.parametreler;
    if (c.arg.length > p.length) {
      throw _hata('${f.ad} en fazla ${p.length} değer alır.',
          '${f.ad} takes at most ${p.length} arguments.', c.j);
    }
    final degerler = List<Object?>.filled(p.length, _yok);
    for (var i = 0; i < c.arg.length; i++) {
      degerler[i] = _e(c.arg[i], k);
    }
    for (final a in c.adli.entries) {
      final i = p.indexWhere((x) => x.$1 == a.key);
      if (i < 0) {
        throw _hata("${f.ad} içinde '${a.key}' parametresi yok.",
            "${f.ad} has no parameter '${a.key}'.", a.value.j);
      }
      degerler[i] = _e(a.value, k);
    }
    for (var i = 0; i < p.length; i++) {
      if (degerler[i] is! _Yok) continue;
      final v = p[i].$2;
      if (v == null) {
        throw _hata("${f.ad} için '${p[i].$1}' eksik.",
            "Missing '${p[i].$1}' for ${f.ad}.", c.j);
      }
      degerler[i] = _e(v, k);
    }
    if (++_cagriDerinligi > _kAzamiCagriDerinligi) {
      throw _hata('Fonksiyonlar çok iç içe çağrılıyor.',
          'Functions are nested too deeply.', c.j);
    }
    final eski = _yol;
    _yol = '$_yol/${c.id}';
    try {
      final kap = _Kapsam(_global);
      final kok = _anahtar(f.id);
      for (var i = 0; i < p.length; i++) {
        final h = _hucre('$kok#p$i');
        _yaz(h, degerler[i]);
        kap.adlar[p[i].$1] = h;
      }
      return _blok(f.govde, kap);
    } finally {
      _yol = eski;
      _cagriDerinligi--;
    }
  }

  // ── Yerleşik seriler ──────────────────────────────────────────────────────

  double _ac(int i) {
    if (!_ohlc) _eksik.add('acilis');
    return veri.acilis[i];
  }

  double _yk(int i) {
    if (!_ohlc) _eksik.add('yuksek');
    return veri.yuksek[i];
  }

  double _ds(int i) {
    if (!_ohlc) _eksik.add('dusuk');
    return veri.dusuk[i];
  }

  double _kp(int i) => veri.kapanis[i];

  double _hc(int i) {
    if (!_hacimVar) _eksik.add('hacim');
    return veri.hacim[i];
  }

  /// Çubuğun yerel (İstanbul) saati. Borsa İstanbul ve uygulamanın
  /// gün sınırı UTC+3.
  DateTime _zaman(int i) =>
      DateTime.fromMillisecondsSinceEpoch(veri.zamanlar[i].toInt(), isUtc: true)
          .add(const Duration(hours: 3));

  bool get _gunIci {
    final p = veri.zamanDilimi;
    return p.isNotEmpty && int.tryParse(p) != null;
  }

  Object? _yerlesikDeger(String ad, int i, _Jeton j) {
    switch (ad) {
      case 'open':
        return _ac(i);
      case 'high':
        return _yk(i);
      case 'low':
        return _ds(i);
      case 'close':
        return _kp(i);
      case 'volume':
        return _hc(i);
      case 'hl2':
        return (_yk(i) + _ds(i)) / 2;
      case 'hlc3':
        return (_yk(i) + _ds(i) + _kp(i)) / 3;
      case 'hlcc4':
        return (_yk(i) + _ds(i) + 2 * _kp(i)) / 4;
      case 'ohlc4':
        return (_ac(i) + _yk(i) + _ds(i) + _kp(i)) / 4;
      case 'time' || 'time_tradingday':
        return veri.zamanlar[i];
      case 'time_close':
        return i + 1 < n ? veri.zamanlar[i + 1] : veri.zamanlar[i];
      case 'timenow':
        return n == 0 ? double.nan : veri.zamanlar[n - 1];
      case 'bar_index':
        return i.toDouble();
      case 'last_bar_index':
        return (n - 1).toDouble();
      case 'last_bar_time':
        return n == 0 ? double.nan : veri.zamanlar[n - 1];
      case 'year':
        return _zaman(i).year.toDouble();
      case 'month':
        return _zaman(i).month.toDouble();
      case 'dayofmonth':
        return _zaman(i).day.toDouble();
      case 'dayofweek':
        return (_zaman(i).weekday % 7 + 1).toDouble();
      case 'hour':
        return _zaman(i).hour.toDouble();
      case 'minute':
        return _zaman(i).minute.toDouble();
      case 'second':
        return _zaman(i).second.toDouble();
      case 'weekofyear':
        final z = _zaman(i);
        final gun = z.difference(DateTime.utc(z.year)).inDays;
        return (gun ~/ 7 + 1).toDouble();
      case 'barstate.islast' || 'barstate.islastconfirmedhistory':
        return i == n - 1;
      case 'barstate.isfirst':
        return i == 0;
      case 'barstate.ishistory':
        return i < n - 1;
      case 'barstate.isrealtime':
        return false;
      case 'barstate.isconfirmed' || 'barstate.isnew':
        return true;
      case 'timeframe.period' || 'timeframe.main_period':
        return veri.zamanDilimi;
      case 'timeframe.multiplier':
        final p = veri.zamanDilimi;
        return (int.tryParse(p.replaceAll(RegExp(r'[A-Za-z]'), '')) ?? 1)
            .toDouble();
      case 'timeframe.isintraday' || 'timeframe.isminutes':
        return _gunIci;
      case 'timeframe.isseconds' || 'timeframe.isticks':
        return false;
      case 'timeframe.isdaily':
        return veri.zamanDilimi.endsWith('D');
      case 'timeframe.isweekly':
        return veri.zamanDilimi.endsWith('W');
      case 'timeframe.ismonthly':
        return veri.zamanDilimi.endsWith('M');
      case 'timeframe.isdwm':
        return !_gunIci;
      case 'syminfo.ticker' || 'syminfo.root' || 'syminfo.description':
        return veri.sembol;
      case 'syminfo.tickerid':
        return 'SANDIK:${veri.sembol}';
      case 'syminfo.prefix':
        return 'SANDIK';
      case 'syminfo.currency' || 'syminfo.basecurrency':
        return 'TRY';
      case 'syminfo.mintick':
        return 0.01;
      case 'syminfo.pointvalue':
        return 1.0;
      case 'syminfo.type':
        return 'stock';
      case 'syminfo.timezone':
        return 'Europe/Istanbul';
      case 'syminfo.session':
        return 'regular';
      case 'math.pi':
        return math.pi;
      case 'math.e':
        return math.e;
      case 'math.phi':
        return 1.618033988749895;
      case 'math.rphi':
        return 0.618033988749895;
    }
    if (ad.startsWith('strategy.')) {
      _notlar.add(BetikNotu.strateji);
      return 0.0;
    }
    if (ad.startsWith('ta.')) return _onSeri(ad, j)[i];
    throw _hata("'$ad' desteklenmiyor.", "'$ad' is not supported.", j);
  }

  /// Betikten bağımsız birikimli seriler (`ta.obv`, `ta.vwap` …) bir kez
  /// hesaplanır.
  List<double> _onSeri(String ad, _Jeton j) {
    final hazir = _onHesap[ad];
    if (hazir != null) return hazir;
    final out = List<double>.filled(n, double.nan);
    switch (ad) {
      case 'ta.tr':
        for (var i = 0; i < n; i++) {
          out[i] = _trAt(i, false);
        }
      case 'ta.obv':
        var t = 0.0;
        for (var i = 0; i < n; i++) {
          if (i > 0) {
            final d = _kp(i) - _kp(i - 1);
            t += d > 0 ? _hc(i) : (d < 0 ? -_hc(i) : 0);
          }
          out[i] = t;
        }
      case 'ta.accdist':
        var t = 0.0;
        for (var i = 0; i < n; i++) {
          final h = _yk(i), l = _ds(i), c = _kp(i);
          final mf = h == l ? 0.0 : ((c - l) - (h - c)) / (h - l);
          t += mf * _hc(i);
          out[i] = t;
        }
      case 'ta.pvt':
        var t = 0.0;
        for (var i = 0; i < n; i++) {
          if (i > 0 && _kp(i - 1) != 0) {
            t += (_kp(i) - _kp(i - 1)) / _kp(i - 1) * _hc(i);
          }
          out[i] = t;
        }
      case 'ta.vwap':
        var pv = 0.0, v = 0.0;
        int? gun;
        for (var i = 0; i < n; i++) {
          final z = _zaman(i);
          final g = z.year * 400 + z.month * 32 + z.day;
          if (g != gun) {
            gun = g;
            pv = 0;
            v = 0;
          }
          final src = (_yk(i) + _ds(i) + _kp(i)) / 3;
          pv += src * _hc(i);
          v += _hc(i);
          out[i] = v == 0 ? double.nan : pv / v;
        }
      default:
        throw _hata("'$ad' desteklenmiyor.", "'$ad' is not supported.", j);
    }
    _harca(n, j);
    _onHesap[ad] = out;
    return out;
  }

  double _trAt(int i, bool naIsle) {
    final h = _yk(i), l = _ds(i);
    if (i == 0 || _kp(i - 1).isNaN) return naIsle ? h - l : double.nan;
    final pc = _kp(i - 1);
    return math.max(h - l, math.max((h - pc).abs(), (l - pc).abs()));
  }

  // ── Sonuç ─────────────────────────────────────────────────────────────────

  BetikSonucu _sonuc() {
    final cizgiler = <BetikCizgi>[];
    final cizgiSirasi = <int, int>{};
    for (final e in _cizgiler.entries) {
      if (cizgiler.length >= kBetikAzamiCizgi) {
        _notlar.add(BetikNotu.fazlaCizgi);
        break;
      }
      final c = e.value;
      var d = c.degerler;
      if (c.kayma != 0) {
        d = List<double>.filled(n, double.nan);
        for (var i = 0; i < n; i++) {
          final h = i + c.kayma;
          if (h >= 0 && h < n) d[h] = c.degerler[i];
        }
      }
      final histo = c.stil == BetikCizgiStili.histogram;
      cizgiSirasi[e.key] = cizgiler.length;
      cizgiler.add(BetikCizgi(
        c.ad ?? 'Çizgi ${cizgiler.length + 1}',
        d,
        renk: c.renkVerildi
            ? _enSik(c, (v) => !histo || v >= 0) ?? _enSik(c, (_) => true)
            : null,
        eksiRenk: c.renkVerildi && histo ? _enSik(c, (v) => v < 0) : null,
        kalinlik: c.kalinlik,
        stil: c.stil,
        gizli: c.gizli || (c.renkVerildi && c.hepsiSaydam),
      ));
    }
    final yataylar = _yataylar.values
        .take(_kAzamiYatay)
        .map((y) => BetikYatay(y.ad, y.deger, renk: y.renk))
        .toList();
    final isaretler = <BetikIsaret>[
      for (final m in _isaretler.values.take(_kAzamiIsaret))
        BetikIsaret(m.ad, m.indeksler,
            renk: m.renkler.isEmpty
                ? null
                : (m.renkler.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value)))
                    .first
                    .key),
    ];
    if (!program.fiyatUstunde && isaretler.any((m) => m.indeksler.isNotEmpty)) {
      _notlar.add(BetikNotu.paneldeIsaret);
    }
    final yatayDeger = {
      for (final e in _yataylar.entries) e.key: e.value.deger,
    };
    final dolgular = <BetikDolgu>[];
    for (final d in _dolgular.values) {
      if (d.a.tur == 'plot' && d.b.tur == 'plot') {
        final a = cizgiSirasi[d.a.id], b = cizgiSirasi[d.b.id];
        if (a != null && b != null) {
          dolgular.add(BetikDolgu(a: a, b: b, renk: d.renk));
        }
      } else if (d.a.tur == 'hline' && d.b.tur == 'hline') {
        final a = yatayDeger[d.a.id], b = yatayDeger[d.b.id];
        if (a != null && b != null) {
          dolgular.add(BetikDolgu(yatayA: a, yatayB: b, renk: d.renk));
        }
      }
    }
    return BetikSonucu(
      x: veri.x,
      fiyatUstunde: program.fiyatUstunde,
      baslik: program.baslik,
      cizgiler: cizgiler,
      yataylar: yataylar,
      isaretler: isaretler,
      dolgular: dolgular,
      eksikVeri: _eksik,
      notlar: _notlar,
    );
  }

  String? _enSik(_CizgiKaydi c, bool Function(double) filtre) {
    final say = <String, int>{};
    for (var i = 0; i < n; i++) {
      final r = c.renkler[i];
      final v = c.degerler[i];
      if (r == null || v.isNaN || !filtre(v)) continue;
      say[r] = (say[r] ?? 0) + 1;
    }
    if (say.isEmpty) return null;
    return (say.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .first
        .key;
  }
}
