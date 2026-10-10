part of 'betik.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Yerleşik kütüphane: adlar, imzalar ve uygulamalar
//
// İmzalar Pine v5/v6 başvuru kılavuzundaki parametre SIRASIDIR — sıralı
// argümanlar bu sırayla, adlı argümanlar adıyla eşlenir. Burada olmayan adlı
// argüman (ör. `minval=`, `group=`, `transp=`) sessizce yok sayılır: Pine'da
// çoğu görünüm/ayar içindir ve kopyalanan betiğin kırılması daha kötüdür.
//
// Hesaplar `TechnicalAnalysisService` ve TradingView ile aynı sözleşmede:
// pencere dolmadan değer yok (na); EMA/RMA ilk dolu penceredeki basit
// ortalamayla tohumlanır (uygulamanın EMA çipleriyle aynı sayı).
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _girdi = ['defval', 'title'];

const Map<String, List<String>> _imzalar = {
  // Çıktı
  'plot': [
    'series', 'title', 'color', 'linewidth', 'style', 'trackprice', //
    'histbase', 'offset', 'join', 'editable', 'show_last', 'display',
  ],
  'hline': [
    'price', 'title', 'color', 'linestyle', 'linewidth', 'editable', //
    'display',
  ],
  'plotshape': [
    'series', 'title', 'style', 'location', 'color', 'offset', 'text', //
    'textcolor', 'editable', 'size', 'show_last', 'display',
  ],
  'plotchar': [
    'series', 'title', 'char', 'location', 'color', 'offset', 'text', //
    'textcolor', 'editable', 'size', 'show_last', 'display',
  ],
  'plotarrow': [
    'series', 'title', 'colorup', 'colordown', 'offset', 'minheight', //
    'maxheight', 'editable', 'show_last', 'display',
  ],
  'fill': [
    'hline1', 'hline2', 'color', 'title', 'editable', 'fillgaps', //
    'display', 'top_value', 'bottom_value', 'top_color', 'bottom_color',
  ],
  // Bildirim ve no-op
  'indicator': [], 'strategy': [], 'alertcondition': [], 'alert': [], //
  'bgcolor': [], 'barcolor': [], 'plotcandle': [], 'plotbar': [],
  'max_bars_back': [],
  // Girdi
  'input': _girdi, 'input.int': _girdi, 'input.float': _girdi, //
  'input.bool': _girdi, 'input.string': _girdi, 'input.color': _girdi,
  'input.source': _girdi, 'input.timeframe': _girdi,
  'input.session': _girdi, 'input.symbol': _girdi, 'input.price': _girdi,
  'input.time': _girdi, 'input.text_area': _girdi, 'input.enum': _girdi,
  // Veri
  'request.security': [
    'symbol', 'timeframe', 'expression', 'gaps', 'lookahead', //
    'ignore_invalid_symbol', 'currency',
  ],
  'ticker.new': ['*'], 'ticker.standard': ['*'], 'ticker.modify': ['*'],
  'ticker.heikinashi': ['*'], 'ticker.renko': ['*'], 'ticker.kagi': ['*'],
  'ticker.linebreak': ['*'], 'ticker.pointfigure': ['*'],
  // Genel
  'na': ['x'], 'nz': ['source', 'replacement'], 'fixnan': ['source'],
  'iff': ['condition', 'then', '_else'],
  'runtime.error': ['message'],
  // ta
  'ta.sma': ['source', 'length'], 'ta.ema': ['source', 'length'],
  'ta.rma': ['source', 'length'], 'ta.wma': ['source', 'length'],
  'ta.vwma': ['source', 'length'], 'ta.hma': ['source', 'length'],
  'ta.swma': ['source'],
  'ta.alma': ['series', 'length', 'offset', 'sigma', 'floor'],
  'ta.linreg': ['source', 'length', 'offset'],
  'ta.rsi': ['source', 'length'],
  'ta.stdev': ['source', 'length', 'biased'],
  'ta.variance': ['source', 'length', 'biased'],
  'ta.dev': ['source', 'length'],
  'ta.highest': ['source', 'length'], 'ta.lowest': ['source', 'length'],
  'ta.highestbars': ['source', 'length'],
  'ta.lowestbars': ['source', 'length'],
  'ta.change': ['source', 'length'], 'ta.mom': ['source', 'length'],
  'ta.roc': ['source', 'length'],
  'ta.cross': ['source1', 'source2'], 'ta.crossover': ['source1', 'source2'],
  'ta.crossunder': ['source1', 'source2'],
  'ta.atr': ['length'], 'ta.tr': ['handle_na'], 'ta.cum': ['source'],
  'ta.macd': ['source', 'fastlen', 'slowlen', 'siglen'],
  'ta.bb': ['series', 'length', 'mult'], 'ta.bbw': ['series', 'length', 'mult'],
  'ta.kc': ['series', 'length', 'mult', 'useTrueRange'],
  'ta.kcw': ['series', 'length', 'mult', 'useTrueRange'],
  'ta.stoch': ['source', 'high', 'low', 'length'],
  'ta.cci': ['source', 'length'], 'ta.mfi': ['series', 'length'],
  'ta.wpr': ['length'], 'ta.cmo': ['series', 'length'],
  'ta.tsi': ['source', 'short_length', 'long_length'],
  'ta.vwap': ['source'],
  'ta.dmi': ['diLength', 'adxSmoothing'],
  'ta.supertrend': ['factor', 'atrPeriod'],
  'ta.sar': ['start', 'inc', 'max'],
  'ta.pivothigh': ['source', 'leftbars', 'rightbars'],
  'ta.pivotlow': ['source', 'leftbars', 'rightbars'],
  'ta.valuewhen': ['condition', 'source', 'occurrence'],
  'ta.barssince': ['condition'],
  'ta.rising': ['source', 'length'], 'ta.falling': ['source', 'length'],
  'ta.median': ['source', 'length'], 'ta.percentrank': ['source', 'length'],
  'ta.range': ['source', 'length'],
  'ta.correlation': ['source1', 'source2', 'length'],
  'ta.cog': ['source', 'length'],
  'ta.max': ['source'], 'ta.min': ['source'],
  // math
  'math.abs': ['number'], 'math.sqrt': ['number'], 'math.log': ['number'],
  'math.log10': ['number'], 'math.exp': ['number'],
  'math.pow': ['base', 'exponent'], 'math.round': ['number', 'precision'],
  'math.floor': ['number'], 'math.ceil': ['number'], 'math.sign': ['number'],
  'math.sin': ['angle'], 'math.cos': ['angle'], 'math.tan': ['angle'],
  'math.asin': ['angle'], 'math.acos': ['angle'], 'math.atan': ['angle'],
  'math.todegrees': ['radians'], 'math.toradians': ['degrees'],
  'math.round_to_mintick': ['number'],
  'math.max': ['*'], 'math.min': ['*'], 'math.avg': ['*'],
  'math.sum': ['source', 'length'],
  // str
  'str.tostring': ['value', 'format'], 'str.tonumber': ['string'],
  'str.length': ['string'], 'str.contains': ['source', 'str'],
  'str.startswith': ['source', 'str'], 'str.endswith': ['source', 'str'],
  'str.upper': ['source'], 'str.lower': ['source'],
  'str.format': ['*'],
  // color
  'color.new': ['color', 'transp'],
  'color.rgb': ['red', 'green', 'blue', 'transp'],
  'color.from_gradient': [
    'value', 'bottom_value', 'top_value', 'bottom_color', 'top_color', //
  ],
  'color.r': ['color'], 'color.g': ['color'], 'color.b': ['color'],
  'color.t': ['color'],
  // zaman
  'timestamp': ['*'],
  'time': ['timeframe', 'session', 'timezone'],
  'time_close': ['timeframe', 'session', 'timezone'],
  'year': ['time', 'timezone'], 'month': ['time', 'timezone'],
  'dayofmonth': ['time', 'timezone'], 'dayofweek': ['time', 'timezone'],
  'hour': ['time', 'timezone'], 'minute': ['time', 'timezone'],
  'second': ['time', 'timezone'], 'weekofyear': ['time', 'timezone'],
  'timeframe.in_seconds': ['timeframe'],
  'timeframe.change': ['timeframe'],
};

/// Pine v3/v4 adları ve kısaltmalar → kanonik ad.
const Map<String, String> _takmaAdlar = {
  'study': 'indicator',
  'security': 'request.security',
  'tostring': 'str.tostring',
  'tonumber': 'str.tonumber',
  'sum': 'math.sum',
  'tickerid': 'ticker.new',
  'heikinashi': 'ticker.heikinashi',
  'renko': 'ticker.renko',
};

/// Çağrıları çalışan ama ekranda karşılığı olmayan alanlar.
const Set<String> _yoksayilanAlanlar = {
  'label', 'line', 'box', 'table', 'linefill', 'polyline', 'strategy', //
  'log', 'chart',
};

/// Yalnız en dış kapsamda çağrılabilen çıktı fonksiyonları (Pine kuralı).
const Set<String> _ciktiFonksiyonlari = {
  'plot', 'hline', 'plotshape', 'plotchar', 'plotarrow', 'fill', //
  'bgcolor', 'barcolor', 'plotcandle', 'plotbar', 'alertcondition',
};

String? _fonksiyonKanonik(String ad) {
  if (_imzalar.containsKey(ad)) return ad;
  final t = _takmaAdlar[ad];
  if (t != null) return t;
  final nokta = ad.indexOf('.');
  if (nokta > 0 && _yoksayilanAlanlar.contains(ad.substring(0, nokta))) {
    return ad;
  }
  if (nokta < 0) {
    // v4'te öneksiz max/min matematiktir (ta.max v5'te geldi).
    if (_imzalar.containsKey('math.$ad')) return 'math.$ad';
    if (_imzalar.containsKey('ta.$ad')) return 'ta.$ad';
  }
  return null;
}

/// Yerleşik değişkenler (çağrısız okunan adlar) → kanonik ad.
const Map<String, String> _yerlesikDegiskenler = {
  'open': 'open', 'high': 'high', 'low': 'low', 'close': 'close', //
  'volume': 'volume', 'hl2': 'hl2', 'hlc3': 'hlc3', 'hlcc4': 'hlcc4',
  'ohlc4': 'ohlc4', 'time': 'time', 'time_close': 'time_close',
  'time_tradingday': 'time_tradingday', 'timenow': 'timenow',
  'bar_index': 'bar_index', 'last_bar_index': 'last_bar_index',
  'last_bar_time': 'last_bar_time', 'n': 'bar_index',
  'year': 'year', 'month': 'month', 'dayofmonth': 'dayofmonth',
  'dayofweek': 'dayofweek', 'hour': 'hour', 'minute': 'minute',
  'second': 'second', 'weekofyear': 'weekofyear',
  'barstate.islast': 'barstate.islast',
  'barstate.isfirst': 'barstate.isfirst',
  'barstate.ishistory': 'barstate.ishistory',
  'barstate.isrealtime': 'barstate.isrealtime',
  'barstate.isconfirmed': 'barstate.isconfirmed',
  'barstate.isnew': 'barstate.isnew',
  'barstate.islastconfirmedhistory': 'barstate.islastconfirmedhistory',
  'timeframe.period': 'timeframe.period',
  'timeframe.main_period': 'timeframe.main_period',
  'timeframe.multiplier': 'timeframe.multiplier',
  'timeframe.isintraday': 'timeframe.isintraday',
  'timeframe.isminutes': 'timeframe.isminutes',
  'timeframe.isseconds': 'timeframe.isseconds',
  'timeframe.isticks': 'timeframe.isticks',
  'timeframe.isdaily': 'timeframe.isdaily',
  'timeframe.isweekly': 'timeframe.isweekly',
  'timeframe.ismonthly': 'timeframe.ismonthly',
  'timeframe.isdwm': 'timeframe.isdwm',
  'syminfo.ticker': 'syminfo.ticker', 'syminfo.tickerid': 'syminfo.tickerid',
  'syminfo.root': 'syminfo.root', 'syminfo.prefix': 'syminfo.prefix',
  'syminfo.description': 'syminfo.description',
  'syminfo.currency': 'syminfo.currency',
  'syminfo.basecurrency': 'syminfo.basecurrency',
  'syminfo.mintick': 'syminfo.mintick',
  'syminfo.pointvalue': 'syminfo.pointvalue',
  'syminfo.type': 'syminfo.type', 'syminfo.timezone': 'syminfo.timezone',
  'syminfo.session': 'syminfo.session',
  'math.pi': 'math.pi', 'math.e': 'math.e', 'math.phi': 'math.phi',
  'math.rphi': 'math.rphi',
  'ta.tr': 'ta.tr', 'ta.obv': 'ta.obv', 'ta.accdist': 'ta.accdist',
  'ta.pvt': 'ta.pvt', 'ta.vwap': 'ta.vwap',
  // v4
  'tr': 'ta.tr', 'obv': 'ta.obv', 'accdist': 'ta.accdist', 'pvt': 'ta.pvt',
  'vwap': 'ta.vwap', 'period': 'timeframe.period',
  'isintraday': 'timeframe.isintraday', 'isdaily': 'timeframe.isdaily',
  'isweekly': 'timeframe.isweekly', 'ismonthly': 'timeframe.ismonthly',
  'isdwm': 'timeframe.isdwm',
};

String? _degiskenKanonik(String ad) {
  final k = _yerlesikDegiskenler[ad];
  if (k != null) return k;
  if (ad.startsWith('strategy.')) return ad;
  return null;
}

/// Pine renk sabitleri (TradingView paleti).
const Map<String, _PineRenk> _renkSabitleri = {
  'aqua': _PineRenk(0x00, 0xBC, 0xD4), 'black': _PineRenk(0x36, 0x3A, 0x45),
  'blue': _PineRenk(0x21, 0x96, 0xF3), 'fuchsia': _PineRenk(0xE0, 0x40, 0xFB),
  'gray': _PineRenk(0x78, 0x7B, 0x86), 'green': _PineRenk(0x4C, 0xAF, 0x50),
  'lime': _PineRenk(0x00, 0xE6, 0x76), 'maroon': _PineRenk(0x88, 0x0E, 0x4F),
  'navy': _PineRenk(0x31, 0x1B, 0x92), 'olive': _PineRenk(0x80, 0x80, 0x00),
  'orange': _PineRenk(0xFF, 0x98, 0x00), 'purple': _PineRenk(0x9C, 0x27, 0xB0),
  'red': _PineRenk(0xFF, 0x52, 0x52), 'silver': _PineRenk(0xB2, 0xB5, 0xBE),
  'teal': _PineRenk(0x00, 0x89, 0x7B), 'white': _PineRenk(0xFF, 0xFF, 0xFF),
  'yellow': _PineRenk(0xFF, 0xEB, 0x3B),
};

/// Değeri kendi adı olan (dize) sabit alanları: `plot.style_histogram`,
/// `location.abovebar`, `shape.triangleup` …
const Set<String> _sabitAlanlari = {
  'plot', 'hline', 'shape', 'location', 'size', 'display', 'format', //
  'scale', 'extend', 'position', 'text', 'xloc', 'yloc', 'font', 'order',
  'currency', 'barmerge', 'session', 'label', 'line', 'alert', 'adjustment',
  'settlement_as_close', 'splits', 'dividends', 'earnings', 'input',
  'timeframe', 'backadjustment',
};

const Map<String, double> _gunSabitleri = {
  'sunday': 1, 'monday': 2, 'tuesday': 3, 'wednesday': 4, 'thursday': 5, //
  'friday': 6, 'saturday': 7,
};

/// Pine v2/v3 öneksiz sabitleri (`color=lime`, `style=histogram`,
/// `type=bool`). LazyBear gibi hâlâ çok kopyalanan eski göstergeler bunları
/// kullanır. Kullanıcı aynı adla değişken tanımlarsa onunki kazanır.
final Map<String, Object> _eskiSabitler = {
  for (final e in _renkSabitleri.entries) e.key: e.value,
  'histogram': 'plot.style_histogram', 'columns': 'plot.style_columns', //
  'area': 'plot.style_area', 'cross': 'plot.style_cross',
  'circles': 'plot.style_circles', 'linebr': 'plot.style_linebr',
  'stepline': 'plot.style_stepline', 'line': 'plot.style_line',
  'bool': 'input.bool', 'integer': 'input.integer', 'float': 'input.float',
  'source': 'input.source', 'resolution': 'input.resolution',
  'string': 'input.string', 'symbol': 'input.symbol',
  'session': 'input.session', 'dashed': 'hline.style_dashed',
  'dotted': 'hline.style_dotted', 'solid': 'hline.style_solid',
};

bool _sabitAdMi(String ad) {
  final nokta = ad.indexOf('.');
  if (nokta < 0) return _eskiSabitler.containsKey(ad);
  if (nokta == 0) return false;
  final ns = ad.substring(0, nokta);
  final uye = ad.substring(nokta + 1);
  if (ns == 'color') return _renkSabitleri.containsKey(uye);
  if (ns == 'dayofweek') return _gunSabitleri.containsKey(uye);
  return _sabitAlanlari.contains(ns) && !uye.contains('.');
}

Object _sabitDeger(String ad) {
  final nokta = ad.indexOf('.');
  if (nokta < 0) return _eskiSabitler[ad]!;
  final ns = ad.substring(0, nokta);
  final uye = ad.substring(nokta + 1);
  if (ns == 'color') return _renkSabitleri[uye]!;
  if (ns == 'dayofweek') return _gunSabitleri[uye]!;
  return ad;
}

// ─────────────────────────────────────────────────────────────────────────────
// Durum nesneleri
// ─────────────────────────────────────────────────────────────────────────────

/// Bir çağrı yerinin gördüğü değerler (çalıştığı her seferde bir tane).
class _Pencere {
  final List<double> v = [];
  int get uz => v.length;
  void ekle(double x) => v.add(x);
  double son(int k) => k < v.length ? v[v.length - 1 - k] : double.nan;
}

class _Ema {
  final _Pencere p = _Pencere();
  double? e;
}

class _Iki {
  double a = double.nan;
  double b = double.nan;
}

class _Sayac {
  double t = 0;
  double u = double.nan;
  int? son;
  int adet = 0;
  int? gun;
  double pv = 0;
  double v = 0;
}

class _Coklu {
  _Coklu(int emaSayisi, int pencereSayisi)
      : e = List.generate(emaSayisi, (_) => _Ema()),
        p = List.generate(pencereSayisi, (_) => _Pencere());
  final List<_Ema> e;
  final List<_Pencere> p;
  final List<double> d = List.filled(8, double.nan);
  int adet = 0;
  bool asagi = false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Uygulamalar
// ─────────────────────────────────────────────────────────────────────────────

extension _Yerlesik on _Yorumlayici {
  Object? _yerlesikCagri(_ICagri c, _Kapsam k) {
    final ad = c.ad;
    final nokta = ad.indexOf('.');
    final ns = nokta > 0 ? ad.substring(0, nokta) : '';
    if (_yoksayilanAlanlar.contains(ns)) {
      if (ns == 'strategy') {
        _notlar.add(BetikNotu.strateji);
      } else if (ns != 'log') {
        _notlar.add(BetikNotu.cizimNesnesi);
      }
      return double.nan;
    }
    switch (ad) {
      case 'indicator' || 'strategy' || 'alertcondition' || 'alert' ||
            'max_bars_back':
        return double.nan;
      case 'bgcolor' || 'barcolor' || 'plotcandle' || 'plotbar':
        _notlar.add(BetikNotu.boyama);
        return double.nan;
    }
    final imza = _imzalar[ad]!;
    final a = _bagla(c, k, imza);
    return _uygula(ad, a, c);
  }

  List<Object?> _bagla(_ICagri c, _Kapsam k, List<String> imza) {
    if (imza.length == 1 && imza.first == '*') {
      return [for (final x in c.arg) _e(x, k)];
    }
    if (c.arg.length > imza.length) {
      throw _hata('${c.ad} en fazla ${imza.length} değer alır.',
          '${c.ad} takes at most ${imza.length} arguments.', c.arg.last.j);
    }
    final out = List<Object?>.filled(imza.length, _yok);
    for (var i = 0; i < c.arg.length; i++) {
      out[i] = _e(c.arg[i], k);
    }
    for (final e in c.adli.entries) {
      final i = imza.indexOf(e.key);
      if (i >= 0) out[i] = _e(e.value, k);
    }
    return out;
  }

  int _uzunluk(Object? v, _Jeton j, String ad) {
    if (v is _Yok) {
      throw _hata('$ad için uzunluk eksik.', 'Missing length for $ad.', j);
    }
    final d = _Yorumlayici._sayi(v);
    if (d.isNaN) return -1;
    final l = d.round();
    if (l < 1 || l > kBetikAzamiUzunluk) {
      throw _hata('$ad uzunluğu 1 ile $kBetikAzamiUzunluk arasında olmalı.',
          '$ad length must be between 1 and $kBetikAzamiUzunluk.', j);
    }
    return l;
  }

  double _smaP(_Pencere p, int l, _Jeton j) {
    if (l < 1 || p.uz < l) return double.nan;
    _harca(l, j);
    var t = 0.0;
    for (var i = 0; i < l; i++) {
      final x = p.son(i);
      if (x.isNaN) return double.nan;
      t += x;
    }
    return t / l;
  }

  double _emaA(_Ema s, double x, int l, double alfa, _Jeton j) {
    s.p.ekle(x);
    if (s.e == null) {
      final m = _smaP(s.p, l, j);
      if (m.isNaN) return double.nan;
      s.e = m;
      return m;
    }
    if (x.isNaN) return double.nan;
    s.e = alfa * x + (1 - alfa) * s.e!;
    return s.e!;
  }

  double _rmaA(_Ema s, double x, int l, _Jeton j) =>
      l < 1 ? double.nan : _emaA(s, x, l, 1 / l, j);

  double _wmaP(_Pencere p, int l, _Jeton j) {
    if (l < 1 || p.uz < l) return double.nan;
    _harca(l, j);
    var t = 0.0;
    for (var i = 0; i < l; i++) {
      final x = p.son(i);
      if (x.isNaN) return double.nan;
      t += x * (l - i);
    }
    return t / (l * (l + 1) / 2);
  }

  double _stdevP(_Pencere p, int l, bool yanli, _Jeton j) {
    final m = _smaP(p, l, j);
    if (m.isNaN) return double.nan;
    var t = 0.0;
    for (var i = 0; i < l; i++) {
      final d = p.son(i) - m;
      t += d * d;
    }
    final b = yanli ? l : l - 1;
    return b <= 0 ? double.nan : t / b;
  }

  /// En yüksek/düşük ve kaç çubuk önce.
  (double, int) _ucP(_Pencere p, int l, bool enY, _Jeton j) {
    if (l < 1 || p.uz < l) return (double.nan, 0);
    _harca(l, j);
    var m = p.son(0);
    var yer = 0;
    for (var i = 0; i < l; i++) {
      final x = p.son(i);
      if (x.isNaN) return (double.nan, 0);
      if (enY ? x > m : x < m) {
        m = x;
        yer = i;
      }
    }
    return (m, yer);
  }

  double _toplamP(_Pencere p, int l, _Jeton j) {
    final m = _smaP(p, l, j);
    return m.isNaN ? m : m * l;
  }

  /// Zaman aralığı dizisi → dönem başı (ms). `time("D")` ve
  /// `timeframe.change("W")` için.
  double _donemBasi(String tf, int i) {
    if (tf.isEmpty || tf == veri.zamanDilimi) return veri.zamanlar[i];
    final z = _zaman(i);
    DateTime b;
    final dakika = int.tryParse(tf);
    if (dakika != null) {
      final gunDk = z.hour * 60 + z.minute;
      final bas = gunDk - gunDk % dakika;
      b = DateTime.utc(z.year, z.month, z.day, bas ~/ 60, bas % 60);
    } else if (tf.endsWith('D')) {
      b = DateTime.utc(z.year, z.month, z.day);
    } else if (tf.endsWith('W')) {
      final g = DateTime.utc(z.year, z.month, z.day);
      b = g.subtract(Duration(days: g.weekday - 1));
    } else if (tf.endsWith('M')) {
      b = DateTime.utc(z.year, z.month);
    } else {
      return veri.zamanlar[i];
    }
    return b.subtract(const Duration(hours: 3)).millisecondsSinceEpoch
        .toDouble();
  }

  Object? _uygula(String ad, List<Object?> a, _ICagri c) {
    final j = c.j;
    double s(int i) => i < a.length ? _Yorumlayici._sayi(a[i]) : double.nan;
    bool var_(int i) => i < a.length && a[i] is! _Yok;
    int u(int i) => _uzunluk(a[i], j, ad);
    String m(int i) => i < a.length ? _Yorumlayici._metin(a[i]) : '';
    final i0 = _i;

    switch (ad) {
      // ── Çıktı ──────────────────────────────────────────────────────────
      case 'plot':
        return _plot(a, c);
      case 'hline':
        if (!_yataylar.containsKey(c.id)) {
          final v = s(0);
          final gizli = m(6).contains('none');
          if (!v.isNaN && !gizli) {
            _yataylar[c.id] = _YatayKaydi(
                m(1), v, _Yorumlayici._renk(a[2])?.token);
          }
        }
        return _CizimKimligi('hline', c.id);
      case 'plotshape' || 'plotchar':
        _isaret(c.id, a, renkYeri: 4, varsayilanAd: 'İşaret');
        return double.nan;
      case 'plotarrow':
        final v = s(0);
        final yukari = _isaretler.putIfAbsent(
            c.id, () => _IsaretKaydi('${m(1).isEmpty ? 'Ok' : m(1)} ↑'));
        final asagi = _isaretler.putIfAbsent(
            -c.id, () => _IsaretKaydi('${m(1).isEmpty ? 'Ok' : m(1)} ↓'));
        if (v > 0) {
          yukari.indeksler.add(_i);
          final r = _Yorumlayici._renk(a[2])?.token ?? 'yesil';
          yukari.renkler[r] = (yukari.renkler[r] ?? 0) + 1;
        } else if (v < 0) {
          asagi.indeksler.add(_i);
          final r = _Yorumlayici._renk(a[3])?.token ?? 'kirmizi';
          asagi.renkler[r] = (asagi.renkler[r] ?? 0) + 1;
        }
        return double.nan;
      case 'fill':
        final p1 = a[0], p2 = a[1];
        if (p1 is _CizimKimligi && p2 is _CizimKimligi) {
          final r = _Yorumlayici._renk(a[2]) ??
              _Yorumlayici._renk(a[4]) ??
              _Yorumlayici._renk(a[9]);
          final eski = _dolgular[c.id];
          if (eski == null || (eski.renk == null && r != null)) {
            _dolgular[c.id] = _DolguKaydi(p1, p2, r?.token);
          }
        }
        return double.nan;

      // ── Girdi ──────────────────────────────────────────────────────────
      case 'input' || 'input.int' || 'input.float' || 'input.bool' ||
            'input.string' || 'input.color' || 'input.source' ||
            'input.timeframe' || 'input.session' || 'input.symbol' ||
            'input.price' || 'input.time' || 'input.text_area' ||
            'input.enum':
        if (!var_(0)) {
          throw _hata('$ad için varsayılan değer (defval) eksik.',
              'Missing default value (defval) for $ad.', j);
        }
        return a[0];

      // ── Veri ───────────────────────────────────────────────────────────
      case 'request.security':
        final sembol = m(0);
        final tf = m(1);
        final ayniSembol = sembol.isEmpty ||
            sembol == veri.sembol ||
            sembol == 'SANDIK:${veri.sembol}';
        final ayniAralik = tf.isEmpty ||
            tf == veri.zamanDilimi ||
            (tf == '1D' && veri.zamanDilimi == 'D') ||
            (tf == '1W' && veri.zamanDilimi == 'W') ||
            (tf == '1M' && veri.zamanDilimi == 'M');
        if (!ayniSembol || !ayniAralik) {
          throw _hata(
              'request.security yalnız açık grafiğin varlığı ve aralığıyla çalışır ('
                  '${ayniSembol ? 'aralık "$tf"' : 'sembol "$sembol"'} desteklenmiyor).',
              'request.security only works with the open chart\'s symbol and interval ('
                  '${ayniSembol ? 'interval "$tf"' : 'symbol "$sembol"'} is not supported).',
              j);
        }
        return a[2];
      case 'ticker.new' || 'ticker.standard' || 'ticker.modify':
        return 'SANDIK:${veri.sembol}';
      case 'ticker.heikinashi' || 'ticker.renko' || 'ticker.kagi' ||
            'ticker.linebreak' || 'ticker.pointfigure':
        return 'DONUSUM:${veri.sembol}';

      // ── Genel ──────────────────────────────────────────────────────────
      case 'na':
        return _Yorumlayici._na(a[0]);
      case 'nz':
        if (_Yorumlayici._na(a[0])) return var_(1) ? a[1] : 0.0;
        return a[0];
      case 'fixnan':
        final st = _durumAl(c.id, _Sayac.new);
        final v = s(0);
        if (!v.isNaN) st.u = v;
        return st.u;
      case 'iff':
        return _Yorumlayici._bool(a[0]) ? a[1] : a[2];
      case 'runtime.error':
        throw _hata(m(0), m(0), j);

      // ── Hareketli ortalamalar ──────────────────────────────────────────
      case 'ta.sma':
        final p = _durumAl(c.id, _Pencere.new)..ekle(s(0));
        return _smaP(p, u(1), j);
      case 'ta.ema':
        final l = u(1);
        return _emaA(_durumAl(c.id, _Ema.new), s(0), l, 2 / (l + 1), j);
      case 'ta.rma':
        return _rmaA(_durumAl(c.id, _Ema.new), s(0), u(1), j);
      case 'ta.wma':
        final p = _durumAl(c.id, _Pencere.new)..ekle(s(0));
        return _wmaP(p, u(1), j);
      case 'ta.vwma':
        final st = _durumAl(c.id, () => _Coklu(0, 2));
        final h = _hc(i0);
        st.p[0].ekle(s(0) * h);
        st.p[1].ekle(h);
        final l = u(1);
        final pay = _smaP(st.p[0], l, j), payda = _smaP(st.p[1], l, j);
        return payda == 0 ? double.nan : pay / payda;
      case 'ta.hma':
        final st = _durumAl(c.id, () => _Coklu(0, 2));
        final l = u(1);
        if (l < 0) return double.nan;
        st.p[0].ekle(s(0));
        final yarim = math.max(1, l ~/ 2);
        st.p[1].ekle(
            2 * _wmaP(st.p[0], yarim, j) - _wmaP(st.p[0], l, j));
        return _wmaP(st.p[1], math.max(1, math.sqrt(l).floor()), j);
      case 'ta.swma':
        final p = _durumAl(c.id, _Pencere.new)..ekle(s(0));
        if (p.uz < 4) return double.nan;
        return (p.son(3) + 2 * p.son(2) + 2 * p.son(1) + p.son(0)) / 6;
      case 'ta.alma':
        final p = _durumAl(c.id, _Pencere.new)..ekle(s(0));
        final l = u(1);
        if (l < 1 || p.uz < l) return double.nan;
        final ofs = var_(2) ? s(2) : 0.85;
        final sig = var_(3) ? s(3) : 6.0;
        var mm = ofs * (l - 1);
        if (var_(4) && _Yorumlayici._bool(a[4])) mm = mm.floorToDouble();
        final ss = l / sig;
        var t = 0.0, w = 0.0;
        _harca(l, j);
        for (var i = 0; i < l; i++) {
          final ag = math.exp(-((i - mm) * (i - mm)) / (2 * ss * ss));
          t += ag * p.son(l - 1 - i);
          w += ag;
        }
        return t / w;
      case 'ta.linreg':
        final p = _durumAl(c.id, _Pencere.new)..ekle(s(0));
        final l = u(1);
        if (l < 1 || p.uz < l) return double.nan;
        _harca(l, j);
        var sx = 0.0, sy = 0.0, sxy = 0.0, sxx = 0.0;
        for (var i = 0; i < l; i++) {
          final y = p.son(l - 1 - i);
          if (y.isNaN) return double.nan;
          sx += i;
          sy += y;
          sxy += i * y;
          sxx += i * i;
        }
        final payda = l * sxx - sx * sx;
        final egim = payda == 0 ? 0.0 : (l * sxy - sx * sy) / payda;
        final kes = (sy - egim * sx) / l;
        return kes + egim * (l - 1 - (var_(2) ? s(2) : 0));

      // ── Osilatörler ────────────────────────────────────────────────────
      case 'ta.rsi':
        final st = _durumAl(c.id, () => _Coklu(2, 0));
        final x = s(0);
        final d = x - st.d[0];
        st.d[0] = x;
        final l = u(1);
        final yu = _rmaA(st.e[0], d.isNaN ? double.nan : math.max(d, 0), l, j);
        final as = _rmaA(st.e[1], d.isNaN ? double.nan : math.max(-d, 0), l, j);
        if (yu.isNaN || as.isNaN) return double.nan;
        if (as == 0) return 100.0;
        if (yu == 0) return 0.0;
        return 100 - 100 / (1 + yu / as);
      case 'ta.stdev' || 'ta.variance':
        final p = _durumAl(c.id, _Pencere.new)..ekle(s(0));
        final yanli = !var_(2) || _Yorumlayici._bool(a[2]);
        final v = _stdevP(p, u(1), yanli, j);
        return ad == 'ta.stdev' ? math.sqrt(v) : v;
      case 'ta.dev':
        final p = _durumAl(c.id, _Pencere.new)..ekle(s(0));
        final l = u(1);
        final ort = _smaP(p, l, j);
        if (ort.isNaN) return double.nan;
        var t = 0.0;
        for (var i = 0; i < l; i++) {
          t += (p.son(i) - ort).abs();
        }
        return t / l;
      case 'ta.highest' || 'ta.lowest' || 'ta.highestbars' ||
            'ta.lowestbars':
        final enY = ad.contains('highest');
        final p = _durumAl(c.id, _Pencere.new);
        final int l;
        if (!var_(1)) {
          p.ekle(enY ? _yk(i0) : _ds(i0));
          l = u(0);
        } else {
          p.ekle(s(0));
          l = u(1);
        }
        final (v, yer) = _ucP(p, l, enY, j);
        if (ad.endsWith('bars')) return v.isNaN ? v : -yer.toDouble();
        return v;
      case 'ta.change' || 'ta.mom' || 'ta.roc':
        final p = _durumAl(c.id, _Pencere.new);
        final mantik = a[0] is bool;
        final x = s(0);
        p.ekle(x);
        final l = var_(1) ? u(1) : 1;
        if (l < 0) return double.nan;
        final once = p.son(l);
        if (mantik) return !once.isNaN && once != x;
        if (ad == 'ta.roc') {
          return once == 0 || once.isNaN ? double.nan : 100 * (x - once) / once;
        }
        return x - once;
      case 'ta.cross' || 'ta.crossover' || 'ta.crossunder':
        final st = _durumAl(c.id, _Iki.new);
        final x = s(0), y = s(1);
        final ust = x > y && st.a <= st.b;
        final alt = x < y && st.a >= st.b;
        st.a = x;
        st.b = y;
        return switch (ad) {
          'ta.crossover' => ust,
          'ta.crossunder' => alt,
          _ => ust || alt,
        };
      case 'ta.atr':
        return _rmaA(_durumAl(c.id, _Ema.new), _trAt(i0, true), u(0), j);
      case 'ta.tr':
        return _trAt(i0, var_(0) && _Yorumlayici._bool(a[0]));
      case 'ta.cum':
        final st = _durumAl(c.id, _Sayac.new);
        final x = s(0);
        if (!x.isNaN) st.t += x;
        return st.t;
      case 'math.sum':
        final p = _durumAl(c.id, _Pencere.new)..ekle(s(0));
        return _toplamP(p, u(1), j);
      case 'ta.macd':
        final st = _durumAl(c.id, () => _Coklu(3, 0));
        final f = u(1), y = u(2), g = u(3);
        final x = s(0);
        final hizli = _emaA(st.e[0], x, f, 2 / (f + 1), j);
        final yavas = _emaA(st.e[1], x, y, 2 / (y + 1), j);
        final macd = hizli - yavas;
        final sinyal = _emaA(st.e[2], macd, g, 2 / (g + 1), j);
        return [macd, sinyal, macd - sinyal];
      case 'ta.bb' || 'ta.bbw':
        final p = _durumAl(c.id, _Pencere.new)..ekle(s(0));
        final l = u(1);
        final orta = _smaP(p, l, j);
        final sapma = s(2) * math.sqrt(_stdevP(p, l, true, j));
        if (ad == 'ta.bbw') {
          return orta == 0 ? double.nan : (2 * sapma) / orta;
        }
        return [orta, orta + sapma, orta - sapma];
      case 'ta.kc' || 'ta.kcw':
        final st = _durumAl(c.id, () => _Coklu(2, 0));
        final l = u(1);
        final orta = _emaA(st.e[0], s(0), l, 2 / (l + 1), j);
        final gercek = !var_(3) || _Yorumlayici._bool(a[3]);
        final aralik = gercek ? _trAt(i0, true) : _yk(i0) - _ds(i0);
        final ar = _emaA(st.e[1], aralik, l, 2 / (l + 1), j);
        final ust = orta + s(2) * ar, alt = orta - s(2) * ar;
        if (ad == 'ta.kcw') return orta == 0 ? double.nan : (ust - alt) / orta;
        return [orta, ust, alt];
      case 'ta.stoch':
        final st = _durumAl(c.id, () => _Coklu(0, 2));
        st.p[0].ekle(s(1));
        st.p[1].ekle(s(2));
        final l = u(3);
        final (hh, _) = _ucP(st.p[0], l, true, j);
        final (ll, _) = _ucP(st.p[1], l, false, j);
        if (hh.isNaN || ll.isNaN || hh == ll) return double.nan;
        return 100 * (s(0) - ll) / (hh - ll);
      case 'ta.cci':
        final p = _durumAl(c.id, _Pencere.new)..ekle(s(0));
        final l = u(1);
        final ort = _smaP(p, l, j);
        if (ort.isNaN) return double.nan;
        var t = 0.0;
        for (var i = 0; i < l; i++) {
          t += (p.son(i) - ort).abs();
        }
        final dev = t / l;
        return dev == 0 ? 0.0 : (p.son(0) - ort) / (0.015 * dev);
      case 'ta.mfi':
        final st = _durumAl(c.id, () => _Coklu(0, 2));
        final x = s(0);
        final d = x - st.d[0];
        st.d[0] = x;
        final h = _hc(i0);
        st.p[0].ekle(d.isNaN ? double.nan : (d > 0 ? h * x : 0));
        st.p[1].ekle(d.isNaN ? double.nan : (d < 0 ? h * x : 0));
        final l = u(1);
        final ust = _toplamP(st.p[0], l, j), alt = _toplamP(st.p[1], l, j);
        if (ust.isNaN || alt.isNaN) return double.nan;
        if (alt == 0) return 100.0;
        return 100 - 100 / (1 + ust / alt);
      case 'ta.wpr':
        final st = _durumAl(c.id, () => _Coklu(0, 2));
        st.p[0].ekle(_yk(i0));
        st.p[1].ekle(_ds(i0));
        final l = u(0);
        final (hh, _) = _ucP(st.p[0], l, true, j);
        final (ll, _) = _ucP(st.p[1], l, false, j);
        if (hh.isNaN || ll.isNaN || hh == ll) return double.nan;
        return 100 * (_kp(i0) - hh) / (hh - ll);
      case 'ta.cmo':
        final st = _durumAl(c.id, () => _Coklu(0, 2));
        final x = s(0);
        final d = x - st.d[0];
        st.d[0] = x;
        st.p[0].ekle(d.isNaN ? double.nan : math.max(d, 0));
        st.p[1].ekle(d.isNaN ? double.nan : math.max(-d, 0));
        final l = u(1);
        final yu = _toplamP(st.p[0], l, j), as = _toplamP(st.p[1], l, j);
        if (yu.isNaN || as.isNaN || yu + as == 0) return double.nan;
        return 100 * (yu - as) / (yu + as);
      case 'ta.tsi':
        final st = _durumAl(c.id, () => _Coklu(4, 0));
        final x = s(0);
        final d = x - st.d[0];
        st.d[0] = x;
        final kisa = u(1), uzun = u(2);
        final e1 = _emaA(st.e[0], d, uzun, 2 / (uzun + 1), j);
        final e2 = _emaA(st.e[1], e1, kisa, 2 / (kisa + 1), j);
        final a1 = _emaA(st.e[2], d.abs(), uzun, 2 / (uzun + 1), j);
        final a2 = _emaA(st.e[3], a1, kisa, 2 / (kisa + 1), j);
        return a2 == 0 ? double.nan : e2 / a2;
      case 'ta.vwap':
        final st = _durumAl(c.id, _Sayac.new);
        final z = _zaman(i0);
        final g = z.year * 400 + z.month * 32 + z.day;
        if (g != st.gun) {
          st.gun = g;
          st.pv = 0;
          st.v = 0;
        }
        final h = _hc(i0);
        st.pv += s(0) * h;
        st.v += h;
        return st.v == 0 ? double.nan : st.pv / st.v;
      case 'ta.dmi':
        final st = _durumAl(c.id, () => _Coklu(4, 0));
        final di = u(0), adxL = u(1);
        final h = _yk(i0), l = _ds(i0);
        final yukari = h - st.d[0], asagi = st.d[1] - l;
        st.d[0] = h;
        st.d[1] = l;
        final artiDm = yukari.isNaN
            ? double.nan
            : (yukari > asagi && yukari > 0 ? yukari : 0.0);
        final eksiDm = asagi.isNaN
            ? double.nan
            : (asagi > yukari && asagi > 0 ? asagi : 0.0);
        final tr = _rmaA(st.e[0], _trAt(i0, true), di, j);
        final arti = 100 * _rmaA(st.e[1], artiDm, di, j) / tr;
        final eksi = 100 * _rmaA(st.e[2], eksiDm, di, j) / tr;
        final top = arti + eksi;
        final adx = 100 *
            _rmaA(st.e[3], (arti - eksi).abs() / (top == 0 ? 1 : top), adxL,
                j);
        return [arti, eksi, adx];
      case 'ta.supertrend':
        return _supertrend(c, s(0), u(1));
      case 'ta.sar':
        return _sar(c, s(0), s(1), s(2));
      case 'ta.pivothigh' || 'ta.pivotlow':
        final enY = ad == 'ta.pivothigh';
        final p = _durumAl(c.id, _Pencere.new);
        final int sol, sag;
        if (!var_(2)) {
          p.ekle(enY ? _yk(i0) : _ds(i0));
          sol = u(0);
          sag = u(1);
        } else {
          p.ekle(s(0));
          sol = u(1);
          sag = u(2);
        }
        if (p.uz < sol + sag + 1) return double.nan;
        final orta = p.son(sag);
        if (orta.isNaN) return double.nan;
        _harca(sol + sag, j);
        for (var i = 0; i <= sol + sag; i++) {
          if (i == sag) continue;
          final v = p.son(i);
          if (v.isNaN || (enY ? v >= orta : v <= orta)) return double.nan;
        }
        return orta;
      case 'ta.valuewhen':
        final p = _durumAl(c.id, _Pencere.new);
        if (_Yorumlayici._bool(a[0])) p.ekle(s(1));
        final o = var_(2) ? s(2).round() : 0;
        return p.son(o);
      case 'ta.barssince':
        final st = _durumAl(c.id, _Sayac.new);
        st.adet++;
        if (_Yorumlayici._bool(a[0])) st.son = st.adet;
        return st.son == null ? double.nan : (st.adet - st.son!).toDouble();
      case 'ta.rising' || 'ta.falling':
        final p = _durumAl(c.id, _Pencere.new)..ekle(s(0));
        final l = u(1);
        if (l < 1 || p.uz <= l) return false;
        final x = p.son(0);
        for (var i = 1; i <= l; i++) {
          final v = p.son(i);
          if (ad == 'ta.rising' ? !(x > v) : !(x < v)) return false;
        }
        return true;
      case 'ta.median' || 'ta.percentrank' || 'ta.range':
        final p = _durumAl(c.id, _Pencere.new)..ekle(s(0));
        final l = u(1);
        if (l < 1 || p.uz < l + (ad == 'ta.percentrank' ? 1 : 0)) {
          return double.nan;
        }
        _harca(l, j);
        if (ad == 'ta.percentrank') {
          final x = p.son(0);
          var say = 0;
          for (var i = 1; i <= l; i++) {
            if (p.son(i) <= x) say++;
          }
          return 100 * say / l;
        }
        final w = [for (var i = 0; i < l; i++) p.son(i)];
        if (w.any((v) => v.isNaN)) return double.nan;
        w.sort();
        if (ad == 'ta.range') return w.last - w.first;
        return l.isOdd ? w[l ~/ 2] : (w[l ~/ 2 - 1] + w[l ~/ 2]) / 2;
      case 'ta.correlation':
        final st = _durumAl(c.id, () => _Coklu(0, 2));
        st.p[0].ekle(s(0));
        st.p[1].ekle(s(1));
        final l = u(2);
        final ma = _smaP(st.p[0], l, j), mb = _smaP(st.p[1], l, j);
        if (ma.isNaN || mb.isNaN) return double.nan;
        var sab = 0.0, saa = 0.0, sbb = 0.0;
        for (var i = 0; i < l; i++) {
          final da = st.p[0].son(i) - ma, db = st.p[1].son(i) - mb;
          sab += da * db;
          saa += da * da;
          sbb += db * db;
        }
        final payda = math.sqrt(saa * sbb);
        return payda == 0 ? double.nan : sab / payda;
      case 'ta.cog':
        final p = _durumAl(c.id, _Pencere.new)..ekle(s(0));
        final l = u(1);
        if (l < 1 || p.uz < l) return double.nan;
        var pay = 0.0, payda = 0.0;
        for (var i = 0; i < l; i++) {
          pay += p.son(i) * (i + 1);
          payda += p.son(i);
        }
        return payda == 0 ? double.nan : -pay / payda;
      case 'ta.max' || 'ta.min':
        final st = _durumAl(c.id, _Sayac.new);
        final x = s(0);
        if (!x.isNaN &&
            (st.u.isNaN || (ad == 'ta.max' ? x > st.u : x < st.u))) {
          st.u = x;
        }
        return st.u;

      // ── math ───────────────────────────────────────────────────────────
      case 'math.abs':
        return s(0).abs();
      case 'math.sqrt':
        return s(0) < 0 ? double.nan : math.sqrt(s(0));
      case 'math.log':
        return s(0) <= 0 ? double.nan : math.log(s(0));
      case 'math.log10':
        return s(0) <= 0 ? double.nan : math.log(s(0)) / math.ln10;
      case 'math.exp':
        return math.exp(s(0));
      case 'math.pow':
        return math.pow(s(0), s(1)).toDouble();
      case 'math.round':
        final x = s(0);
        if (x.isNaN) return x;
        if (!var_(1)) return x.roundToDouble();
        final k = math.pow(10, s(1).round()).toDouble();
        return (x * k).roundToDouble() / k;
      case 'math.floor':
        return s(0).isNaN ? s(0) : s(0).floorToDouble();
      case 'math.ceil':
        return s(0).isNaN ? s(0) : s(0).ceilToDouble();
      case 'math.sign':
        return s(0).isNaN ? s(0) : s(0).sign;
      case 'math.sin':
        return math.sin(s(0));
      case 'math.cos':
        return math.cos(s(0));
      case 'math.tan':
        return math.tan(s(0));
      case 'math.asin':
        return math.asin(s(0));
      case 'math.acos':
        return math.acos(s(0));
      case 'math.atan':
        return math.atan(s(0));
      case 'math.todegrees':
        return s(0) * 180 / math.pi;
      case 'math.toradians':
        return s(0) * math.pi / 180;
      case 'math.round_to_mintick':
        return (s(0) * 100).roundToDouble() / 100;
      case 'math.max' || 'math.min' || 'math.avg':
        if (a.isEmpty) {
          throw _hata('$ad en az bir değer alır.',
              '$ad takes at least one argument.', j);
        }
        final v = [for (var i = 0; i < a.length; i++) s(i)];
        if (v.any((x) => x.isNaN)) return double.nan;
        return switch (ad) {
          'math.max' => v.reduce(math.max),
          'math.min' => v.reduce(math.min),
          _ => v.reduce((x, y) => x + y) / v.length,
        };

      // ── str ────────────────────────────────────────────────────────────
      case 'str.tostring':
        return m(0);
      case 'str.tonumber':
        return double.tryParse(m(0)) ?? double.nan;
      case 'str.length':
        return m(0).length.toDouble();
      case 'str.contains':
        return m(0).contains(m(1));
      case 'str.startswith':
        return m(0).startsWith(m(1));
      case 'str.endswith':
        return m(0).endsWith(m(1));
      case 'str.upper':
        return m(0).toUpperCase();
      case 'str.lower':
        return m(0).toLowerCase();
      case 'str.format':
        var f = m(0);
        for (var i = 1; i < a.length; i++) {
          f = f.replaceAll(RegExp('\\{${i - 1}(,[^}]*)?\\}'), m(i));
        }
        return f;

      // ── color ──────────────────────────────────────────────────────────
      case 'color.new':
        final r = _Yorumlayici._renk(a[0]);
        return r?.saydam(var_(1) ? s(1) : r.t) ?? double.nan;
      case 'color.rgb':
        int b(double x) => x.isNaN ? 0 : x.round().clamp(0, 255);
        return _PineRenk(b(s(0)), b(s(1)), b(s(2)), var_(3) ? s(3) : 0);
      case 'color.from_gradient':
        final v = s(0), alt = s(1), ust = s(2);
        if (v.isNaN) return double.nan;
        final oran = ust == alt ? 1.0 : (v - alt) / (ust - alt);
        return oran < 0.5 ? a[3] : a[4];
      case 'color.r' || 'color.g' || 'color.b' || 'color.t':
        final r = _Yorumlayici._renk(a[0]);
        if (r == null) return double.nan;
        return switch (ad) {
          'color.r' => r.r.toDouble(),
          'color.g' => r.g.toDouble(),
          'color.b' => r.b.toDouble(),
          _ => r.t,
        };

      // ── zaman ──────────────────────────────────────────────────────────
      case 'timestamp':
        final say = [
          for (final x in a)
            if (x is! String) _Yorumlayici._sayi(x)
        ];
        if (say.length < 3) {
          if (a.isNotEmpty && a.last is String) {
            final t = DateTime.tryParse(a.last as String);
            if (t != null) return t.millisecondsSinceEpoch.toDouble();
          }
          throw _hata('timestamp(yıl, ay, gün, …) bekleniyordu.',
              'Expected timestamp(year, month, day, …).', j);
        }
        int v(int i) => i < say.length && !say[i].isNaN ? say[i].round() : 0;
        return DateTime.utc(v(0), v(1), v(2), v(3), v(4), v(5))
            .subtract(const Duration(hours: 3))
            .millisecondsSinceEpoch
            .toDouble();
      case 'time' || 'time_close':
        if (var_(1) && m(1).isNotEmpty) {
          throw _hata('Seans (session) filtresi desteklenmiyor.',
              'Session filters are not supported.', j);
        }
        return _donemBasi(var_(0) ? m(0) : '', i0);
      case 'year' || 'month' || 'dayofmonth' || 'dayofweek' || 'hour' ||
            'minute' || 'second' || 'weekofyear':
        final t = s(0);
        if (t.isNaN) return double.nan;
        final z = DateTime.fromMillisecondsSinceEpoch(t.toInt(), isUtc: true)
            .add(const Duration(hours: 3));
        return switch (ad) {
          'year' => z.year,
          'month' => z.month,
          'dayofmonth' => z.day,
          'dayofweek' => z.weekday % 7 + 1,
          'hour' => z.hour,
          'minute' => z.minute,
          'second' => z.second,
          _ => z.difference(DateTime.utc(z.year)).inDays ~/ 7 + 1,
        }
            .toDouble();
      case 'timeframe.in_seconds':
        final tf = var_(0) ? m(0) : veri.zamanDilimi;
        final dk = int.tryParse(tf);
        if (dk != null) return dk * 60.0;
        final kat = int.tryParse(tf.replaceAll(RegExp('[A-Za-z]'), '')) ?? 1;
        if (tf.endsWith('D')) return kat * 86400.0;
        if (tf.endsWith('W')) return kat * 604800.0;
        if (tf.endsWith('M')) return kat * 2628003.0;
        return double.nan;
      case 'timeframe.change':
        if (i0 == 0) return true;
        return _donemBasi(m(0), i0) != _donemBasi(m(0), i0 - 1);
    }
    throw _hata("'$ad' henüz desteklenmiyor.", "'$ad' is not supported yet.",
        j);
  }

  Object? _plot(List<Object?> a, _ICagri c) {
    final kayit = _cizgiler.putIfAbsent(c.id, () => _CizgiKaydi(n));
    final baslik = a[1];
    if (kayit.ad == null && baslik is String && baslik.isNotEmpty) {
      kayit.ad = baslik;
    }
    var v = _Yorumlayici._sayi(a[0]);
    if (a[2] is! _Yok) {
      kayit.renkVerildi = true;
      final r = _Yorumlayici._renk(a[2]);
      if (r == null) {
        v = double.nan;
      } else {
        kayit.renkler[_i] = r.token;
        if (!r.gorunmez) kayit.hepsiSaydam = false;
      }
    }
    kayit.degerler[_i] = v;
    {
      final w = _Yorumlayici._sayi(a[3]);
      if (!w.isNaN) kayit.kalinlik = 1.2 + (w.clamp(1, 4) - 1) * 0.6;
      final stil = _Yorumlayici._metin(a[4]);
      kayit.stil = switch (stil) {
        'plot.style_histogram' || 'plot.style_columns' =>
          BetikCizgiStili.histogram,
        'plot.style_area' || 'plot.style_areabr' => BetikCizgiStili.alan,
        'plot.style_circles' || 'plot.style_cross' => BetikCizgiStili.nokta,
        _ => BetikCizgiStili.cizgi,
      };
      final ofs = _Yorumlayici._sayi(a[7]);
      if (!ofs.isNaN) kayit.kayma = ofs.round();
      final gor = _Yorumlayici._metin(a[11]);
      kayit.gizli = gor == 'display.none' ||
          gor == 'display.data_window' ||
          gor == 'display.status_line' ||
          gor == 'display.price_scale';
    }
    return _CizimKimligi('plot', c.id);
  }

  void _isaret(int id, List<Object?> a,
      {required int renkYeri, required String varsayilanAd}) {
    final m = _isaretler.putIfAbsent(id, () {
      final b = _Yorumlayici._metin(a[1]);
      return _IsaretKaydi(
          b.isEmpty ? '$varsayilanAd ${_isaretler.length + 1}' : b);
    });
    final konum = _Yorumlayici._metin(a[3]);
    var acik = konum == 'location.absolute'
        ? !_Yorumlayici._sayi(a[0]).isNaN
        : _Yorumlayici._bool(a[0]);
    String? renk;
    if (a[renkYeri] is! _Yok) {
      final r = _Yorumlayici._renk(a[renkYeri]);
      if (r == null || r.gorunmez) {
        acik = false;
      } else {
        renk = r.token;
      }
    }
    if (!acik) return;
    m.indeksler.add(_i);
    if (renk != null) m.renkler[renk] = (m.renkler[renk] ?? 0) + 1;
  }

  List<double> _supertrend(_ICagri c, double faktor, int atrL) {
    final st = _durumAl(c.id, () => _Coklu(1, 0));
    final j = c.j;
    final i = _i;
    final orta = (_yk(i) + _ds(i)) / 2;
    final atr = _rmaA(st.e[0], _trAt(i, true), atrL, j);
    var ust = orta + faktor * atr;
    var alt = orta - faktor * atr;
    final oncekiAlt = st.d[0].isNaN ? 0.0 : st.d[0];
    final oncekiUst = st.d[1].isNaN ? 0.0 : st.d[1];
    final oncekiKapanis = i > 0 ? _kp(i - 1) : double.nan;
    alt = alt > oncekiAlt || oncekiKapanis < oncekiAlt ? alt : oncekiAlt;
    ust = ust < oncekiUst || oncekiKapanis > oncekiUst ? ust : oncekiUst;
    final oncekiSt = st.d[2];
    double yon;
    if (st.d[3].isNaN) {
      yon = 1;
    } else if (oncekiSt == oncekiUst) {
      yon = _kp(i) > ust ? -1 : 1;
    } else {
      yon = _kp(i) < alt ? 1 : -1;
    }
    final sonuc = yon == -1 ? alt : ust;
    st.d[0] = alt;
    st.d[1] = ust;
    st.d[2] = sonuc;
    st.d[3] = atr;
    return [atr.isNaN ? double.nan : sonuc, atr.isNaN ? double.nan : yon];
  }

  double _sar(_ICagri c, double bas, double artis, double azami) {
    // Pine başvurusundaki pine_sar ile aynı adımlar. d: [sonuc, uc, ivme].
    final st = _durumAl(c.id, () => _Coklu(0, 0));
    final i = _i;
    st.adet++;
    final sira = st.adet - 1;
    if (sira == 0) return double.nan;
    var ilkTrend = false;
    if (sira == 1) {
      if (_kp(i) > _kp(i - 1)) {
        st.asagi = true;
        st.d[1] = _yk(i);
        st.d[0] = _ds(i - 1);
      } else {
        st.asagi = false;
        st.d[1] = _ds(i);
        st.d[0] = _yk(i - 1);
      }
      ilkTrend = true;
      st.d[2] = bas;
    }
    var sonuc = st.d[0] + st.d[2] * (st.d[1] - st.d[0]);
    if (st.asagi) {
      if (sonuc > _ds(i)) {
        ilkTrend = true;
        st.asagi = false;
        sonuc = math.max(_yk(i), st.d[1]);
        st.d[1] = _ds(i);
        st.d[2] = bas;
      }
    } else {
      if (sonuc < _yk(i)) {
        ilkTrend = true;
        st.asagi = true;
        sonuc = math.min(_ds(i), st.d[1]);
        st.d[1] = _yk(i);
        st.d[2] = bas;
      }
    }
    if (!ilkTrend) {
      if (st.asagi) {
        if (_yk(i) > st.d[1]) {
          st.d[1] = _yk(i);
          st.d[2] = math.min(st.d[2] + artis, azami);
        }
      } else if (_ds(i) < st.d[1]) {
        st.d[1] = _ds(i);
        st.d[2] = math.min(st.d[2] + artis, azami);
      }
    }
    if (st.asagi) {
      sonuc = math.min(sonuc, _ds(i - 1));
      if (sira > 1) sonuc = math.min(sonuc, _ds(i - 2));
    } else {
      sonuc = math.max(sonuc, _yk(i - 1));
      if (sira > 1) sonuc = math.max(sonuc, _yk(i - 2));
    }
    st.d[0] = sonuc;
    return sonuc;
  }
}
