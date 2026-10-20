import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/settings_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ayarlar › Bildirimler › "Dönem özeti bildirimleri" (2026-10-17).
///
/// Neden: `profiles.weekly_summary_push` sütununu sunucu 0052'den beri
/// okuyordu ama yazan bir anahtar yoktu (TECHNICAL_DEBT "Dönem özeti
/// push'unun istemcide kapatma anahtarı yok"). Kilitlenenler:
///   · satır bayraksız görünür (yasin 2026-10-17: bayrağı o ister),
///     dar ekranda ve büyük yazıda taşmaz;
///   · istemcinin yazdığı sütun, sunucunun okuduğu sütunla AYNI — biri
///     yeniden adlandırılırsa anahtar sessizce hiçbir şeyi kapatmaz.
const _baslik = 'Dönem özeti bildirimleri';

Future<void> _pump(WidgetTester tester,
    {double width = 390, double olcek = 1.0}) async {
  tester.view.physicalSize = Size(width * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(olcek)),
      child: MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: const SettingsScreen(bolum: SettingsBolum.bildirimler),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  // Tek tek anahtarlar 2026-10-20'den beri "Ayrıntılı" grubunun içinde;
  // üstte Az/Dengeli/Çok ön ayarı var. Satırı görmek için grup açılır.
  await tester.scrollUntilVisible(find.text('AYRINTILI'), 200,
      scrollable: find.byType(Scrollable).first);
  await tester.tap(find.text('AYRINTILI'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  testWidgets('satır var, varsayılan AÇIK görünür',
      (tester) async {
    await _pump(tester);
    await tester.scrollUntilVisible(find.text(_baslik), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(_baslik), findsOneWidget);
    // Oturum yokken sunucu okunmaz; sunucu varsayılanı (açık) gösterilir.
    final anahtar = tester.widget<Switch>(find.descendant(
        of: find
            .ancestor(of: find.text(_baslik), matching: find.byType(Row))
            .first,
        matching: find.byType(Switch)));
    expect(anahtar.value, isTrue);
  });

  for (final (w, olcek) in const [(320.0, 1.0), (320.0, 2.0), (430.0, 3.1)]) {
    testWidgets('${w.toInt()}pt, $olcek× yazı: taşma yok', (tester) async {
        await _pump(tester, width: w, olcek: olcek);
      // Satır listenin altında; tembel listede çizilmeden taşma ölçülemez.
      await tester.scrollUntilVisible(find.text(_baslik), 200,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
      final kutu = tester.getSize(find
          .ancestor(of: find.text(_baslik), matching: find.byType(Row))
          .first);
      // HIG: satır (dokunma alanı Switch'in kendisi) 44pt altına inmez.
      expect(kutu.height, greaterThanOrEqualTo(44));
    });
  }

  test('istemcinin yazdığı sütun sunucunun okuduğu sütunla aynı', () {
    final istemci =
        File('lib/services/supabase_service.dart').readAsStringSync();
    final sunucu =
        File('supabase/functions/weekly-summary/index.ts').readAsStringSync();
    expect(istemci, contains("update({'weekly_summary_push': enabled})"));
    expect(sunucu, contains('weekly_summary_push === false'));
  });
}
