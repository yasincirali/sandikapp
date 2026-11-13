import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/demo/demo_modu.dart';
import 'package:portfoy_takip/models/technical_signal.dart';
import 'package:portfoy_takip/screens/signal_settings_screen.dart';
import 'package:portfoy_takip/services/bildirim_izni.dart';
import 'package:portfoy_takip/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sinyal Ayarları'nın üst satırı (2026-11-13): izin varken örnek
/// bildirim, yokken izne giden yol. Örnek metin gerçek sinyal metniyle
/// aynıdır, yalnız "Örnek: " ile başlar.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DemoModu.ac();
  });
  tearDown(() {
    DemoModu.kapat();
    BildirimIzni.testDurumOkuyucu = null;
    SignalSettingsScreen.ornekBildirimTest = null;
  });

  Future<void> pump(WidgetTester tester, BildirimIzinDurumu durum) async {
    BildirimIzni.testDurumOkuyucu = () async => durum;
    tester.view.physicalSize = const Size(900 * 3, 3000 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
          theme: ThemeData.dark(), home: const SignalSettingsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  test('örnek metin = gerçek sinyal metni + "Örnek: "', () {
    final o = NotificationService.ornekSinyalMesaji();
    final g = NotificationService.buildSignalMessage(
        assetName: 'ABC',
        ticker: 'ABC',
        signal: SignalType.buy,
        buyCount: 2,
        sellCount: 1,
        toplam: 3);
    expect(o.title, 'Örnek: ${g.title}');
    expect(o.body, g.body);
  });

  testWidgets('izin var: örnek gönderilir, onay görünür', (tester) async {
    var cagri = 0;
    SignalSettingsScreen.ornekBildirimTest = () async => cagri++;
    await pump(tester, BildirimIzinDurumu.verildi);
    expect(find.text("Bildirim izni kapalı · Ayarlar'da aç"), findsNothing);
    await tester.tap(find.text('Örnek bildirimi gönder'));
    await tester.pumpAndSettle();
    expect(cagri, 1);
    expect(find.text('Örnek bildirim gönderildi'), findsOneWidget);
    // Satır dokunma hedefi ≥ 44 pt.
    final kutu = tester.getSize(find
        .ancestor(
            of: find.text('Örnek bildirimi gönder'),
            matching: find.byType(ConstrainedBox))
        .first);
    expect(kutu.height, greaterThanOrEqualTo(44));
  });

  testWidgets('izin reddedildi: Ayarlar satırı, örnek yok', (tester) async {
    var cagri = 0;
    SignalSettingsScreen.ornekBildirimTest = () async => cagri++;
    await pump(tester, BildirimIzinDurumu.reddedildi);
    expect(find.text('Örnek bildirimi gönder'), findsNothing);
    expect(find.text("Bildirim izni kapalı · Ayarlar'da aç"), findsOneWidget);
    await tester.tap(find.text("Bildirim izni kapalı · Ayarlar'da aç"));
    await tester.pumpAndSettle();
    expect(cagri, 0);
  });

  testWidgets('izin sorulmadı: izin iste satırı', (tester) async {
    await pump(tester, BildirimIzinDurumu.sorulmadi);
    expect(find.text('Bildirim izni kapalı · İzin ver'), findsOneWidget);
    expect(find.text('Örnek bildirimi gönder'), findsNothing);
  });
}
