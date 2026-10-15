import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/friendly_error.dart';

/// Ortak onay diyaloğu (`showSandikConfirm`) her genişlik × metin ölçeğinde
/// taşmadan çizilir ve düğme etiketi kesilmez.
///
/// Neden: kilit ekranındaki "Oturumu kapat" onayında düğme 46 pt sabit
/// yükseklikteydi; büyük yazıda etiket iki satıra kırılıp kesiliyordu
/// (iPhone ekran görüntüsü 2026-10-15). `text_scale_overflow_test` yalnız
/// ekranları tarıyordu, diyalog kabuğu kapsam dışıydı.
Future<void> _ac(
  WidgetTester t, {
  required double w,
  required double s,
  String onay = 'Oturumu kapat',
}) async {
  t.view.physicalSize = Size(w, 700);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(extensions: const [SandikPalette.light]),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(s)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showSandikConfirm(
            context: context,
            title: 'Oturumu kapat',
            message: 'Bu hesaptan çıkılacak ve giriş ekranına döneceksin. '
                'Verilerin silinmez; tekrar giriş yaptığında yerinde olur.',
            confirmLabel: onay,
          ),
          child: const Text('aç'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('aç'));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  for (final w in [320.0, 375.0, 430.0]) {
    for (final s in [1.0, 1.3, 1.5, 2.0, 3.1]) {
      testWidgets('${w.toInt()}pt x$s taşmaz, etiket tam görünür', (t) async {
        await _ac(t, w: w, s: s);
        expect(t.takeException(), isNull);
        final etiket = find.text('Oturumu kapat').last;
        final kutu = find
            .ancestor(of: etiket, matching: find.byType(ConstrainedBox))
            .first;
        final e = t.getRect(etiket);
        final k = t.getRect(kutu);
        expect(k.height, greaterThanOrEqualTo(44), reason: 'dokunma alanı');
        expect(
            k.contains(e.topLeft) &&
                k.contains(e.bottomRight - const Offset(0.01, 0.01)),
            isTrue,
            reason: 'etiket kutunun içinde: $e / $k');
        // Vazgeç'e dokunulabiliyor (kaydırma gerekse bile ekranda).
        await t.ensureVisible(find.text('Vazgeç'));
        await t.tap(find.text('Vazgeç'));
        await t.pumpAndSettle();
        expect(find.text('Vazgeç'), findsNothing);
      });
    }
  }

  // Test yazı tipi (Ahem) her harfi 1 em çizer; "Oturumu kapat" 1.0×'te bile
  // yarım genişliğe sığmaz. Yan yana durumu kısa etiketle sınanır.
  testWidgets('kısa etiket yan yana, uzun etiket alt alta (onay üstte)',
      (t) async {
    await _ac(t, w: 375, s: 1.0, onay: 'Sil');
    expect(t.getRect(find.text('Vazgeç')).center.dy,
        closeTo(t.getRect(find.text('Sil')).center.dy, 1));
    await t.tap(find.text('Vazgeç'));
    await t.pumpAndSettle();

    await _ac(t, w: 375, s: 2.0);
    expect(t.getRect(find.text('Oturumu kapat').last).center.dy,
        lessThan(t.getRect(find.text('Vazgeç')).center.dy));
  });
}
