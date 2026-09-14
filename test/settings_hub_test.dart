import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/settings_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';

/// Ayarlar bilgi mimarisi (2026-09-14): sığ hub + dört alt ekran.
///
/// Uzun tek liste (9 bölüm) yerine dört satır; özelliğe ait ayarlar
/// özelliğin yanında (Yarış → Lider tablosu, alarm kurma → varlık ekranı).
/// Delegate'siz MaterialApp → `context.l10n` Türkçe sözlüğe düşer; test aynı
/// sözlükten okur.
final _tr = AppLocalizationsTr();

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  Widget host({SettingsBolum? bolum}) => ProviderScope(
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: SettingsScreen(bolum: bolum),
        ),
      );

  testWidgets('hub dört bölüm sunar, eski anahtarları taşımaz',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    for (final b in SettingsBolum.values) {
      expect(find.text(b.baslikOf(_tr)), findsOneWidget, reason: b.name);
    }
    // Hub'da anahtar/seçici YOK — onlar alt ekranlarda.
    expect(find.text('Sistem'), findsNothing);
    expect(find.text('Sinyal ayarları'), findsNothing);
    expect(find.text('Hesabımı Sil'), findsNothing);
    // Yarış anahtarı Ayarlar'dan çıktı (Lider tablosu ekranında).
    expect(find.textContaining('Yarış'), findsNothing);
  });

  testWidgets('hub satırı alt ekranı açar', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text(SettingsBolum.gorunum.baslikOf(_tr)));
    await tester.pumpAndSettle();
    // "Sistem" iki seçicide de var (tema + dil, 3.20) — en az bir tane.
    expect(find.text('Sistem'), findsAtLeastNWidgets(1));
    expect(find.text('Koyu'), findsOneWidget);
    expect(find.text('USD'), findsOneWidget, reason: 'baz para seçici');
  });

  testWidgets('Hesap & Güvenlik: kilit, indir, sil', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(bolum: SettingsBolum.hesap));
    await tester.pumpAndSettle();
    expect(find.text('Biyometrik kilit'), findsOneWidget);
    expect(find.text('Verilerimi İndir'), findsOneWidget);
    expect(find.text('Hesabımı Sil'), findsOneWidget);
    expect(find.text('Gizlilik Politikası'), findsNothing);
  });

  testWidgets('Yardım & Yasal: destek önce, yasal sonra', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(bolum: SettingsBolum.yardim));
    await tester.pumpAndSettle();
    final destek = tester.getTopLeft(find.text('Bize Ulaş')).dy;
    final yasal = tester.getTopLeft(find.text('Gizlilik Politikası')).dy;
    expect(destek, lessThan(yasal));
    expect(find.text('Tanıtım turunu yeniden izle'), findsOneWidget);
  });

  test('alarm kurma yeri varlık ekranı; Yarış anahtarı lider tablosunda', () {
    String oku(String p) => File(p).readAsStringSync();
    final detay = oku('lib/screens/asset_detail_screen.dart');
    expect(detay.contains('AlarmSeridi('), isTrue);
    expect(detay.contains("tooltip: 'Fiyat alarmı kur'"), isTrue);
    expect(oku('lib/screens/portfolio_screen.dart').contains('_AlarmRozeti('),
        isTrue, reason: 'Portföy kartında alarm rozeti');
    final lider = oku('lib/screens/leaderboard_screen.dart');
    expect(lider.contains('leaderboardOptInProvider.notifier).set(false)'),
        isTrue, reason: 'yarıştan ayrılma lider tablosunda');
    final ayarlar = oku('lib/screens/settings_screen.dart');
    expect(ayarlar.contains('leaderboardOptInProvider'), isFalse);
    // Alarm ekranı kendi Future'ı yerine ortak provider'ı okur.
    final alarm = oku('lib/screens/price_alerts_screen.dart');
    expect(alarm.contains('priceAlertsProvider'), isTrue);
    expect(alarm.contains('class _AlarmKurSheet'), isFalse,
        reason: 'sheet ortak widget (alarm_kur_sheet.dart)');
  });
}
