import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/demo/demo_modu.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/bildirim_on_ayar_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/sinyal_on_ayar_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/bildirim_on_ayar_karti.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ayarlar › Bildirimler — tek seçici "Az · Dengeli · Çok" (2026-10-20).
///
/// Kilitlenenler:
///   1. Hiç dokunmamış kullanıcı = Dengeli (uydurma ön ayar yok).
///   2. Her ön ayar kendi yazdığı değerlerden geri okunur (gidiş-dönüş).
///   3. Hiçbirine uymayan kayıt "Özel" (`null`); hiçbir şey yazılmaz.
///   4. Az, sinyal kategori ayarlarına dokunmaz (yeniden açılınca dursun).
///   5. Premium kapısı Sinyal Ayarları'ndaki kartla aynı kural.
///   6. Kart: seçmek sunucu tercihlerine + sinyal anahtarına yazar.
BildirimDurumu _durum(BildirimOnAyarTanimi t, {SinyalOnAyar? sinyalOnAyar}) => (
      sinyal: t.sinyal,
      sinyalOnAyar: sinyalOnAyar ?? t.sinyalOnAyar,
      ortakHareketi: t.ortakHareketi,
      donemOzeti: t.donemOzeti,
    );

/// Sunucuya gitmeyen tercih kaynağı: yazılanı bellekte tutar.
class _SahteSunucu extends SunucuBildirimTercihleriNotifier {
  _SahteSunucu(this._ilk);
  final SunucuBildirimTercihleri _ilk;

  @override
  Future<SunucuBildirimTercihleri> build() async => _ilk;

  @override
  Future<void> ayarla({bool? ortakHareketi, bool? donemOzeti}) async {
    final o = state.value!;
    state = AsyncData((
      ortakHareketi: ortakHareketi ?? o.ortakHareketi,
      donemOzeti: donemOzeti ?? o.donemOzeti,
    ));
  }
}

void main() {
  group('eşleme (saf)', () {
    test('bugünkü varsayılanlar = Dengeli', () {
      expect(
          bildirimOnAyarEslesen((
            sinyal: true,
            sinyalOnAyar: SinyalOnAyar.dengeli,
            ortakHareketi: true,
            donemOzeti: true,
          )),
          BildirimOnAyar.dengeli);
    });

    test('her ön ayar kendi değerlerinden geri okunur', () {
      for (final a in BildirimOnAyar.values) {
        expect(bildirimOnAyarEslesen(_durum(bildirimOnAyarTanimi(a))), a,
            reason: a.name);
      }
    });

    test('Az: sinyal kapalıyken saklı sinyal ön ayarı fark etmez', () {
      final az = bildirimOnAyarTanimi(BildirimOnAyar.az);
      expect(az.sinyalOnAyar, isNull,
          reason: 'Az sinyal kategori ayarlarına yazmaz');
      for (final s in [null, ...SinyalOnAyar.values]) {
        expect(
            bildirimOnAyarEslesen((
              sinyal: false,
              sinyalOnAyar: s,
              ortakHareketi: false,
              donemOzeti: false,
            )),
            BildirimOnAyar.az);
      }
    });

    test('karışık kayıt = Özel', () {
      // Sinyal kapalı ama dönem özeti açık.
      expect(
          bildirimOnAyarEslesen((
            sinyal: false,
            sinyalOnAyar: null,
            ortakHareketi: false,
            donemOzeti: true,
          )),
          isNull);
      // Her şey açık ama sinyaller kendi ayarlı (Özel sinyal ön ayarı).
      expect(
          bildirimOnAyarEslesen((
            sinyal: true,
            sinyalOnAyar: null,
            ortakHareketi: true,
            donemOzeti: true,
          )),
          isNull);
      // Sinyal Az ön ayarı, genel ön ayarların hiçbirine uymaz.
      expect(
          bildirimOnAyarEslesen((
            sinyal: true,
            sinyalOnAyar: SinyalOnAyar.az,
            ortakHareketi: true,
            donemOzeti: true,
          )),
          isNull);
    });

    test('Premium kapısı Sinyal Ayarları kartıyla aynı kural', () {
      int gunluk(SinyalOnAyar s) =>
          sinyalOnAyarTanimi(s, AssetType.hisse).siklik.gunlukEnFazla;
      const sinirsiz = 1 << 30;
      for (final a in BildirimOnAyar.values) {
        expect(bildirimOnAyariPremiumIster(a, sinirsiz), isFalse,
            reason: '${a.name}: Premium/sınırsız kullanıcı');
      }
      // Az sinyali kapatır → hiçbir sınırda Premium istemez.
      expect(bildirimOnAyariPremiumIster(BildirimOnAyar.az, 0), isFalse);
      final cok = gunluk(SinyalOnAyar.cok);
      expect(bildirimOnAyariPremiumIster(BildirimOnAyar.cok, cok - 1), isTrue);
      expect(bildirimOnAyariPremiumIster(BildirimOnAyar.cok, cok), isFalse);
    });
  });

  group('kart', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // Demo: sinyal tercihleri sunucuya yazılmaz, yalnız bellekte değişir.
      DemoModu.ac();
    });
    tearDown(DemoModu.kapat);

    Future<ProviderContainer> pump(
      WidgetTester tester, {
      SunucuBildirimTercihleri sunucu = (ortakHareketi: true, donemOzeti: true),
      int slot = 1 << 30,
      VoidCallback? onPaywall,
      double olcek = 1.0,
      double genislik = 390,
    }) async {
      tester.view.physicalSize = Size(genislik * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [
        sunucuBildirimTercihleriProvider.overrideWith(() => _SahteSunucu(sunucu)),
        sinyalSlotSiniriProvider.overrideWithValue(slot),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(olcek)),
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              extensions: const [SandikPalette.dark],
            ),
            home: Scaffold(
              body: ListView(children: [
                BildirimOnAyarKarti(onPaywall: onPaywall ?? () {}),
              ]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('varsayılan: Dengeli seçili, Özel yok', (tester) async {
      await pump(tester);
      expect(find.text('Bildirimler ne sıklıkta gelsin?'), findsOneWidget);
      expect(find.text('Özel'), findsNothing);
      expect(find.textContaining('Önerilen'), findsOneWidget);
    });

    testWidgets('Az: sunucu tercihleri + sinyal anahtarı kapanır',
        (tester) async {
      final c = await pump(tester);
      final sinyalOnce = c.read(sinyalOnAyarProvider);
      await tester.tap(find.text('Az'));
      await tester.pumpAndSettle();
      expect(c.read(signalNotificationsProvider), isFalse);
      expect(c.read(sunucuBildirimTercihleriProvider).value,
          (ortakHareketi: false, donemOzeti: false));
      expect(c.read(sinyalOnAyarProvider), sinyalOnce,
          reason: 'Az sinyal kategori ayarlarına dokunmaz');
      expect(c.read(bildirimOnAyarProvider).value, BildirimOnAyar.az);
      expect(find.textContaining('Yalnız kurduğun'), findsOneWidget);

      // Geri Dengeli: hepsi yeniden açılır.
      await tester.tap(find.text('Dengeli'));
      await tester.pumpAndSettle();
      expect(c.read(signalNotificationsProvider), isTrue);
      expect(c.read(bildirimOnAyarProvider).value, BildirimOnAyar.dengeli);
    });

    testWidgets('karışık kayıt: Özel görünür, hiçbir şey yazılmaz',
        (tester) async {
      final c = await pump(tester,
          sunucu: (ortakHareketi: false, donemOzeti: true));
      expect(find.text('Özel'), findsOneWidget);
      expect(find.textContaining('tek tek'), findsOneWidget);
      expect(c.read(signalNotificationsProvider), isTrue);
      expect(c.read(sunucuBildirimTercihleriProvider).value,
          (ortakHareketi: false, donemOzeti: true));
    });

    testWidgets('Premium sınırı: Çok paywall açar, hiçbir şey yazılmaz',
        (tester) async {
      var paywall = 0;
      final c = await pump(tester, slot: 1, onPaywall: () => paywall++);
      await tester.tap(find.text('Çok'));
      await tester.pumpAndSettle();
      expect(paywall, 1);
      expect(c.read(bildirimOnAyarProvider).value, BildirimOnAyar.dengeli);
    });

    for (final (w, olcek) in const [(320.0, 1.0), (320.0, 2.0), (430.0, 3.1)]) {
      testWidgets('${w.toInt()}pt, $olcek× yazı: taşma yok, segment ≥44pt',
          (tester) async {
        await pump(tester, genislik: w, olcek: olcek,
            sunucu: (ortakHareketi: false, donemOzeti: true));
        expect(tester.takeException(), isNull);
        for (final t in ['Az', 'Dengeli', 'Çok']) {
          expect(tester.getSize(find.text(t)).height, greaterThan(0));
        }
        final segment = tester.getSize(find
            .ancestor(of: find.text('Dengeli'), matching: find.byType(Row))
            .first);
        expect(segment.height, greaterThanOrEqualTo(44));
      });
    }
  });
}
