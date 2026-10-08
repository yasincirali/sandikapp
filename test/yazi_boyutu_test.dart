import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/config/pref_keys.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/settings_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/theme/yazi_boyutu.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ayarlar › Görünüm › Yazı boyutu (2026-10-03).
///
/// Kilitlenen sözleşme: (1) varsayılan "Normal" cihaz ölçeğine dokunmaz —
/// canlı kullanıcı hiçbir şey değişmiş görmez; (2) büyütme birleşik ölçekte
/// 1.3×'te durur ama cihazın kendi ölçeğini asla aşağı çekmez; (3) seçim
/// kalıcıdır; (4) kademe değişince ağaç yeniden kurulmaz (kullanıcı
/// Ayarlar'dan atılmaz).
void main() {
  group('KullaniciYaziOlcegi', () {
    double olc(double cihaz, YaziBoyutu b) => KullaniciYaziOlcegi(
          cihaz: TextScaler.linear(cihaz),
          carpan: b.carpan,
        ).scale(10);

    test('cihaz 1.0: kademe çarpanı aynen uygulanır', () {
      expect(olc(1.0, YaziBoyutu.kucuk), closeTo(9, 1e-9));
      expect(olc(1.0, YaziBoyutu.normal), closeTo(10, 1e-9));
      expect(olc(1.0, YaziBoyutu.buyuk), closeTo(11, 1e-9));
      expect(olc(1.0, YaziBoyutu.cokBuyuk), closeTo(12, 1e-9));
    });

    test('büyütme birleşik 1.3×\'te durur', () {
      // 1.2 × 1.2 = 1.44 → 1.3
      expect(olc(1.2, YaziBoyutu.cokBuyuk), closeTo(13, 1e-9));
    });

    test('cihaz ölçeği tavanın üstündeyse aşağı çekilmez', () {
      expect(olc(1.5, YaziBoyutu.buyuk), closeTo(15, 1e-9));
      expect(olc(2.0, YaziBoyutu.cokBuyuk), closeTo(20, 1e-9));
    });

    test('küçültme cihaz ölçeğinin üstüne çarpan olarak uygulanır', () {
      expect(olc(1.5, YaziBoyutu.kucuk), closeTo(13.5, 1e-9));
    });

    test('tanınmayan kayıt Normal\'e düşer', () {
      expect(YaziBoyutu.indekstenOku(-1), YaziBoyutu.normal);
      expect(YaziBoyutu.indekstenOku(99), YaziBoyutu.normal);
      expect(YaziBoyutu.indekstenOku(3), YaziBoyutu.cokBuyuk);
    });
  });

  group('YaziBoyutuKapsami', () {
    Future<TextScaler> olcekAltinda(
        WidgetTester tester, YaziBoyutu b, TextScaler cihaz) async {
      late TextScaler gorulen;
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(textScaler: cihaz),
        child: YaziBoyutuKapsami(
          boyut: b,
          child: Builder(builder: (c) {
            gorulen = MediaQuery.textScalerOf(c);
            return const SizedBox();
          }),
        ),
      ));
      return gorulen;
    }

    testWidgets('Normal cihaz ölçeğini AYNEN geçirir', (tester) async {
      const cihaz = TextScaler.linear(1.37);
      expect(await olcekAltinda(tester, YaziBoyutu.normal, cihaz),
          same(cihaz));
    });

    testWidgets('Büyük cihaz ölçeğini sarar', (tester) async {
      final s = await olcekAltinda(
          tester, YaziBoyutu.buyuk, TextScaler.noScaling);
      expect(s.scale(10), closeTo(11, 1e-9));
    });

    testWidgets('CihazYaziOlcegi (alt menü) uygulama ayarından muaf',
        (tester) async {
      const cihaz = TextScaler.linear(1.15);
      late TextScaler gorulen;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: cihaz),
        child: YaziBoyutuKapsami(
          boyut: YaziBoyutu.cokBuyuk,
          child: CihazYaziOlcegi(
            child: Builder(builder: (c) {
              gorulen = MediaQuery.textScalerOf(c);
              return const SizedBox();
            }),
          ),
        ),
      ));
      expect(gorulen, same(cihaz));
    });

    testWidgets('kademe değişince alt ağacın durumu korunur', (tester) async {
      final anahtar = GlobalKey<_SayacState>();
      Widget agac(YaziBoyutu b) => MediaQuery(
            data: const MediaQueryData(),
            child: YaziBoyutuKapsami(boyut: b, child: _Sayac(key: anahtar)),
          );
      await tester.pumpWidget(agac(YaziBoyutu.normal));
      anahtar.currentState!.deger = 7;
      await tester.pumpWidget(agac(YaziBoyutu.cokBuyuk));
      expect(anahtar.currentState!.deger, 7);
      await tester.pumpWidget(agac(YaziBoyutu.normal));
      expect(anahtar.currentState!.deger, 7);
    });
  });

  group('kalıcılık ve Ayarlar', () {
    test('varsayılan Normal; seçim diske yazılır', () async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(yaziBoyutuProvider), YaziBoyutu.normal);

      await c.read(yaziBoyutuIndexProvider.notifier).set(2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefKeys.yaziBoyutu), 2);
      expect(c.read(yaziBoyutuProvider), YaziBoyutu.buyuk);
    });

    test('kayıtlı seçim açılışta senkron okunur', () async {
      SharedPreferences.setMockInitialValues({PrefKeys.yaziBoyutu: 3});
      await initPreferencesCache();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(yaziBoyutuProvider), YaziBoyutu.cokBuyuk);
    });

    for (final w in <double>[320, 360]) {
      testWidgets('${w.toInt()}pt Görünüm: seçici dokununca kademe değişir, '
          'Çok büyük + cihaz 1.6× taşmaz', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await initPreferencesCache();
        tester.view.physicalSize = Size(w * 3, 1400 * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          child: Consumer(builder: (context, ref, _) {
            return MaterialApp(
              theme: ThemeData(
                brightness: Brightness.dark,
                extensions: const [SandikPalette.dark],
              ),
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: YaziBoyutuKapsami(
                    boyut: ref.watch(yaziBoyutuProvider), child: child!),
              ),
              home: const SettingsScreen(bolum: SettingsBolum.gorunum),
            );
          }),
        ));
        await tester.pump();
        final hedef = find.text('Çok büyük');
        await tester.scrollUntilVisible(hedef, 200,
            scrollable: find
                .byWidgetPredicate((w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.down)
                .first);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(hedef);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(PrefKeys.yaziBoyutu), YaziBoyutu.cokBuyuk.index);
      });
    }
  });
}

class _Sayac extends StatefulWidget {
  const _Sayac({super.key});
  @override
  State<_Sayac> createState() => _SayacState();
}

class _SayacState extends State<_Sayac> {
  int deger = 0;
  @override
  Widget build(BuildContext context) => const SizedBox();
}
