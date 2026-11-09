import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/gunler_provider.dart';
import 'package:portfoy_takip/providers/ozellik_onerisi_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/veri_kalitesi_provider.dart';
import 'package:portfoy_takip/services/ozellik_onerisi.dart';
import 'package:portfoy_takip/services/sunucu_secimi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/gunler_satiri.dart';
import 'package:portfoy_takip/widgets/guncelleme_karti.dart';
import 'package:portfoy_takip/widgets/ozellik_onerisi_karti.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Yumuşak güncelleme kartı (2026-10-23, Ar-Ge): Console'daki önerilen
/// build bu build'in üstündeyse ana sayfada kapatılabilir "Yeni sürüm
/// hazır". Hiçbir şeyi kilitlemez; ana sayfanın tek dürtü yuvasını paylaşır.
void main() {
  group('yumusakGuncellemeGorunur', () {
    test('önerilen build üstteyse görünür', () {
      expect(
          yumusakGuncellemeGorunur(
              mevcutBuild: 100, onerilenBuild: 120, kapatilanBuild: 0),
          isTrue);
    });
    test('tanımsız öneri ya da okunamayan build → görünmez', () {
      expect(
          yumusakGuncellemeGorunur(
              mevcutBuild: 100, onerilenBuild: 0, kapatilanBuild: 0),
          isFalse);
      expect(
          yumusakGuncellemeGorunur(
              mevcutBuild: 0, onerilenBuild: 120, kapatilanBuild: 0),
          isFalse);
    });
    test('güncel ya da daha yeni build → görünmez', () {
      expect(
          yumusakGuncellemeGorunur(
              mevcutBuild: 120, onerilenBuild: 120, kapatilanBuild: 0),
          isFalse);
    });
    test('kapatılan öneri bir daha sorulmaz, daha yenisi sorulur', () {
      expect(
          yumusakGuncellemeGorunur(
              mevcutBuild: 100, onerilenBuild: 120, kapatilanBuild: 120),
          isFalse);
      expect(
          yumusakGuncellemeGorunur(
              mevcutBuild: 100, onerilenBuild: 130, kapatilanBuild: 120),
          isTrue);
    });
  });

  group('tek dürtü sırası', () {
    test('takvim > güncelleme > öneri', () {
      expect(
          anaSayfaDurtusu(
              bilgiEksikGorunur: false,
              takvimOlayi: null,
              oneriVar: true,
              guncellemeVar: true),
          AnaSayfaDurtusu.guncelleme);
      expect(
          anaSayfaDurtusu(
              bilgiEksikGorunur: false,
              takvimOlayi: GunOlayi(
                  gun: DateTime.utc(2026, 10, 24), tur: GunOlayiTuru.tcmb),
              oneriVar: true,
              guncellemeVar: true),
          AnaSayfaDurtusu.takvim);
    });
  });

  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    SunucuSecimi.instance.testIcinKur(
        const SunucuYapilandirmasi(url: 'http://127.0.0.1:54321', anonKey: 'x'),
        mevcutBuild: 100,
        onerilen: 120);
  });
  tearDown(() => SunucuSecimi.instance.testIcinKur(
      const SunucuYapilandirmasi(url: 'http://127.0.0.1:54321', anonKey: 'x')));

  final kartIkonu = find.byIcon(Icons.system_update_rounded);
  final oneriIkonu = find.byIcon(Icons.notifications_active_outlined);

  Future<void> kur(WidgetTester t, {double olcek = 1.0}) async {
    t.view.physicalSize = const Size(390 * 2, 1600);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        veriKalitesiSaatProvider
            .overrideWithValue(() => DateTime.utc(2026, 10, 23, 9)),
        veriEksikleriProvider.overrideWithValue(const []),
        ozellikOnerisiProvider.overrideWithValue(OzellikOnerisi.alarm),
        yaklasanGunlerProvider.overrideWith((ref) => const []),
      ],
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(olcek)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GunlerSatiri(),
                GuncellemeKarti(),
                OzellikOnerisiKarti(anaSayfa: true),
              ],
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('kart görünür, özellik önerisi susar', (t) async {
    await kur(t);
    expect(find.text('Yeni sürüm hazır'), findsOneWidget);
    expect(kartIkonu, findsOneWidget);
    expect(oneriIkonu, findsNothing);
  });

  testWidgets('kapatınca kart gider, öneri yuvaya döner', (t) async {
    await kur(t);
    await t.tap(find.byTooltip('Şimdilik kapat'));
    await t.pumpAndSettle();
    expect(kartIkonu, findsNothing);
    expect(oneriIkonu, findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('pref_guncelleme_kapatilan_build'), 120);
  });

  testWidgets('güncel build kart görmez', (t) async {
    SunucuSecimi.instance.testIcinKur(
        const SunucuYapilandirmasi(url: 'http://127.0.0.1:54321', anonKey: 'x'),
        mevcutBuild: 120,
        onerilen: 120);
    await kur(t);
    expect(kartIkonu, findsNothing);
    expect(oneriIkonu, findsOneWidget);
  });

  for (final olcek in [2.0, 3.1]) {
    testWidgets('×$olcek yazıda taşma yok, kapat ≥44pt', (t) async {
      await kur(t, olcek: olcek);
      expect(t.takeException(), isNull);
      final k = t.getSize(find.byTooltip('Şimdilik kapat'));
      expect(k.width, greaterThanOrEqualTo(SandikTouch.min));
      expect(k.height, greaterThanOrEqualTo(SandikTouch.min));
    });
  }

  test('ana sayfa kartı yuvaya koyar', () {
    final k = ekranKaynagiSync('lib/screens/home_screen.dart');
    expect(k.contains('GuncellemeKarti('), isTrue);
  });
}
