import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/varlik_istatistik.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/donem_secici.dart';
import 'package:portfoy_takip/widgets/varlik_ozeti.dart';

import 'helpers/kaynak.dart';

/// Dönem getirisinde "veri bu döneme yetmiyor" (2026-10-23, Ar-Ge #1):
/// 8 aylık fonda "5Y" çipi 8 ayın getirisini yazıyordu.
void main() {
  final simdi = DateTime(2026, 10, 23, 12);
  const gun = 86400000;
  int gunOnce(int n) => simdi.millisecondsSinceEpoch - n * gun;

  group('eksikKapsamGunu', () {
    test('8 aylık seri 5Y için eksik, kapsanan ~240 gün', () {
      final k = DonemIstatistigi.eksikKapsamGunu(
          ilkTs: gunOnce(240), periodDays: 1825, simdi: simdi);
      expect(k, 240);
    });

    test('dönem başını birkaç gün kaçıran seri eksik sayılmaz', () {
      // 1Y: pay %20 = 73 gün. 30 gün geç başlayan seri yeterli.
      expect(
          DonemIstatistigi.eksikKapsamGunu(
              ilkTs: gunOnce(335), periodDays: 365, simdi: simdi),
          isNull);
      // 1A: pay en az 10 gün (hafta sonu + bayram).
      expect(
          DonemIstatistigi.eksikKapsamGunu(
              ilkTs: gunOnce(21), periodDays: 30, simdi: simdi),
          isNull);
      expect(
          DonemIstatistigi.eksikKapsamGunu(
              ilkTs: gunOnce(15), periodDays: 30, simdi: simdi),
          15);
    });

    test('GÜNLÜK ve 1H hiç kontrol edilmez', () {
      expect(
          DonemIstatistigi.eksikKapsamGunu(
              ilkTs: gunOnce(1), periodDays: 7, simdi: simdi),
          isNull);
      expect(
          DonemIstatistigi.eksikKapsamGunu(
              ilkTs: simdi.millisecondsSinceEpoch, periodDays: 1, simdi: simdi),
          isNull);
    });

    test('hesapla simdi ile kapsamı taşır, simdisiz eski davranış', () {
      final seri = {gunOnce(240): 10.0, gunOnce(1): 12.0};
      final ist = DonemIstatistigi.hesapla(seri,
          periodDays: 1825, simdi: simdi)!;
      expect(ist.kapsamEksik, isTrue);
      expect(ist.kapsananGun, 240);
      // Yüzde değişmez: sayı doğru, etiketi değişir.
      expect(ist.degisimPct, closeTo(20, 1e-9));
      expect(DonemIstatistigi.hesapla(seri, periodDays: 1825)!.kapsamEksik,
          isFalse);
    });
  });

  Widget uygulama(Widget cocuk) => MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: Scaffold(body: cocuk),
      );

  testWidgets('eksik dönem çipi "—" yazar, ekran okuyucu nedenini söyler',
      (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(uygulama(Padding(
      padding: const EdgeInsets.all(SandikSpace.md),
      child: DonemSecici(
        donemler: SummaryPeriod.values,
        secili: 5,
        getiriler: const [0.1, 1.2, 3.4, 5.6, 7.8, 9.1, 34.0],
        eksik: const [false, false, false, false, false, false, true],
        onSec: (_) {},
      ),
    )));
    await t.pump();
    expect(find.text('—'), findsOneWidget);
    expect(find.text('+%34,0'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('5 yıl, Bu dönem için yeterli veri yok')),
        findsOneWidget);
    h.dispose();
  });

  testWidgets('başlık etiketi kapsanan süreyi yazar', (t) async {
    late String ay, gunluk;
    await t.pumpWidget(uygulama(Builder(builder: (c) {
      ay = donemKapsamEtiketi(c, 240);
      gunluk = donemKapsamEtiketi(c, 40);
      return const SizedBox();
    })));
    expect(ay, 'son 8 ay (veri bu kadar)');
    expect(gunluk, 'son 40 gün (veri bu kadar)');
  });

  test('iki varlık yüzeyi de kapsamı geçirir', () {
    for (final y in [
      'lib/screens/varlik_sayfasi.dart',
      'lib/screens/asset_detail_screen.dart',
    ]) {
      final k = ekranKaynagiSync(y);
      expect(k.contains('eksik:'), isTrue, reason: y);
      expect(k.contains('donemKapsamEtiketi('), isTrue, reason: y);
    }
  });
}
