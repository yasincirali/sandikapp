import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/settings_screen.dart';
import 'package:portfoy_takip/services/biometric_lock_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/gizlilik_perdesi.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ar-Ge 5 Kas 21:20 → müşteri raporu YAP maddeleri: gizlilik perdesi,
/// Yardım'da Sık sorulanlar, biyometrik satırı yöntemi söyler.
final _tr = AppLocalizationsTr();

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  ThemeData tema() => ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      );

  group('Gizlilik perdesi', () {
    Future<void> kur(WidgetTester tester,
        {required bool kilit, required bool ios}) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: tema(),
          home: GizlilikPerdesi(
            iosMu: ios,
            child: const Scaffold(body: Text('₺ 1.250.000')),
          ),
        ),
      ));
      final kap = ProviderScope.containerOf(
          tester.element(find.byType(GizlilikPerdesi)));
      await kap.read(biometricLockProvider.notifier).set(kilit);
      await tester.pump();
    }

    final perde = find.byKey(const ValueKey('gizlilikPerdesi'));

    testWidgets('kilit açık + iOS: arka planda örter, öne dönünce kalkar',
        (tester) async {
      await kur(tester, kilit: true, ios: true);
      expect(perde, findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(perde, findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(perde, findsNothing);
    });

    testWidgets('kilit kapalıyken hiç örtmez', (tester) async {
      await kur(tester, kilit: false, ios: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(perde, findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('Android: örtmez (FLAG_SECURE ayrı karar)', (tester) async {
      await kur(tester, kilit: true, ios: false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(perde, findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  });

  Widget ayarlar(SettingsBolum bolum, {List<Override> ek = const []}) =>
      ProviderScope(
        overrides: ek,
        child: MaterialApp(theme: tema(), home: SettingsScreen(bolum: bolum)),
      );

  testWidgets('Yardım: Sık sorulanlar en üstte, satır yerinde açılır',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ayarlar(SettingsBolum.yardim));
    await tester.pumpAndSettle();

    // Tek başlık (Ar-Ge 7 Kas 04:03 #3): "Yardım ve destek" altında önce
    // sorular; eski ikinci "Destek" başlığı yok.
    expect(find.text(_tr.yardimVeDestek), findsOneWidget);
    final baslik = tester.getTopLeft(find.text(_tr.yardimVeDestek)).dy;
    final ilkSoru = tester.getTopLeft(find.byKey(const ValueKey('sss0'))).dy;
    expect(baslik, lessThan(ilkSoru));
    expect(find.text(_tr.sssFonCevap), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sss0')));
    await tester.pumpAndSettle();
    expect(find.text(_tr.sssFonCevap), findsOneWidget);
    expect(find.byKey(const ValueKey('sssBizeYaz0')), findsOneWidget);

    // Tek satır açık kalır: başka soru açılınca öncekisi kapanır.
    await tester.tap(find.byKey(const ValueKey('sss2')));
    await tester.pumpAndSettle();
    expect(find.text(_tr.sssFonCevap), findsNothing);
    expect(find.text(_tr.sssKriptoCevap), findsOneWidget);

    // Satırlar 44 pt dokunma alanı.
    expect(tester.getSize(find.byKey(const ValueKey('sss0'))).height,
        greaterThanOrEqualTo(SandikTouch.min));
  });

  testWidgets('Hesap: biyometrik satırı cihazın yöntemini söyler',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ayarlar(SettingsBolum.hesap, ek: [
      kilitYontemiProvider.overrideWith((ref) async => KilitYontemi.faceId),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Face ID ile kilitle'), findsOneWidget);
    expect(find.text(_tr.biometricLock), findsNothing);
  });

  testWidgets('Bildirimler: sayfa başlığı altında ikinci "Bildirimler" yok',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ayarlar(SettingsBolum.bildirimler));
    await tester.pumpAndSettle();
    // Üst barda bir kez; liste içinde grup başlığı olarak tekrar etmez.
    expect(find.text(_tr.notificationsUpper), findsOneWidget);
  });
}
