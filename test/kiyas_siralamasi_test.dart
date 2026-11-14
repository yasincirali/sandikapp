import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/services/kiyas_siralamasi.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';

/// "Bu dönemde sıralama" cümlesi (Ar-Ge 14 Kas 22:03, YAP 3).
void main() {
  final tr = lookupAppLocalizations(const Locale('tr'));
  final en = lookupAppLocalizations(const Locale('en'));

  KiyasGetirisi g(String t, String ad, double pct) =>
      (ticker: t, ad: ad, pct: pct);
  final portfoy = g(PortfolioSeries.mine, 'Portföyüm', 9.3);
  final altin = g('ALTIN_GRAM', 'Gram altın', 12.4);
  final bist = g('XU100.IS', 'BIST 100', 6.2);
  final dolar = g('USDTRY=X', 'Dolar', 1);
  final tufe = g(TufeSeries.ticker, 'TÜFE', 2.5);

  test('üçten az seride cümle yok', () {
    expect(kiyasSiralamasiKur([portfoy, altin]), isNull);
    expect(kiyasSiralamasiKur([portfoy, altin, g('X', 'X', double.nan)]),
        isNull);
  });

  test('portföy ortada: lider, sıra, alttaki ve üstteki fark', () {
    final s = kiyasSiralamasiKur([portfoy, bist, altin])!;
    expect(s.portfoySirasi, 2);
    expect(
        s.cumle(tr),
        'Önde Gram altın: +%12,40. Portföyün 2. sırada: '
        'BIST 100 karşısında 3,1 puan önde, '
        'Gram altın karşısında 3,1 puan geride.');
    expect(s.cumle(en), contains('Your portfolio ranks #2'));
  });

  test('portföy önde: lider cümlesi portföyü söyler', () {
    final s = kiyasSiralamasiKur([bist, portfoy, dolar])!;
    expect(s.cumle(tr),
        'Önde portföyün: +%9,30. BIST 100 karşısında 3,1 puan önde.');
  });

  test('portföy yoksa yalnız lider ve sıra', () {
    final s = kiyasSiralamasiKur([dolar, altin, bist])!;
    expect(s.portfoySirasi, isNull);
    expect(s.cumle(tr),
        'Önde Gram altın: +%12,40. Sıra: Gram altın, BIST 100, Dolar.');
  });

  test('TÜFE komşu değilse bağlam cümlesi eklenir', () {
    final s = kiyasSiralamasiKur([portfoy, altin, bist, tufe])!;
    expect(s.tufeninUstunde, isTrue);
    expect(s.cumle(tr), endsWith("Portföyün TÜFE'nin üstünde."));
    // TÜFE portföyün komşusuysa cümle onu zaten puanla söylüyor.
    final k = kiyasSiralamasiKur([portfoy, altin, tufe])!;
    expect(k.tufeninUstunde, isNull);
    expect(k.cumle(tr), isNot(contains("TÜFE'nin")));
  });

  test('eşit getiri başa baş, sıra seçim sırasıyla', () {
    final s = kiyasSiralamasiKur(
        [altin, portfoy, g('ASELS.IS', 'ASELS.IS', 9.3)])!;
    expect(s.portfoySirasi, 2);
    expect(s.cumle(tr), contains('ASELS.IS ile başa baş'));
  });
}
