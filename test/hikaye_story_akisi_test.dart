import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/hikaye_akisi.dart';

/// Hikâye kabuğunun story akışı (yasin 2026-10-12: "yıl özeti story gibi
/// akmıyor"; bayrak `goz_alici`).
///
/// Sözleşme:
/// - bayrak kapalıyken eski davranış: kendiliğinden geçmez, dokunmak
///   sayfa değiştirmez;
/// - açıkken sayfa [HikayeAkisi.sayfaSuresi] sonra geçer, son sayfada durur;
/// - sağa dokunmak ileri, sol üçte bire dokunmak geri;
/// - basılı tutmak durdurur;
/// - "hareketi azalt" ya da ekran okuyucu açıkken kendiliğinden geçmez,
///   dokunarak geçiş kalır.
void main() {
  tearDown(() => RemoteConfigService.testAcik = {});

  Widget kabuk({bool azalt = false, bool okuyucu = false, VoidCallback? bitti}) =>
      MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            disableAnimations: azalt,
            accessibleNavigation: okuyucu,
          ),
          child: Scaffold(
            body: HikayeAkisi(
              devamMetni: 'Devam',
              sonEylemMetni: 'Paylaş',
              onBitti: bitti ?? () {},
              sayfalar: [
                for (var i = 1; i <= 3; i++)
                  HikayeSayfasi(
                    ust: 'Üst $i',
                    baslik: 'Sayfa $i',
                    alt: 'Alt $i',
                    renk: const Color(0xFFF5A623),
                  ),
              ],
            ),
          ),
        ),
      );

  Future<void> sagaDokun(WidgetTester t) =>
      t.tapAt(t.getCenter(find.byType(PageView)) + const Offset(120, 0));
  Future<void> solaDokun(WidgetTester t) =>
      t.tapAt(t.getTopLeft(find.byType(PageView)) + const Offset(30, 300));

  testWidgets('bayrak kapalı: kendiliğinden geçmez, dokunmak geçirmez',
      (t) async {
    await t.pumpWidget(kabuk());
    await t.pump(HikayeAkisi.sayfaSuresi * 2);
    expect(find.text('Sayfa 1'), findsOneWidget);
    await sagaDokun(t);
    await t.pump();
    expect(find.text('Sayfa 1'), findsOneWidget);
  });

  testWidgets('açık: süre dolunca geçer, son sayfada durur', (t) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    await t.pumpWidget(kabuk());
    await t.pump();
    await t.pump(HikayeAkisi.sayfaSuresi ~/ 2);
    expect(find.text('Sayfa 1'), findsOneWidget);
    await t.pump(HikayeAkisi.sayfaSuresi);
    await t.pump();
    expect(find.text('Sayfa 2'), findsOneWidget);
    await t.pump(HikayeAkisi.sayfaSuresi * 3);
    await t.pumpAndSettle();
    expect(find.text('Sayfa 3'), findsOneWidget);
    expect(find.text('Paylaş'), findsOneWidget);
  });

  testWidgets('açık: sağ ileri, sol geri; geçiş kesme', (t) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    await t.pumpWidget(kabuk());
    await t.pump();
    await sagaDokun(t);
    await t.pump();
    // Kesme: tek karede yeni sayfa, kayma animasyonu yok.
    expect(find.text('Sayfa 2'), findsOneWidget);
    expect(find.text('Sayfa 1'), findsNothing);
    await solaDokun(t);
    await t.pump();
    expect(find.text('Sayfa 1'), findsOneWidget);
  });

  testWidgets('açık: basılı tutmak durdurur', (t) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    await t.pumpWidget(kabuk());
    await t.pump();
    final g = await t.startGesture(t.getCenter(find.byType(PageView)));
    await t.pump(const Duration(seconds: 1));
    await t.pump(HikayeAkisi.sayfaSuresi * 2);
    expect(find.text('Sayfa 1'), findsOneWidget);
    await g.up();
    await t.pump(); // sayaç bu karede yeniden başlar
    await t.pump(HikayeAkisi.sayfaSuresi + const Duration(seconds: 1));
    await t.pump();
    expect(find.text('Sayfa 2'), findsOneWidget);
  });

  for (final (ad, azalt, okuyucu) in [
    ('hareketi azalt', true, false),
    ('ekran okuyucu', false, true),
  ]) {
    testWidgets('açık, $ad: kendiliğinden geçmez, dokununca geçer',
        (t) async {
      RemoteConfigService.testAcik = {'goz_alici'};
      await t.pumpWidget(kabuk(azalt: azalt, okuyucu: okuyucu));
      await t.pump(HikayeAkisi.sayfaSuresi * 2);
      expect(find.text('Sayfa 1'), findsOneWidget);
      await t.tap(find.text('Devam'));
      await t.pump();
      expect(find.text('Sayfa 2'), findsOneWidget);
    });
  }
}
