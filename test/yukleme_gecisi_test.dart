import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sandik_skeleton.dart';

/// İskelet → içerik geçişi (yasin 2026-10-14: "keskin oldu"; bayraksız,
/// doğrudan düzeltme). Kilitlenen: çapraz solma + boy akışı, aynı
/// anahtarda solma yok, hareketi azalt açıkken tek kare.
void main() {
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

  testWidgets('iskelet söner, içerik belirir, boy akar',
      (tester) async {
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
    await tester.pumpWidget(kur(false, metin: '₺100'));
    await tester.pumpAndSettle();
    // Fiyat tiki: yeni rakam İLK karede yazılır, eskisi hiç görünmez.
    await tester.pumpWidget(kur(false, metin: '₺101'));
    expect(find.text('₺100'), findsNothing);
    expect(find.text('₺101'), findsOneWidget);
    expect(opaklik(tester, find.text('₺101')), 1);
  });

  testWidgets('hareketi azalt: tek kare', (tester) async {
    await tester.pumpWidget(kur(true, azalt: true));
    await tester.pumpWidget(kur(false, azalt: true));
    expect(find.byKey(const Key('iskelet')), findsNothing);
    expect(find.byType(AnimatedSize), findsNothing,
        reason: 'sıfır süreli AnimatedSize assert verir (#96)');
  });

  testWidgets('SandikIcerikGecisi: anahtar değişince eski içerik söner',
      (tester) async {
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

  testWidgets('SandikBelirme: veri gelince kart sıfır boydan akarak belirir',
      (tester) async {
    Widget kart(bool var_) => MaterialApp(
          home: Scaffold(
            body: Column(children: [
              SandikBelirme(
                child: var_
                    ? const SizedBox(height: 120, child: Text('kart'))
                    : const SizedBox.shrink(),
              ),
              const Text('alttaki'),
            ]),
          ),
        );
    await tester.pumpWidget(kart(false));
    final once = tester.getTopLeft(find.text('alttaki')).dy;
    await tester.pumpWidget(kart(true));
    await tester.pump(SandikMotion.surface ~/ 2);
    final ara = tester.getTopLeft(find.text('alttaki')).dy;
    expect(ara, greaterThan(once), reason: 'kart yer açmaya başladı');
    expect(ara, lessThan(once + 120),
        reason: 'alttaki satır tek karede 120 pt zıplamamalı');
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('alttaki')).dy, once + 120);
  });

  testWidgets('tamEkran: iki katman aynı kutuyu doldurur, boy akışı yok',
      (tester) async {
    Widget kur(String hal) => MaterialApp(
          home: SandikIcerikGecisi(
            tamEkran: true,
            anahtar: hal,
            child: hal == 'yukleniyor'
                ? const ColoredBox(
                    key: Key('yukleyici'), color: Color(0xFF000000))
                : ListView(children: const [Text('gövde')]),
          ),
        );
    await tester.pumpWidget(kur('yukleniyor'));
    await tester.pumpWidget(kur('icerik'));
    await tester.pump(SandikMotion.surface ~/ 2);
    expect(find.byType(AnimatedSize), findsNothing);
    expect(tester.getSize(find.byKey(const Key('yukleyici'))),
        tester.getSize(find.byType(ListView)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('yukleyici')), findsNothing);
  });

  test('hal: when(skipLoadingOnReload) dalıyla aynı', () {
    expect(SandikIcerikGecisi.hal(const [AsyncLoading<int>()]), 'yukleniyor');
    expect(SandikIcerikGecisi.hal(const [AsyncData(1)]), 'icerik');
    expect(
        SandikIcerikGecisi.hal(
            [const AsyncLoading<int>().copyWithPrevious(const AsyncData(1))]),
        'icerik',
        reason: 'yeniden yüklemede gövde kalır');
    expect(SandikIcerikGecisi.hal([AsyncError<int>('x', StackTrace.empty)]),
        'hata');
    expect(
        SandikIcerikGecisi.hal(
            const [AsyncData(1), AsyncLoading<Map<String, int>>()]),
        'yukleniyor',
        reason: 'iç içe when: ikincisi bekliyorsa yükleyici');
  });
}
