import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/money_format.dart';
import 'package:portfoy_takip/utils/tr_format.dart';

/// Baz para birimi gösterim katmanı (Faz 3.2).
///
/// Kural: TRY tutarı bugünkü kurla bölünür, seçili birimin sembolüyle
/// yazılır; kur yoksa ₺'ye düşülür. ₺ seçiliyken çıktı eski `fmtTRY`/
/// `fmtTRYCompact`/`fmtTRYAxis` ile BİREBİR aynı olmalı — varsayılan
/// davranış değişmedi.
void main() {
  group('₺ varsayılanı eski biçimlendiricilerle birebir', () {
    const baz = BazPara.lira();
    test('fmt / formatter', () {
      expect(baz.fmt(1234567), fmtTRY(1234567));
      expect(baz.formatter(digits: 3).format(12.5), fmtTRY(12.5, digits: 3));
    });
    test('compact / axis', () {
      for (final v in [0.0, 900.0, 1500.0, 2300000.0, -45000.0]) {
        expect(baz.compact(v), fmtTRYCompact(v));
        expect(baz.axis(v, 100000), fmtTRYAxis(v, 100000));
      }
    });
    test('kur 0 ise hangi birim seçilirse seçilsin ₺', () {
      const b = BazPara(BaseCurrency.usd, 0);
      expect(b.lira, isTrue);
      expect(b.sembol, '₺');
      expect(b.fmt(100), fmtTRY(100));
    });
  });

  group('USD / EUR', () {
    const usd = BazPara(BaseCurrency.usd, 40);
    test('tutar kurla bölünür, TR ayraçları korunur', () {
      expect(usd.fmt(4000000), '\$100.000');
      expect(usd.fmt(4000), '\$100');
      expect(usd.formatter(digits: 2).format(50), '\$1,25');
    });
    test('compact ve axis sembolü öne alır', () {
      expect(usd.compact(80000000), '\$2,00M');
      expect(usd.compact(60000), '\$1,5K');
      expect(usd.compact(-4000), '-\$100');
      expect(usd.axis(4000000, 40000), '\$100,0K');
    });
    test('euro sembolü', () {
      const eur = BazPara(BaseCurrency.eur, 50);
      expect(eur.fmt(5000), '€100');
    });
  });

  group('gram altın', () {
    const gold = BazPara(BaseCurrency.gold, 5000);
    test('gram sembolü sonda, 0 ondalık istense bile 1 hane', () {
      expect(gold.fmt(17000), '3,4 gr');
      expect(gold.fmt(5000), '1,0 gr');
      expect(gold.formatter(digits: 2).format(5000), '1,00 gr');
    });
    test('compact', () {
      expect(gold.compact(50000000), '10,0K gr');
      expect(gold.compact(1250000), '250 gr');
      expect(gold.compact(17000), '3,4 gr');
    });
  });

  test('fromIndex bilinmeyen değerde ₺', () {
    expect(BaseCurrency.fromIndex(-1), BaseCurrency.try_);
    expect(BaseCurrency.fromIndex(99), BaseCurrency.try_);
    expect(BaseCurrency.fromIndex(3), BaseCurrency.gold);
  });

  test('ana yüzeyler baz birimi geçiriyor — kaynak taraması', () {
    String oku(String p) => File(p).readAsStringSync();
    expect(oku('lib/screens/home_screen.dart'), contains('baz: baz'));
    expect(oku('lib/screens/portfolio_screen.dart'),
        contains('baz: ref.watch(bazParaProvider)'));
    final perf = oku('lib/screens/portfolio_performance_screen.dart');
    expect(perf, contains('PeriodSummaryView(\n      baz: ref.watch(bazParaProvider)'));
    expect(perf, isNot(contains('tryFormatter(digits: 0)')),
        reason: 'performans ekranında ₺\'ye sabit biçimlendirici kalmamalı');
    expect(oku('lib/widgets/period_summary_view.dart'), isNot(contains('fmtTRY(')));
  });
}
