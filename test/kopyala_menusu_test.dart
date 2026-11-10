import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/kopyala_menusu.dart';

import 'helpers/kaynak.dart';

/// Kod ve fiyata uzun bas → kopyala (ücretsiz, 2026-11-10).
void main() {
  late List<MethodCall> cagrilar;
  String? pano;

  setUp(() {
    cagrilar = [];
    pano = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      cagrilar.add(call);
      if (call.method == 'Clipboard.setData') {
        pano = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(WidgetTester tester, {String? fiyat = '₺312,40'}) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [SandikPalette.light]),
      home: Scaffold(
        body: Center(
          child: KopyalaUzunBasma(
            kod: 'THYAO',
            fiyat: fiyat,
            child: const Text('THYAO'),
          ),
        ),
      ),
    ));
  }

  testWidgets('uzun bas: iki satırlı menü; fiyat ekrandaki metinle kopyalanır',
      (tester) async {
    await pump(tester);
    await tester.longPress(find.text('THYAO'));
    await tester.pumpAndSettle();
    expect(find.text('Kodu kopyala'), findsOneWidget);
    expect(find.text('Fiyatı kopyala'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('kopyalaFiyat'))).height,
        greaterThanOrEqualTo(SandikTouch.min));

    await tester.tap(find.text('Fiyatı kopyala'));
    await tester.pumpAndSettle();
    expect(pano, '₺312,40');
    expect(cagrilar.map((c) => c.method), contains('HapticFeedback.vibrate'));
    expect(find.text('Kopyalandı'), findsOneWidget);
  });

  testWidgets('kodu kopyala', (tester) async {
    await pump(tester);
    await tester.longPress(find.text('THYAO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kodu kopyala'));
    await tester.pumpAndSettle();
    expect(pano, 'THYAO');
  });

  testWidgets('fiyat bilinmiyorsa ("—") yalnız kod', (tester) async {
    await pump(tester, fiyat: '—');
    await tester.longPress(find.text('THYAO'));
    await tester.pumpAndSettle();
    expect(find.text('Kodu kopyala'), findsOneWidget);
    expect(find.text('Fiyatı kopyala'), findsNothing);
  });

  testWidgets('ekran okuyucu uzun basma ipucunu duyar', (tester) async {
    final h = tester.ensureSemantics();
    await pump(tester);
    expect(
      tester.getSemantics(find.byType(KopyalaUzunBasma)),
      isSemantics(
        hasLongPressAction: true,
        onLongPressHint: 'kopyalama seçenekleri',
      ),
    );
    h.dispose();
  });

  test('iki varlık yüzeyi de başlık ve fiyatı sarar', () {
    final detay = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    expect(detay, contains('_kopyalanir(pnl, _baslik())'));
    expect(detay, contains('_kopyalanir(pnl, _fiyatBlogu(pnl, baz))'));
    final sayfa = ekranKaynagiSync('lib/screens/varlik_sayfasi.dart');
    expect(sayfa, contains('_kopyalanir(VarlikBasligi(kimlik: k))'));
    expect(sayfa, contains('_kopyalanir(VarlikFiyatBlogu('));
  });
}
