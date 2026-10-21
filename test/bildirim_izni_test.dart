import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/bildirim_izni.dart';
import 'package:portfoy_takip/widgets/bildirim_izni_uyarisi.dart';

/// "Bildirimler kapalı" satırı (Ar-Ge 16:45 #1, 2026-10-21): izin
/// reddedilmişse alarm/sinyal yüzeylerinde görünür, değilse yer kaplamaz,
/// öne dönüşte yeniden okunur.
void main() {
  tearDown(() => BildirimIzni.testOkuyucu = null);

  Widget sahne() => const MaterialApp(
        home: Scaffold(body: BildirimIzniUyarisi()),
      );

  testWidgets('izin reddedilmişse satır ve Ayarları aç düğmesi görünür',
      (t) async {
    BildirimIzni.testOkuyucu = () async => true;
    await t.pumpWidget(sahne());
    await t.pumpAndSettle();
    expect(find.text('Bildirimler kapalı'), findsOneWidget);
    expect(find.text('Ayarları aç'), findsOneWidget);
  });

  testWidgets('izin varsa ya da bilinmiyorsa hiçbir şey çizilmez', (t) async {
    BildirimIzni.testOkuyucu = () async => false;
    await t.pumpWidget(sahne());
    await t.pumpAndSettle();
    expect(find.text('Bildirimler kapalı'), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('Ayarlar\'dan dönünce (öne dönüş) satır kalkar', (t) async {
    var kapali = true;
    BildirimIzni.testOkuyucu = () async => kapali;
    await t.pumpWidget(sahne());
    await t.pumpAndSettle();
    expect(find.text('Bildirimler kapalı'), findsOneWidget);

    kapali = false;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('Bildirimler kapalı'), findsNothing);
  });

  test(
      'alarm, Fiyat Alarmları ve sinyal ayarları satırı taşır; kanal adı iki uçta aynı',
      () {
    for (final yol in [
      'lib/widgets/alarm_kur_sheet.dart',
      'lib/screens/price_alerts_screen.dart',
      'lib/screens/signal_settings_screen.dart',
    ]) {
      expect(File(yol).readAsStringSync(), contains('BildirimIzniUyarisi('),
          reason: yol);
    }
    const kanal = 'com.sandik.app/ayarlar';
    expect(File('lib/services/bildirim_izni.dart').readAsStringSync(),
        contains("'$kanal'"));
    final kotlin =
        File('android/app/src/main/kotlin/com/sandik/app/MainActivity.kt')
            .readAsStringSync();
    expect(kotlin, contains('"$kanal"'));
    expect(kotlin, contains('"bildirimAyarlari"'));
  });
}
