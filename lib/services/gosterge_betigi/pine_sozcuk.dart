part of 'betik.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sözcükleyici
//
// Pine girintiyle blok açar (Python gibi): 4 boşluk (ya da sekme) = bir
// seviye. Satır devamı Pine'daki kuralla: 4'ün katı OLMAYAN girinti önceki
// satırın devamıdır. TradingView'den kopyalanan kodlarda sık görülen iki
// gevşekliği de kabul ediyoruz: satır bir işleçle bitiyorsa ya da sonraki
// satır işleçle (`?`, `:`, `and` …) başlıyorsa girinti ne olursa olsun devam.
// ─────────────────────────────────────────────────────────────────────────────

enum _J { sayi, ad, metin, renk, isaret, satirSonu, girinti, cikinti, son }

class _Jeton {
  const _Jeton(this.tur, this.deger, this.satir, this.sutun);
  final _J tur;
  final String deger;
  final int satir;
  final int sutun;

  @override
  String toString() => '$tur($deger)@$satir:$sutun';
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
  final List<_Jeton> _out = [];
  final List<int> _girintiler = [0];

  static final _harf = RegExp(r'[A-Za-z_çğıöşüÇĞİÖŞÜ]');
  static final _harfRakam = RegExp(r'[A-Za-z0-9_çğıöşüÇĞİÖŞÜ]');
  static final _onaltilik = RegExp(r'[0-9A-Fa-f]');
  static const _ikili = {
    '==', '!=', '<=', '>=', ':=', '+=', '-=', '*=', '/=', '%=', '=>', //
  };
  static const _tekli = '+-*/%()[],=<>?:.';

  /// Satırı bu jetonla biten satırın alttaki satırı devamıdır.
  static const _devamIsleci = {
    '+', '-', '*', '/', '%', '==', '!=', '<', '>', '<=', '>=', '?', ':', //
    ',', '=', ':=', '+=', '-=', '*=', '/=', '%=', '(', '[',
  };

  List<_Jeton> hepsi() {
    var satirBasinda = true;
    while (_i < kod.length) {
      if (satirBasinda && _parantez == 0) {
        satirBasinda = false;
        if (!_satirBasi_()) break;
        continue;
      }
      final c = kod[_i];
      final sutun = _i - _satirBasi + 1;
      if (c == '\n') {
        _yeniSatir();
        if (_parantez == 0) satirBasinda = true;
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
      if (_rakam(c) ||
          (c == '.' && _i + 1 < kod.length && _rakam(kod[_i + 1]))) {
        _sayi(sutun);
        continue;
      }
      if (_harf.hasMatch(c)) {
        final b = _i;
        while (_i < kod.length && _harfRakam.hasMatch(kod[_i])) {
          _i++;
        }
        _out.add(_Jeton(_J.ad, kod.substring(b, _i), _satir, sutun));
        continue;
      }
      if (c == '"' || c == "'") {
        _metin(c, sutun);
        continue;
      }
      if (c == '#') {
        final b = ++_i;
        while (_i < kod.length && _onaltilik.hasMatch(kod[_i])) {
          _i++;
        }
        final h = kod.substring(b, _i);
        if (h.length != 6 && h.length != 8) {
          throw BetikHatasi("Renk #rrggbb biçiminde yazılır: '#$h'",
              "Color must be #rrggbb: '#$h'",
              satir: _satir, sutun: sutun);
        }
        _out.add(_Jeton(_J.renk, h, _satir, sutun));
        continue;
      }
      if (_i + 1 < kod.length && _ikili.contains(kod.substring(_i, _i + 2))) {
        _out.add(_Jeton(_J.isaret, kod.substring(_i, _i + 2), _satir, sutun));
        _i += 2;
        continue;
      }
      if (_tekli.contains(c)) {
        if (c == '(' || c == '[') _parantez++;
        if ((c == ')' || c == ']') && _parantez > 0) _parantez--;
        _out.add(_Jeton(_J.isaret, c, _satir, sutun));
        _i++;
        continue;
      }
      throw BetikHatasi("Tanınmayan karakter: '$c'", "Unknown character: '$c'",
          satir: _satir, sutun: sutun);
    }
    _satirKapat();
    while (_girintiler.length > 1) {
      _girintiler.removeLast();
      _out.add(_Jeton(_J.cikinti, '', _satir, 1));
    }
    _out.add(_Jeton(_J.son, '', _satir, 1));
    return _out;
  }

  void _yeniSatir() {
    _i++;
    _satir++;
    _satirBasi = _i;
    if (_satir > _kAzamiSatir) {
      throw const BetikHatasi('Betik en fazla $_kAzamiSatir satır olabilir.',
          'Script can have at most $_kAzamiSatir lines.');
    }
  }

  /// Satır başı: girintiyi ölç, boş/yorum satırını atla, blok jetonlarını
  /// üret. false → kod bitti.
  bool _satirBasi_() {
    while (true) {
      var w = 0;
      var j = _i;
      while (j < kod.length && (kod[j] == ' ' || kod[j] == '\t')) {
        w += kod[j] == '\t' ? 4 : 1;
        j++;
      }
      if (j >= kod.length) {
        _i = j;
        return false;
      }
      final c = kod[j];
      final yorum = c == '/' && j + 1 < kod.length && kod[j + 1] == '/';
      if (c == '\n' || c == '\r' || yorum) {
        while (j < kod.length && kod[j] != '\n') {
          j++;
        }
        _i = j;
        if (_i >= kod.length) return false;
        _yeniSatir();
        continue;
      }
      _i = j;
      if (_devamMi(w, j)) return true;
      _satirKapat();
      final ust = _girintiler.last;
      final jeton = _Jeton(_J.girinti, '', _satir, w + 1);
      if (w > ust) {
        _girintiler.add(w);
        _out.add(jeton);
      } else if (w < ust) {
        while (w < _girintiler.last) {
          _girintiler.removeLast();
          _out.add(_Jeton(_J.cikinti, '', _satir, w + 1));
        }
        if (w != _girintiler.last) {
          throw BetikHatasi(
              'Girinti üst bloklardan biriyle hizalı değil.',
              'Indentation does not match any outer block.',
              satir: _satir,
              sutun: w + 1);
        }
      }
      return true;
    }
  }

  /// Bu satır öncekinin devamı mı?
  bool _devamMi(int girinti, int j) {
    if (_out.isEmpty) return false;
    final son = _out.last;
    if (son.tur == _J.satirSonu ||
        son.tur == _J.girinti ||
        son.tur == _J.cikinti) {
      return false;
    }
    if (girinti % 4 != 0) return true;
    if (son.tur == _J.isaret && _devamIsleci.contains(son.deger)) return true;
    if (son.tur == _J.ad && (son.deger == 'and' || son.deger == 'or')) {
      return true;
    }
    // Sonraki satır işleçle başlıyor (çok satırlı üçlü koşul).
    final c = kod[j];
    if (girinti > _girintiler.last &&
        (c == '?' || c == ':' || c == '+' || c == '*' || c == '/')) {
      return true;
    }
    if (girinti > _girintiler.last &&
        (kod.startsWith('and ', j) || kod.startsWith('or ', j))) {
      return true;
    }
    return false;
  }

  void _satirKapat() {
    if (_out.isEmpty) return;
    final t = _out.last.tur;
    if (t == _J.satirSonu || t == _J.girinti || t == _J.cikinti) return;
    _out.add(_Jeton(_J.satirSonu, '\n', _satir, 1));
  }

  void _sayi(int sutun) {
    final b = _i;
    while (_i < kod.length && (_rakam(kod[_i]) || kod[_i] == '.')) {
      _i++;
    }
    if (_i < kod.length && (kod[_i] == 'e' || kod[_i] == 'E')) {
      var j = _i + 1;
      if (j < kod.length && (kod[j] == '+' || kod[j] == '-')) j++;
      if (j < kod.length && _rakam(kod[j])) {
        _i = j;
        while (_i < kod.length && _rakam(kod[_i])) {
          _i++;
        }
      }
    }
    _out.add(_Jeton(_J.sayi, kod.substring(b, _i), _satir, sutun));
  }

  void _metin(String tirnak, int sutun) {
    _i++;
    final sb = StringBuffer();
    while (_i < kod.length && kod[_i] != tirnak && kod[_i] != '\n') {
      if (kod[_i] == '\\' && _i + 1 < kod.length) {
        final s = kod[_i + 1];
        sb.write(switch (s) { 'n' => '\n', 't' => '\t', _ => s });
        _i += 2;
        continue;
      }
      sb.write(kod[_i]);
      _i++;
    }
    if (_i >= kod.length || kod[_i] != tirnak) {
      throw BetikHatasi('Tırnak kapanmamış.', 'Unterminated string.',
          satir: _satir, sutun: sutun);
    }
    _i++;
    _out.add(_Jeton(_J.metin, sb.toString(), _satir, sutun));
  }

  static bool _rakam(String c) {
    final k = c.codeUnitAt(0);
    return k >= 48 && k <= 57;
  }
}
