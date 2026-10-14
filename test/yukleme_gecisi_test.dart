import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sandik_skeleton.dart';

/// İskelet → içerik geçişi (yasin 2026-10-14: "keskin oldu", bayrak
/// `goz_alici`). Kilitlenen: bayrak kapalıyken tek kare (eski davranış),
/// açıkken çapraz solma + boy akışı, aynı anahtarda solma yok, hareketi
/// azalt açıkken tek kare.
void main() {
  tearDown(() => RemoteConfigService.testAcik = {});

  Widget kur(bool yukleniyor,
          {String metin = 'içerik', double boy = 200, bool azalt = false}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: azalt),
          child: Scaffold(
            body: Column(children: [
              SandikYuklemeGecisi(
                yukleniyor: yukleniyor,
                iskelet: const SizedBox(
                    key: Key('iskelet'), height: 80, width: 100),
                icerik: (_) => SizedBox(height: boy, child: Text(metin)),
              ),
            ]),
          ),
        ),
      );

  double opaklik(WidgetTester tester, Finder f) => tester
      .widget<FadeTransition>(
          find.ancestor(of: f, matching: find.byType(FadeTransition)).first)
      .opacity
      .value;

  testWidgets('bayrak kapalı: tek karede değişir, animasyon katmanı yok',
      (tester) async {
    await tester.pumpWidget(kur(true));
    await tester.pumpWidget(kur(false));
    expect(find.byKey(const Key('iskelet')), findsNothing);
    expect(find.text('içerik'), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.byType(AnimatedSize), findsNothing);
  });

  testWidgets('bayrak açık: iskelet söner, içerik belirir, boy akar',
      (tester) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    await tester.pumpWidget(kur(true));
    await tester.pumpWidget(kur(false));
    await tester.pump(SandikMotion.surface ~/ 2);

    // Yarı yolda ikisi de ağaçta; iskelet çıkış eğrisiyle büyük ölçüde
    // sönmüş, içerik görünür hâle gelmiş.
    expect(find.byKey(const Key('iskelet')), findsOneWidget);
    expect(find.text('içerik'), findsOneWidget);
    expect(opaklik(tester, find.byKey(const Key('iskelet'))), lessThan(0.3));
    expect(opaklik(tester, find.text('içerik')), greaterThan(0.6));

    // Boy 80'den 200'e tek karede sıçramaz.
    final ara = tester.getSize(find.byType(AnimatedSize)).height;
    expect(ara, greaterThan(80));
    expect(ara, lessThan(200));

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('iskelet')), findsNothing);
    expect(tester.getSize(find.byType(AnimatedSize)).height, 200);
  });

  testWidgets('içerik geldikten sonra yeniden kurulum solma oynatmaz',
      (tester) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    await tester.pumpWidget(kur(false, metin: '₺100'));
    await tester.pumpAndSettle();
    // Fiyat tiki: yeni rakam İLK karede yazılır, eskisi hiç görünmez.
    await tester.pumpWidget(kur(false, metin: '₺101'));
    expect(find.text('₺100'), findsNothing);
    expect(find.text('₺101'), findsOneWidget);
    expect(opaklik(tester, find.text('₺101')), 1);
  });

  testWidgets('hareketi azalt: bayrak açıkken de tek kare', (tester) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    await tester.pumpWidget(kur(true, azalt: true));
    await tester.pumpWidget(kur(false, azalt: true));
    expect(find.byKey(const Key('iskelet')), findsNothing);
    expect(find.byType(AnimatedSize), findsNothing,
        reason: 'sıfır süreli AnimatedSize assert verir (#96)');
  });

  testWidgets('SandikIcerikGecisi: anahtar değişince eski içerik söner',
      (tester) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    Widget gecis(String donem) => MaterialApp(
          home: Scaffold(
            body: SandikIcerikGecisi(anahtar: donem, child: Text('özet $donem')),
          ),
        );
    await tester.pumpWidget(gecis('1A'));
    await tester.pumpWidget(gecis('1Y'));
    await tester.pump(SandikMotion.surface ~/ 2);
    expect(find.text('özet 1A'), findsOneWidget);
    expect(find.text('özet 1Y'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('özet 1A'), findsNothing);
  });
}
