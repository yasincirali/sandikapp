import 'package:intl/intl.dart';

import 'tr_format.dart';

/// Baz para birimi (Faz 3.2).
///
/// Portföy TÜM hesaplarını TRY üzerinden yapar (`toTRY`, `totalCostTRY`,
/// seri motoru); baz para birimi yalnızca **gösterim** katmanıdır. Bir TRY
/// tutarı bugünkü kurla bölünüp seçili birimin sembolüyle yazılır. Bu bilinçli
/// bir sadeleştirmedir: geçmiş tarihli tutarlar da bugünkü kurla çevrilir,
/// yani "USD cinsinden gerçek getiri" DEĞİL, "bugünkü dolarla kaç para"
/// sorusunun cevabıdır. Kur bazlı gerçek getiri ayrı bir hesaptır
/// (`TECHNICAL_DEBT.md`).
///
/// Neden ayrı bir model: 60'tan fazla çağrı yeri `NumberFormat` nesnesini
/// parametre olarak taşıyor ve `.format(x)` çağırıyor. [ParaBicimi] aynı
/// `format` imzasını verir; çağrı yerleri tipi değiştirmekle yetinir.
/// Fiyat kaynağının 22 ayar gram altın iç sembolü (`PriceService._goldWeights`).
const kGoldGramSymbol = 'ALTIN_GRAM';

enum BaseCurrency {
  try_('TRY', '₺', 'Lira'),
  usd('USD', '\$', 'Dolar'),
  eur('EUR', '€', 'Euro'),
  gold('ALTIN', 'gr', 'Gram altın');

  const BaseCurrency(this.kod, this.sembol, this.label);
  final String kod;
  final String sembol;
  final String label;

  /// Tercih tam sayı olarak saklanır; bilinmeyen değer TRY'ye düşer.
  static BaseCurrency fromIndex(int i) =>
      i >= 0 && i < values.length ? values[i] : try_;
}

/// Seçili baz birim + o birimin TRY karşılığı (1 birim = [kur] TRY).
///
/// [kur] geçersizse (0 ya da negatif — kur henüz çekilmedi) TRY'ye düşülür:
/// yanlış kurla yazılmış bir tutar, ₺ ile yazılmış doğru tutardan kötüdür.
class BazPara {
  const BazPara(this.birim, this.kur);

  /// Varsayılan: ₺, kur 1 — eski davranışın birebir aynısı.
  const BazPara.lira()
      : birim = BaseCurrency.try_,
        kur = 1;

  final BaseCurrency birim;
  final double kur;

  bool get lira => birim == BaseCurrency.try_ || !(kur > 0);
  BaseCurrency get etkinBirim => lira ? BaseCurrency.try_ : birim;
  String get sembol => etkinBirim.sembol;

  double cevir(double tryTutar) => lira ? tryTutar : tryTutar / kur;

  /// Bakiye gizliyken yazılan maske — sembol tutarla AYNI tarafta durur.
  /// Gram altında sembol sonektir (`3,4 gr`); maskeyi her zaman ön eke
  /// koymak `gr••••` gibi bir şey üretiyordu.
  String get gizliTutar =>
      etkinBirim == BaseCurrency.gold ? '•••• $sembol' : '$sembol••••';

  /// `tryFormatter(digits:)` karşılığı — `format(num)` sunar.
  ParaBicimi formatter({int digits = 0}) => ParaBicimi._(this, digits);

  /// `fmtTRY` karşılığı.
  String fmt(double tryTutar, {int digits = 0}) =>
      formatter(digits: digits).format(tryTutar);

  /// `fmtTRYCompact` karşılığı — eksen/dar alan etiketi.
  String compact(double tryTutar) {
    if (lira) return fmtTRYCompact(tryTutar);
    final v = cevir(tryTutar);
    final abs = v.abs();
    final sign = v < 0 ? '-' : '';
    final s = etkinBirim.sembol;
    if (etkinBirim == BaseCurrency.gold) {
      if (abs >= 1000) return '$sign${fmtNum(abs / 1000, digits: 1)}K $s';
      return '$sign${fmtNum(abs, digits: abs < 100 ? 1 : 0)} $s';
    }
    if (abs >= 1000000) return '$sign$s${fmtNum(abs / 1000000, digits: 2)}M';
    if (abs >= 1000) return '$sign$s${fmtNum(abs / 1000, digits: 1)}K';
    return '$sign$s${fmtNum(abs, digits: 0)}';
  }

  /// `fmtTRYAxis` karşılığı: iki komşu eksen etiketi ayırt edilebilir kalsın
  /// diye ondalık sayısı bandın genişliğine göre seçilir.
  String axis(double tryTutar, double trySpan) {
    if (lira) return fmtTRYAxis(tryTutar, trySpan);
    final v = cevir(tryTutar);
    final span = cevir(trySpan).abs();
    final abs = v.abs();
    final sign = v < 0 ? '-' : '';
    final s = etkinBirim.sembol;
    final gold = etkinBirim == BaseCurrency.gold;
    String yaz(String govde) => gold ? '$sign$govde $s' : '$sign$s$govde';
    if (abs >= 1000000) {
      final spanM = span / 1000000;
      final digits = spanM >= 0.02 ? 2 : (spanM >= 0.002 ? 3 : 4);
      return yaz('${fmtNum(abs / 1000000, digits: digits)}M');
    }
    if (abs >= 1000) {
      final spanK = span / 1000;
      final digits = spanK >= 0.2 ? 1 : 2;
      return yaz('${fmtNum(abs / 1000, digits: digits)}K');
    }
    return yaz(fmtNum(abs, digits: span < 10 ? 2 : 0));
  }
}

/// `NumberFormat.format` ile aynı imza: TRY tutarı alır, baz birimde yazar.
class ParaBicimi {
  ParaBicimi._(this._baz, this._digits)
      : _tr = tryFormatter(digits: _digits);

  final BazPara _baz;
  final int _digits;
  final NumberFormat _tr;

  String format(num tryTutar) {
    final v = tryTutar.toDouble();
    if (_baz.lira) return _tr.format(v);
    final c = _baz.cevir(v);
    final birim = _baz.etkinBirim;
    if (birim == BaseCurrency.gold) {
      // Gram: 0 ondalık istenen yerde bile 1 hane — 3,4 gr ile 3 gr farklı.
      return '${fmtNum(c, digits: _digits == 0 ? 1 : _digits)} ${birim.sembol}';
    }
    return tryFormatter(digits: _digits, symbol: birim.sembol).format(c);
  }
}
