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
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/gunler_satiri.dart';
import 'package:portfoy_takip/widgets/ozellik_onerisi_karti.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ana sayfa tek dürtü yuvası (2026-10-21): takvim satırı ile özellik
/// önerisi aynı anda görünmez; ×2 ve ×3.1 yazıda taşma yok.
void main() {
  // 21 Eki 2026 12:00 TR (Çarşamba).
  final simdi = DateTime.utc(2026, 10, 21, 9);
  final tcmbYarin =
      GunOlayi(gun: DateTime.utc(2026, 10, 22), tur: GunOlayiTuru.tcmb);
  final temettuCuma = GunOlayi(
      gun: DateTime.utc(2026, 10, 23),
      tur: GunOlayiTuru.temettu,
      kod: 'THYAO');
  final fedUzak =
      GunOlayi(gun: DateTime.utc(2026, 10, 28), tur: GunOlayiTuru.fomc);

  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  final oneriIkonu = find.byIcon(Icons.notifications_active_outlined);

  Future<void> kur(WidgetTester t, List<GunOlayi> olaylar,
      {double olcek = 1.0, double genislik = 390}) async {
    t.view.physicalSize = Size(genislik * 2, 1600);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        veriKalitesiSaatProvider.overrideWithValue(() => simdi),
        veriEksikleriProvider.overrideWithValue(const []),
        ozellikOnerisiProvider.overrideWithValue(OzellikOnerisi.alarm),
        yaklasanGunlerProvider.overrideWith((ref) {
          final k = ref.watch(gunlerKapatilanProvider);
          return [
            for (final o in olaylar)
              if (!k.contains(o.kimlik)) o
          ];
        }),
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
                OzellikOnerisiKarti(anaSayfa: true),
              ],
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('iki gün içinde olay varken yalnız takvim satırı', (t) async {
    await kur(t, [tcmbYarin, fedUzak]);
    expect(find.text('Yarın: TCMB faiz kararı'), findsOneWidget);
    expect(oneriIkonu, findsNothing);
  });

  testWidgets('olay iki günden uzaksa yalnız öneri kartı', (t) async {
    await kur(t, [fedUzak]);
    expect(find.textContaining('faiz kararı'), findsNothing);
    expect(oneriIkonu, findsOneWidget);
  });

  testWidgets('olay yoksa öneri kartı (bugünkü davranış)', (t) async {
    await kur(t, const []);
    expect(oneriIkonu, findsOneWidget);
  });

  testWidgets('kapatınca sıradaki iki gün içindeki olay, sonra öneri',
      (t) async {
    await kur(t, [tcmbYarin, temettuCuma]);
    await t.tap(find.byTooltip('Bu günü gizle'));
    await t.pumpAndSettle();
    expect(find.text('Cuma: THYAO temettü günü'), findsOneWidget);
    expect(oneriIkonu, findsNothing);
    await t.tap(find.byTooltip('Bu günü gizle'));
    await t.pumpAndSettle();
    expect(find.textContaining('temettü günü'), findsNothing);
    expect(oneriIkonu, findsOneWidget);
    // Kapatma kalıcı kayda gider (kişiye özel küme).
    final p = await SharedPreferences.getInstance();
    expect(
        p.getKeys().any((k) =>
            k.contains('pref_gunler_kapatilan') &&
            (p.getStringList(k) ?? const []).contains(tcmbYarin.kimlik)),
        isTrue);
  });

  testWidgets('dokununca 14 günlük liste sayfası açılır', (t) async {
    await kur(t, [tcmbYarin, temettuCuma, fedUzak]);
    await t.tap(find.text('Yarın: TCMB faiz kararı'));
    await t.pumpAndSettle();
    expect(find.text('Yaklaşan günler'), findsOneWidget);
    expect(find.text('22 Ekim Perşembe: TCMB faiz kararı'), findsOneWidget);
    expect(find.text('23 Ekim Cuma: THYAO temettü günü'), findsOneWidget);
    expect(find.text('28 Ekim Çarşamba: Fed faiz kararı'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  for (final olcek in [2.0, 3.1]) {
    testWidgets('×$olcek yazıda satır ve sayfa taşmaz (320 pt)', (t) async {
      await kur(t, [tcmbYarin, temettuCuma, fedUzak],
          olcek: olcek, genislik: 320);
      expect(t.takeException(), isNull);
      // Kapat tuşu ≥44 pt kalır.
      final boy = t.getSize(find.byTooltip('Bu günü gizle'));
      expect(boy.width, greaterThanOrEqualTo(SandikTouch.min));
      expect(boy.height, greaterThanOrEqualTo(SandikTouch.min));
      await t.tap(find.text('Yarın: TCMB faiz kararı'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
