import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/demo/demo_modu.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/signal_frequency.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/sinyal_on_ayar_provider.dart';
import 'package:portfoy_takip/screens/signal_settings_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sadeleştirme 2 — Sinyal ön ayarı (bayrak `sinyal_on_ayar`).
///
/// Kilitlenen davranışlar:
/// 1. Bugünkü varsayılanlar = "Dengeli" (uydurma ön ayar yok).
/// 2. Hiçbir ön ayara birebir uymayan kayıt "Özel" (`null`) okunur.
/// 3. Premium göstergeler eşleşmeye girmez ve uygulamada korunur.
/// 4. Bayrak kapalı: ekran eskisi gibi (soru yok, kategoriler açık).
/// 5. Bayrak açık: soru + segment; kategoriler katlı; ön ayar seçmek tüm
///    kategorilere yazar.
Map<AssetType, int> _esikler(int v) => {for (final t in AssetType.values) t: v};
Map<AssetType, SignalSchedule> _zaman(SignalSchedule s) =>
    {for (final t in AssetType.values) t: s};
Map<AssetType, Set<String>> _gosterge(Set<String> Function(AssetType) f) =>
    {for (final t in AssetType.values) t: f(t)};

SinyalOnAyar? _eslesen({
  Map<AssetType, int>? esik,
  Map<AssetType, SignalSchedule>? zaman,
  Map<AssetType, Set<String>>? gosterge,
}) =>
    sinyalOnAyarEslesen(
      esikler: esik ?? _esikler(kSignalThresholdDefault),
      zamanlamalar: zaman ?? _zaman(kDefaultSchedule),
      gostergeler:
          gosterge ?? _gosterge(TechnicalAnalysisService.defaultEnabledFor),
    );

void main() {
  group('eşleme (saf)', () {
    test('bugünkü varsayılanlar = Dengeli', () {
      expect(_eslesen(), SinyalOnAyar.dengeli);
      // Boş haritalar (hiç kayıt yok) da notifier varsayılanlarıyla okunur.
      expect(
          sinyalOnAyarEslesen(
              esikler: const {}, zamanlamalar: const {}, gostergeler: const {}),
          SinyalOnAyar.dengeli);
      final d = sinyalOnAyarTanimi(SinyalOnAyar.dengeli, AssetType.hisse);
      expect(d.esik, kSignalThresholdDefault);
      expect(d.siklik, kDefaultSchedule.frequency);
      expect(d.saatler, kDefaultSchedule.hours);
      expect(d.gostergeler,
          TechnicalAnalysisService.defaultEnabledFor(AssetType.hisse));
    });

    test('Az ve Çok tanımları', () {
      final az = sinyalOnAyarTanimi(SinyalOnAyar.az, AssetType.fon);
      expect(az.esik, 85);
      expect(az.siklik, SignalFrequency.daily);
      expect(az.saatler, [11]);
      expect(az.gostergeler, {IndicatorId.rsi, IndicatorId.macd});
      final cok = sinyalOnAyarTanimi(SinyalOnAyar.cok, AssetType.fon);
      expect(cok.esik, 50);
      expect(cok.siklik, SignalFrequency.every2h);
      expect(cok.gostergeler.intersection(IndicatorId.premium), isEmpty);
      expect(cok.gostergeler,
          IndicatorId.all.toSet().difference(IndicatorId.premium));

      expect(
          _eslesen(
            esik: _esikler(85),
            zaman: _zaman((frequency: SignalFrequency.daily, hours: [11])),
            gosterge: _gosterge((_) => {IndicatorId.rsi, IndicatorId.macd}),
          ),
          SinyalOnAyar.az);
      // Periyodik sıklıkta kayıtlı saatler eşleşmeyi bozmaz.
      expect(
          _eslesen(
            esik: _esikler(50),
            zaman: _zaman((frequency: SignalFrequency.every2h, hours: [13])),
          ),
          SinyalOnAyar.cok);
    });

    test('tek kategoride sapma → Özel (null)', () {
      expect(
          _eslesen(esik: {..._esikler(70), AssetType.altin: 85}), isNull);
      expect(
          _eslesen(
              zaman: {
            ..._zaman(kDefaultSchedule),
            AssetType.fon: (frequency: SignalFrequency.twiceDaily, hours: [10, 14]),
          }),
          isNull);
      expect(
          _eslesen(gosterge: {
            ..._gosterge(TechnicalAnalysisService.defaultEnabledFor),
            AssetType.kripto: {IndicatorId.rsi},
          }),
          isNull);
    });

    test('Premium göstergeler eşleşmeye girmez', () {
      expect(
          _eslesen(
              gosterge: _gosterge((t) => {
                    ...TechnicalAnalysisService.defaultEnabledFor(t),
                    IndicatorId.adx,
                  })),
          SinyalOnAyar.dengeli);
    });

    test('mevduat eşleşmeye girmez (ayar ekranında yok)', () {
      expect(sinyalOnAyarTurleri, isNot(contains(AssetType.mevduat)));
      expect(_eslesen(esik: {..._esikler(70), AssetType.mevduat: 50}),
          SinyalOnAyar.dengeli);
    });
  });

  group('ekran', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // Demo: tercih diske ve sunucuya yazılmaz, yalnız bellekte değişir.
      DemoModu.ac();
    });
    tearDown(() {
      DemoModu.kapat();
      RemoteConfigService.testAcik = {};
    });

    Future<ProviderContainer> pump(WidgetTester tester) async {
      // Geniş: test fontu (Ahem) DM Sans'tan geniş; 390pt'de eşik satırı
      // bayrak kapalıyken de taşıyor (ekranın kendi hâli, bu işin dışı).
      tester.view.physicalSize = const Size(900 * 3, 3000 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: ThemeData.dark(), home: const SignalSettingsScreen()),
      ));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('bayrak kapalı: soru yok, kategoriler açık', (tester) async {
      await pump(tester);
      expect(find.text('Ne sıklıkta haber verelim?'), findsNothing);
      expect(find.text('Kategoriye göre özelleştir'), findsNothing);
      expect(find.text('Bildirim eşiği'), findsWidgets);
      expect(find.text('Nötr sinyalleri de bildir'), findsOneWidget);
    });

    testWidgets('bayrak açık: soru + Dengeli, kategoriler katlı',
        (tester) async {
      RemoteConfigService.testAcik = {'sinyal_on_ayar'};
      final c = await pump(tester);
      expect(find.text('Ne sıklıkta haber verelim?'), findsOneWidget);
      expect(find.text('Az'), findsOneWidget);
      expect(find.text('Dengeli'), findsOneWidget);
      expect(find.text('Çok'), findsOneWidget);
      expect(find.textContaining('Önerilen'), findsOneWidget);
      expect(find.text('Özel'), findsNothing);
      expect(find.text('Nötr sinyalleri de bildir'), findsOneWidget);
      expect(find.text('Bildirim eşiği'), findsNothing);

      // Az: tüm kategorilere yazar; Premium dışında hiçbir şeye dokunmaz.
      await tester.tap(find.text('Az'));
      await tester.pumpAndSettle();
      expect(c.read(sinyalOnAyarProvider), SinyalOnAyar.az);
      for (final t in sinyalOnAyarTurleri) {
        expect(c.read(signalThresholdProvider)[t], 85);
        expect(c.read(signalScheduleProvider)[t]!.frequency,
            SignalFrequency.daily);
      }
      expect(find.textContaining('Yalnız güçlü'), findsOneWidget);

      // Kategoriye göre özelleştir: eski ayarlar birebir açılır.
      await tester.tap(find.text('Kategoriye göre özelleştir'));
      await tester.pumpAndSettle();
      expect(find.text('Bildirim eşiği'), findsWidgets);
    });

    testWidgets('bayrak açık: kayıt hiçbir ön ayara uymuyorsa Özel',
        (tester) async {
      RemoteConfigService.testAcik = {'sinyal_on_ayar'};
      final c = await pump(tester);
      await c
          .read(signalThresholdProvider.notifier)
          .setForType(AssetType.altin, 85);
      await tester.pumpAndSettle();
      expect(find.text('Özel'), findsOneWidget);
      expect(find.textContaining('kendi ayarların'), findsOneWidget);
      // Hiçbir şey değişmedi: diğer türler hâlâ varsayılan.
      expect(c.read(signalThresholdProvider)[AssetType.hisse],
          kSignalThresholdDefault);

      // Premium göstergesi açık kullanıcı Çok seçince Premium korunur.
      await c
          .read(indicatorPrefsProvider.notifier)
          .setForType(AssetType.hisse, {IndicatorId.rsi, IndicatorId.adx});
      await tester.tap(find.text('Çok'));
      await tester.pumpAndSettle();
      expect(c.read(sinyalOnAyarProvider), SinyalOnAyar.cok);
      expect(c.read(indicatorPrefsProvider)[AssetType.hisse],
          contains(IndicatorId.adx));
    });
  });
}
