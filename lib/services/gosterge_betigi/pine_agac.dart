part of 'betik.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sözdizimi ağacı
// ─────────────────────────────────────────────────────────────────────────────

sealed class _I {
  _I(this.j);
  final _Jeton j;
}

class _ISayi extends _I {
  _ISayi(super.j, this.v);
  final double v;
}

class _IMetin extends _I {
  _IMetin(super.j, this.v);
  final String v;
}

class _IBool extends _I {
  _IBool(super.j, this.v);
  final bool v;
}

class _INa extends _I {
  _INa(super.j);
}

class _IRenk extends _I {
  _IRenk(super.j, this.renk);
  final _PineRenk renk;
}

/// Ad: kullanıcı değişkeni ya da yerleşik (`close`, `barstate.islast`,
/// `color.red`, `plot.style_histogram`).
class _IAd extends _I {
  _IAd(super.j, this.ad);
  final String ad;
}

class _ITekli extends _I {
  _ITekli(super.j, this.op, this.e);
  final String op;
  final _I e;
}

class _IIkili extends _I {
  _IIkili(super.j, this.op, this.a, this.b);
  final String op;
  final _I a;
  final _I b;
}

class _IKosul extends _I {
  _IKosul(super.j, this.k, this.a, this.b);
  final _I k;
  final _I a;
  final _I b;
}

/// `e[n]` — geçmiş. [id] çağrı bağlamı başına tampon anahtarı.
class _IGecmis extends _I {
  _IGecmis(super.j, this.e, this.n, this.id);
  final _I e;
  final _I n;
  final int id;
}

class _ICagri extends _I {
  _ICagri(super.j, this.ad, this.arg, this.adli, this.id);

  /// Kanonik ad (yerleşikse `ta.sma`; kullanıcı fonksiyonuysa kendi adı).
  final String ad;
  final List<_I> arg;
  final Map<String, _I> adli;
  final int id;

  /// Kullanıcı fonksiyonu mu (ayrıştırma anında bilinir).
  bool kullanici = false;
}

/// `[a, b, c]` — demet dönüşü ya da `options=[...]`.
class _IDizi extends _I {
  _IDizi(super.j, this.elemanlar);
  final List<_I> elemanlar;
}

/// `if` yapısı (deyim ya da ifade). [kosullar].length == [bloklar].length;
/// [degilse] son `else`.
class _IEger extends _I {
  _IEger(super.j, this.kosullar, this.bloklar, this.degilse);
  final List<_I> kosullar;
  final List<List<_D>> bloklar;
  final List<_D>? degilse;
}

/// `switch` yapısı. [konu] null → her durum bir koşul. Durumun koşulu null
/// → varsayılan (`=> …`).
class _ISec extends _I {
  _ISec(super.j, this.konu, this.durumlar);
  final _I? konu;
  final List<(_I?, List<_D>)> durumlar;
}

sealed class _D {
  _D(this.j);
  final _Jeton j;
}

class _DBildir extends _D {
  _DBildir(super.j, this.ad, this.e, this.kalici, this.id);
  final String ad;
  final _I e;

  /// `var` / `varip`: yalnız ilk çubukta değerlendirilir.
  final bool kalici;
  final int id;
}

class _DDemet extends _D {
  _DDemet(super.j, this.adlar, this.e, this.id);
  final List<String> adlar;
  final _I e;
  final int id;
}

class _DAta extends _D {
  _DAta(super.j, this.ad, this.op, this.e);
  final String ad;

  /// ':=', '+=', '-=', '*=', '/=', '%='
  final String op;
  final _I e;
}

class _DIfade extends _D {
  _DIfade(super.j, this.e);
  final _I e;
}

class _DFor extends _D {
  _DFor(super.j, this.ad, this.bas, this.son, this.adim, this.blok, this.id);
  final String ad;
  final _I bas;
  final _I son;
  final _I? adim;
  final List<_D> blok;
  final int id;
}

class _DWhile extends _D {
  _DWhile(super.j, this.kosul, this.blok);
  final _I kosul;
  final List<_D> blok;
}

class _DKir extends _D {
  _DKir(super.j);
}

class _DDevam extends _D {
  _DDevam(super.j);
}

class _Fonksiyon {
  _Fonksiyon(this.ad, this.parametreler, this.govde, this.j, this.id);
  final String ad;
  final List<(String, _I?)> parametreler;
  final List<_D> govde;
  final _Jeton j;
  final int id;
}

class _Program {
  _Program({
    required this.deyimler,
    required this.fonksiyonlar,
    required this.fiyatUstunde,
    required this.baslik,
    required this.cizgiSayisi,
  });
  final List<_D> deyimler;
  final Map<String, _Fonksiyon> fonksiyonlar;
  final bool fiyatUstunde;
  final String? baslik;
  final int cizgiSayisi;
}

// ─────────────────────────────────────────────────────────────────────────────
// Ayrıştırıcı
// ─────────────────────────────────────────────────────────────────────────────

const Set<String> _tipAdlari = {
  'int', 'float', 'bool', 'color', 'string', 'label', 'line', 'box', //
  'table', 'linefill', 'polyline', 'series', 'simple', 'const', 'input',
};

/// Desteklenmeyen anahtar sözcükler — neden olmadığını söyleyen mesajla.
const Map<String, (String, String)> _desteklenmeyen = {
  'import': ('Kütüphane (import) eklenemez; kodu betiğe yapıştır.',
      'Libraries (import) are not supported; paste the code in.'),
  'export': ('Kütüphane betikleri (export) desteklenmiyor.',
      'Library scripts (export) are not supported.'),
  'library': ('Kütüphane betikleri desteklenmiyor; gösterge (indicator) yaz.',
      'Library scripts are not supported; write an indicator.'),
  'method': ('method tanımı desteklenmiyor; düz fonksiyon yaz: f(x) => …',
      'method is not supported; write a plain function: f(x) => …'),
  'type': ('type (kullanıcı tipi) desteklenmiyor.',
      'User-defined types are not supported.'),
  'enum': ('enum desteklenmiyor.', 'enum is not supported.'),
};

const String _diziTr =
    'Diziler (array/matrix/map) desteklenmiyor; gösterge fonksiyonlarıyla yaz.';
const String _diziEn =
    'Arrays (array/matrix/map) are not supported; use the built-in functions.';

class _Ayristirici {
  _Ayristirici(this._j);
  final List<_Jeton> _j;
  int _p = 0;
  int _derinlik = 0;
  int _sonId = 0;
  int _yerel = 0;
  int _dongu = 0;
  int _cizgi = 0;
  bool _ust = true;
  String? _baslik;
  bool _ustBelirlendi = false;

  /// Bildirilen adlar — kapsam yığını (ayrıştırma anında "tanımsız ad").
  final List<Set<String>> _kapsam = [{}];
  final Map<String, _Fonksiyon> _fonksiyonlar = {};

  _Jeton get _su => _j[_p];
  _Jeton _bak(int k) => _j[math.min(_p + k, _j.length - 1)];
  _Jeton _al() => _j[_p++];
  bool _isaretMi(String s, [int k = 0]) =>
      _bak(k).tur == _J.isaret && _bak(k).deger == s;
  bool _adMi(String s, [int k = 0]) =>
      _bak(k).tur == _J.ad && _bak(k).deger == s;
  int _yeniId() => ++_sonId;

  void _bekle(String s) {
    if (!_isaretMi(s)) {
      throw _hata("'$s' bekleniyordu.", "Expected '$s'.", _su);
    }
    _p++;
  }

  bool _tanimli(String ad) => _kapsam.any((k) => k.contains(ad));
  void _tanimla(String ad) => _kapsam.last.add(ad);

  _Program program() {
    final deyimler = <_D>[];
    while (_su.tur != _J.son) {
      if (_su.tur == _J.satirSonu) {
        _p++;
        continue;
      }
      if (_su.tur == _J.girinti) {
        throw _hata('Beklenmeyen girinti (satır başındaki boşlukları sil).',
            'Unexpected indentation (remove the leading spaces).', _su);
      }
      if (_su.tur == _J.cikinti) {
        _p++;
        continue;
      }
      if (_fonksiyonTanimiMi()) {
        final f = _fonksiyonTanimi();
        _fonksiyonlar[f.ad] = f;
        continue;
      }
      deyimler.add(_deyim());
    }
    if (_cizgi == 0 && !_ciktiVar) {
      throw const BetikHatasi(
          'Çizilecek bir şey yok. plot(...) ekle.',
          'Nothing to draw. Add plot(...).');
    }
    return _Program(
      deyimler: deyimler,
      fonksiyonlar: _fonksiyonlar,
      fiyatUstunde: _ust,
      baslik: _baslik,
      cizgiSayisi: _cizgi,
    );
  }

  bool _ciktiVar = false;

  // ── Deyimler ─────────────────────────────────────────────────────────────

  List<_D> _blok() {
    if (_su.tur != _J.satirSonu) {
      throw _hata('Blok yeni satırda, 4 boşluk içeride başlar.',
          'A block starts on a new line, indented by 4 spaces.', _su);
    }
    _p++;
    if (_su.tur != _J.girinti) {
      throw _hata('Blok 4 boşluk içeride başlamalı.',
          'The block must be indented by 4 spaces.', _su);
    }
    _p++;
    _kapsam.add({});
    _yerel++;
    final out = <_D>[];
    try {
      while (_su.tur != _J.cikinti && _su.tur != _J.son) {
        if (_su.tur == _J.satirSonu) {
          _p++;
          continue;
        }
        if (_su.tur == _J.girinti) {
          throw _hata('Beklenmeyen girinti.', 'Unexpected indentation.', _su);
        }
        out.add(_deyim());
      }
    } finally {
      _kapsam.removeLast();
      _yerel--;
    }
    if (_su.tur == _J.cikinti) _p++;
    if (out.isEmpty) {
      throw _hata('Blok boş.', 'Empty block.', _su);
    }
    return out;
  }

  /// Bir deyimi ayrıştırır; blokla bitmeyen deyim satır sonu ister.
  _D _deyim() {
    final bas = _su;
    final d = _deyimGovdesi();
    final blokla = _bak(-1).tur == _J.cikinti;
    if (!blokla) {
      if (_su.tur == _J.satirSonu) {
        _p++;
      } else if (_su.tur != _J.son && _su.tur != _J.cikinti) {
        throw _hata('Satır sonu bekleniyordu.', 'Expected end of line.', _su);
      }
    }
    if (d is _DIfade && !_etkili(d.e)) {
      throw _hata('Bu satır bir şey yapmıyor.', 'This line does nothing.', bas);
    }
    return d;
  }

  bool _etkili(_I e) =>
      e is _ICagri || e is _IEger || e is _ISec;

  _D _deyimGovdesi() {
    final j = _su;
    if (j.tur == _J.ad) {
      // `type`/`method` Pine'da bağlamsal sözcük: parametre adı da olur
      // (TradingView'in kendi RSI'ında `ma(source, length, type)`).
      final m = _desteklenmeyen[j.deger];
      if (m != null &&
          (_bak(1).tur == _J.ad || (j.deger == 'library' && _isaretMi('(', 1)))) {
        throw _hata(m.$1, m.$2, j);
      }
      switch (j.deger) {
        case 'if':
          return _DIfade(j, _egerYapisi());
        case 'switch':
          return _DIfade(j, _secYapisi());
        case 'for':
          return _forYapisi();
        case 'while':
          _p++;
          final k = _ifade();
          _dongu++;
          try {
            return _DWhile(j, k, _blok());
          } finally {
            _dongu--;
          }
        case 'break' || 'continue':
          _p++;
          if (_dongu == 0) {
            throw _hata("'${j.deger}' yalnız döngü içinde.",
                "'${j.deger}' only inside a loop.", j);
          }
          return j.deger == 'break' ? _DKir(j) : _DDevam(j);
      }
    }
    // var / varip / tip bildirimi
    var kalici = false;
    if (_adMi('var') || _adMi('varip')) {
      _p++;
      kalici = true;
    }
    _tipAtla();
    if (_isaretMi('[') && _demetBildirimiMi()) {
      return _demetBildirimi();
    }
    if (_su.tur == _J.ad && _isaretMi('=', 1)) {
      final adJ = _al();
      _p++;
      final ad = adJ.deger;
      _adDenetle(ad, adJ);
      final e = _sagTaraf();
      _tanimla(ad);
      return _DBildir(adJ, ad, e, kalici, _yeniId());
    }
    if (kalici) {
      throw _hata("'var' sonrası  ad = değer  bekleniyordu.",
          "Expected  name = value  after 'var'.", _su);
    }
    if (_su.tur == _J.ad && _bak(1).tur == _J.isaret &&
        const {':=', '+=', '-=', '*=', '/=', '%='}.contains(_bak(1).deger)) {
      final adJ = _al();
      final op = _al().deger;
      if (!_tanimli(adJ.deger)) {
        throw _hata("'${adJ.deger}' tanımlanmadan ':=' ile atanamaz; önce  ${adJ.deger} = …  yaz.",
            "'${adJ.deger}' must be declared before ':='; write  ${adJ.deger} = …  first.",
            adJ);
      }
      return _DAta(adJ, adJ.deger, op, _sagTaraf());
    }
    return _DIfade(j, _ifade());
  }

  void _adDenetle(String ad, _Jeton j) {
    if (const {'true', 'false', 'na', 'if', 'for', 'while', 'switch'}
        .contains(ad)) {
      throw _hata("'$ad' ayrılmış bir sözcük; başka ad seç.",
          "'$ad' is a reserved word; pick another name.", j);
    }
  }

  /// `float x =`, `series float x =`, `int[] x` …
  void _tipAtla() {
    while (_su.tur == _J.ad &&
        _tipAdlari.contains(_su.deger) &&
        (_bak(1).tur == _J.ad ||
            (_isaretMi('[', 1) && _isaretMi(']', 2)))) {
      if (_isaretMi('[', 1)) throw _hata(_diziTr, _diziEn, _su);
      _p++;
    }
    if (_su.tur == _J.ad &&
        const {'array', 'matrix', 'map'}.contains(_su.deger) &&
        _isaretMi('<', 1)) {
      throw _hata(_diziTr, _diziEn, _su);
    }
  }

  bool _demetBildirimiMi() {
    var k = 1;
    while (true) {
      if (_bak(k).tur != _J.ad) return false;
      k++;
      if (_isaretMi(',', k)) {
        k++;
        continue;
      }
      if (_isaretMi(']', k)) return _isaretMi('=', k + 1);
      return false;
    }
  }

  _D _demetBildirimi() {
    final j = _al();
    final adlar = <String>[];
    while (true) {
      final a = _al();
      _adDenetle(a.deger, a);
      adlar.add(a.deger);
      if (_isaretMi(',')) {
        _p++;
        continue;
      }
      break;
    }
    _bekle(']');
    _bekle('=');
    final e = _sagTaraf();
    adlar.forEach(_tanimla);
    return _DDemet(j, adlar, e, _yeniId());
  }

  _I _sagTaraf() {
    if (_adMi('if')) return _egerYapisi();
    if (_adMi('switch')) return _secYapisi();
    return _ifade();
  }

  _IEger _egerYapisi() {
    final j = _al(); // if
    final kosullar = <_I>[_ifade()];
    final bloklar = <List<_D>>[_blok()];
    List<_D>? degilse;
    while (_adMi('else')) {
      _p++;
      if (_adMi('if')) {
        _p++;
        kosullar.add(_ifade());
        bloklar.add(_blok());
        continue;
      }
      degilse = _blok();
      break;
    }
    return _IEger(j, kosullar, bloklar, degilse);
  }

  _ISec _secYapisi() {
    final j = _al(); // switch
    _I? konu;
    if (_su.tur != _J.satirSonu) konu = _ifade();
    if (_su.tur != _J.satirSonu || _bak(1).tur != _J.girinti) {
      throw _hata('switch durumları alt satırlarda, 4 boşluk içeride.',
          'switch cases go on the next lines, indented by 4 spaces.', _su);
    }
    _p += 2;
    final durumlar = <(_I?, List<_D>)>[];
    while (_su.tur != _J.cikinti && _su.tur != _J.son) {
      if (_su.tur == _J.satirSonu) {
        _p++;
        continue;
      }
      _I? kosul;
      if (!_isaretMi('=>')) kosul = _ifade();
      final ok = _su;
      _bekle('=>');
      List<_D> blok;
      if (_su.tur == _J.satirSonu) {
        blok = _blok();
      } else {
        _kapsam.add({});
        _yerel++;
        try {
          blok = [_deyimGovdesi()];
        } finally {
          _kapsam.removeLast();
          _yerel--;
        }
        if (_su.tur == _J.satirSonu) _p++;
      }
      if (kosul == null && durumlar.any((d) => d.$1 == null)) {
        throw _hata('switch içinde tek varsayılan (=>) olur.',
            'Only one default (=>) per switch.', ok);
      }
      durumlar.add((kosul, blok));
    }
    if (_su.tur == _J.cikinti) _p++;
    return _ISec(j, konu, durumlar);
  }

  _D _forYapisi() {
    final j = _al(); // for
    if (_isaretMi('[') || (_su.tur == _J.ad && _adMi('in', 1))) {
      throw _hata(_diziTr, _diziEn, j);
    }
    if (_su.tur != _J.ad) {
      throw _hata("for sonrası sayaç adı bekleniyordu: for i = 0 to 9",
          'Expected a counter name: for i = 0 to 9', _su);
    }
    final ad = _al().deger;
    _bekle('=');
    final bas = _ifade();
    if (!_adMi('to')) {
      throw _hata("'to' bekleniyordu: for i = 0 to 9", "Expected 'to'.", _su);
    }
    _p++;
    final son = _ifade();
    _I? adim;
    if (_adMi('by')) {
      _p++;
      adim = _ifade();
    }
    _kapsam.add({ad});
    _dongu++;
    try {
      return _DFor(j, ad, bas, son, adim, _blok(), _yeniId());
    } finally {
      _dongu--;
      _kapsam.removeLast();
    }
  }

  // ── Fonksiyon tanımı ─────────────────────────────────────────────────────

  bool _fonksiyonTanimiMi() {
    if (_su.tur != _J.ad || !_isaretMi('(', 1)) return false;
    var k = 2;
    var d = 1;
    while (d > 0) {
      final t = _bak(k);
      if (t.tur == _J.son) return false;
      if (t.tur == _J.isaret && (t.deger == '(' || t.deger == '[')) d++;
      if (t.tur == _J.isaret && (t.deger == ')' || t.deger == ']')) d--;
      k++;
    }
    return _isaretMi('=>', k);
  }

  _Fonksiyon _fonksiyonTanimi() {
    final j = _al();
    final ad = j.deger;
    if (_fonksiyonKanonik(ad) != null && ad.contains('.')) {
      throw _hata("'$ad' yerleşik; başka ad seç.",
          "'$ad' is built in; pick another name.", j);
    }
    _bekle('(');
    final parametreler = <(String, _I?)>[];
    final adlar = <String>{};
    while (!_isaretMi(')')) {
      _tipAtla();
      if (_su.tur != _J.ad) {
        throw _hata('Parametre adı bekleniyordu.', 'Expected a parameter name.',
            _su);
      }
      final p = _al().deger;
      _I? varsayilan;
      if (_isaretMi('=')) {
        _p++;
        varsayilan = _ifade();
      }
      parametreler.add((p, varsayilan));
      adlar.add(p);
      if (_isaretMi(',')) _p++;
    }
    _bekle(')');
    _bekle('=>');
    // Özyineleme Pine'da yok: ad gövde ayrışırken henüz tanımlı değil.
    _kapsam.add(adlar);
    _yerel++;
    final List<_D> govde;
    try {
      if (_su.tur == _J.satirSonu) {
        govde = _fonksiyonBlogu();
      } else {
        final e = _ifade();
        govde = [_DIfade(j, e)];
        if (_su.tur == _J.satirSonu) _p++;
      }
    } finally {
      _kapsam.removeLast();
      _yerel--;
    }
    return _Fonksiyon(ad, parametreler, govde, j, _yeniId());
  }

  /// Fonksiyon gövdesi: bildirimler ve son ifade (dönüş değeri). Son satır
  /// `[a, b]` demeti olabilir.
  List<_D> _fonksiyonBlogu() {
    _p++; // satır sonu
    if (_su.tur != _J.girinti) {
      throw _hata('Fonksiyon gövdesi 4 boşluk içeride başlar.',
          'The function body must be indented by 4 spaces.', _su);
    }
    _p++;
    final out = <_D>[];
    while (_su.tur != _J.cikinti && _su.tur != _J.son) {
      if (_su.tur == _J.satirSonu) {
        _p++;
        continue;
      }
      final bas = _su;
      final d = _deyimGovdesi();
      out.add(d);
      final blokla = _bak(-1).tur == _J.cikinti;
      if (!blokla) {
        if (_su.tur == _J.satirSonu) {
          _p++;
        } else if (_su.tur != _J.son && _su.tur != _J.cikinti) {
          throw _hata('Satır sonu bekleniyordu.', 'Expected end of line.', bas);
        }
      }
    }
    if (_su.tur == _J.cikinti) _p++;
    if (out.isEmpty) throw _hata('Fonksiyon gövdesi boş.', 'Empty body.', _su);
    return out;
  }

  // ── İfadeler ─────────────────────────────────────────────────────────────

  _I _ifade() {
    if (++_derinlik > _kAzamiDerinlik) {
      throw _hata('İfade çok iç içe.', 'Expression is nested too deeply.', _su);
    }
    try {
      return _kosul();
    } finally {
      _derinlik--;
    }
  }

  _I _kosul() {
    final k = _veya();
    if (_isaretMi('?')) {
      final j = _al();
      final a = _ifade();
      _bekle(':');
      final b = _ifade();
      return _IKosul(j, k, a, b);
    }
    return k;
  }

  _I _veya() {
    var a = _ve();
    while (_adMi('or')) {
      final j = _al();
      a = _IIkili(j, 'or', a, _ve());
    }
    return a;
  }

  _I _ve() {
    var a = _esitlik();
    while (_adMi('and')) {
      final j = _al();
      a = _IIkili(j, 'and', a, _esitlik());
    }
    return a;
  }

  _I _esitlik() {
    var a = _karsilastir();
    while (_isaretMi('==') || _isaretMi('!=')) {
      final j = _al();
      a = _IIkili(j, j.deger, a, _karsilastir());
    }
    return a;
  }

  _I _karsilastir() {
    var a = _topla();
    while (_isaretMi('<') || _isaretMi('>') || _isaretMi('<=') ||
        _isaretMi('>=')) {
      final j = _al();
      a = _IIkili(j, j.deger, a, _topla());
    }
    return a;
  }

  _I _topla() {
    var a = _carp();
    while (_isaretMi('+') || _isaretMi('-')) {
      final j = _al();
      a = _IIkili(j, j.deger, a, _carp());
    }
    return a;
  }

  _I _carp() {
    var a = _tekli();
    while (_isaretMi('*') || _isaretMi('/') || _isaretMi('%')) {
      final j = _al();
      a = _IIkili(j, j.deger, a, _tekli());
    }
    return a;
  }

  _I _tekli() {
    if (_isaretMi('-') || _isaretMi('+') || _adMi('not')) {
      final j = _al();
      if (++_derinlik > _kAzamiDerinlik) {
        throw _hata('İfade çok iç içe.', 'Expression is nested too deeply.', j);
      }
      try {
        final e = _tekli();
        if (j.deger == '+') return e;
        return _ITekli(j, j.deger == 'not' ? 'not' : '-', e);
      } finally {
        _derinlik--;
      }
    }
    var e = _birincil();
    while (_isaretMi('[')) {
      final j = _al();
      final n = _ifade();
      _bekle(']');
      e = _IGecmis(j, e, n, _yeniId());
    }
    return e;
  }

  _I _birincil() {
    final j = _su;
    switch (j.tur) {
      case _J.sayi:
        _p++;
        final v = double.tryParse(j.deger);
        if (v == null) {
          throw _hata("Geçersiz sayı: '${j.deger}' (ondalık için nokta kullan).",
              "Invalid number: '${j.deger}' (use a dot for decimals).", j);
        }
        return _ISayi(j, v);
      case _J.metin:
        _p++;
        return _IMetin(j, j.deger);
      case _J.renk:
        _p++;
        return _IRenk(j, _PineRenk.onaltilik(j.deger));
      case _J.ad:
        return _adVeyaCagri();
      case _J.isaret when j.deger == '(':
        _p++;
        final e = _ifade();
        _bekle(')');
        return e;
      case _J.isaret when j.deger == '[':
        _p++;
        final el = <_I>[];
        while (!_isaretMi(']')) {
          el.add(_ifade());
          if (_isaretMi(',')) {
            _p++;
            continue;
          }
          break;
        }
        _bekle(']');
        return _IDizi(j, el);
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

  _I _adVeyaCagri() {
    final j = _al();
    switch (j.deger) {
      case 'true':
        return _IBool(j, true);
      case 'false':
        return _IBool(j, false);
      case 'na' when !_isaretMi('('):
        return _INa(j);
      case 'if':
        _p--;
        return _egerYapisi();
      case 'switch':
        _p--;
        return _secYapisi();
    }
    var ad = j.deger;
    while (_isaretMi('.') && _bak(1).tur == _J.ad) {
      _p++;
      ad = '$ad.${_al().deger}';
    }
    final ns = ad.contains('.') ? ad.substring(0, ad.indexOf('.')) : '';
    if (const {'array', 'matrix', 'map'}.contains(ns) ||
        const {'array', 'matrix', 'map'}.contains(ad)) {
      throw _hata(_diziTr, _diziEn, j);
    }
    if (_isaretMi('<')) {
      // Jenerik çağrı: array.new<float>(), request.security<…> …
      if (ns.isNotEmpty && _isaretMi('>', 2)) throw _hata(_diziTr, _diziEn, j);
    }
    if (_isaretMi('(')) return _cagri(j, ad);
    if (_tanimli(ad)) return _IAd(j, ad);
    if (_degiskenKanonik(ad) != null) return _IAd(j, ad);
    if (_sabitAdMi(ad)) return _IAd(j, ad);
    if (_fonksiyonlar.containsKey(ad) || _fonksiyonKanonik(ad) != null) {
      throw _hata("'$ad' bir fonksiyon; parantezle çağır: $ad(...)",
          "'$ad' is a function; call it: $ad(...)", j);
    }
    final oneri = _yakinAd(ad, [
      for (final k in _kapsam) ...k,
      ..._yerlesikDegiskenler.keys,
    ]);
    throw _hata(
        "Tanımsız ad: '$ad'${oneri != null ? " — '$oneri' mi demek istedin?" : ''}",
        "Undefined name: '$ad'${oneri != null ? " — did you mean '$oneri'?" : ''}",
        j);
  }

  _I _cagri(_Jeton j, String ad) {
    _p++; // (
    final arg = <_I>[];
    final adli = <String, _I>{};
    while (!_isaretMi(')')) {
      if (_su.tur == _J.ad && _isaretMi('=', 1)) {
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
    _bekle(')');
    if (_fonksiyonlar.containsKey(ad)) {
      return _ICagri(j, ad, arg, adli, _yeniId())..kullanici = true;
    }
    final k = _fonksiyonKanonik(ad);
    if (k == null) {
      final oneri = _yakinAd(ad, [
        ..._fonksiyonlar.keys,
        ..._imzalar.keys,
      ]);
      throw _hata(
          "Bilinmeyen fonksiyon: '$ad'${oneri != null ? " — '$oneri' mi demek istedin?" : ''}",
          "Unknown function: '$ad'${oneri != null ? " — did you mean '$oneri'?" : ''}",
          j);
    }
    final c = _ICagri(j, k, arg, adli, _yeniId());
    _cagriDenetle(c);
    return c;
  }

  /// Çıktı fonksiyonları yalnız en dış kapsamda (Pine kuralı) ve
  /// `indicator()` ayarları ayrıştırma anında okunur.
  void _cagriDenetle(_ICagri c) {
    if (_ciktiFonksiyonlari.contains(c.ad)) {
      if (_yerel > 0) {
        throw _hata('${c.ad}(...) yerel kapsamda (if/for/fonksiyon içinde) kullanılamaz.',
            'Cannot use ${c.ad}(...) in a local scope.', c.j);
      }
      _ciktiVar = true;
      if (c.ad == 'plot') _cizgi++;
    }
    if (c.ad == 'indicator' || c.ad == 'strategy') {
      if (_ustBelirlendi) {
        throw _hata('indicator(...) bir kez yazılır.',
            'indicator(...) may appear only once.', c.j);
      }
      _ustBelirlendi = true;
      final baslikI = c.adli['title'] ?? (c.arg.isNotEmpty ? c.arg[0] : null);
      if (baslikI is _IMetin) _baslik = baslikI.v;
      final ustI = c.adli['overlay'] ?? (c.arg.length > 2 ? c.arg[2] : null);
      if (ustI != null) {
        if (ustI is! _IBool) {
          throw _hata('overlay true ya da false olmalı.',
              'overlay must be true or false.', ustI.j);
        }
        _ust = ustI.v;
      } else {
        // Pine'da varsayılan overlay=false.
        _ust = false;
      }
      final tf = c.adli['timeframe'];
      if (tf is _IMetin && tf.v.isNotEmpty) {
        throw _hata('Başka zaman aralığında çalışan gösterge desteklenmiyor; grafiğin aralığını seç.',
            'Indicators on another timeframe are not supported; pick the chart interval.',
            tf.j);
      }
    }
  }
}

/// Yakın adı bul (öneri için) — küçük Levenshtein.
String? _yakinAd(String ad, Iterable<String> adaylar) {
  String? en;
  var enIyi = 3;
  for (final a in adaylar) {
    final d = _mesafe(ad.toLowerCase(), a.toLowerCase());
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
