import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/zirve_riza_karti.dart';

/// Zirvedeki Portföyler açık rıza kartı (0091).
///
/// Açık rıza "bilgilendirmeye dayalı" olmalı: kart ne paylaşıldığını, ne
/// paylaşılmadığını, karşılığında ne sunulduğunu ve nasıl geri çekileceğini
/// AYRI AYRI söylemeli; tek açık eylem "Katılıyorum" olmalı.
void main() {
  Future<void> pump(WidgetTester tester,
      {required Future<void> Function() onKatil, VoidCallback? onSimdiDegil}) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      // InkSparkle gölgelendiricisi taze derleme ortamında (SkSL yok)
      // yüklenemiyor; dokunma efekti testin konusu değil.
      theme: ThemeData.dark().copyWith(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ZirveRizaKarti(onKatil: onKatil, onSimdiDegil: onSimdiDegil),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('beş bilgi başlığı ve hukuki dayanak görünür', (tester) async {
    await pump(tester, onKatil: () async {});
    for (final b in [
      'Ne paylaşılır',
      'Ne paylaşılmaz',
      'Nasıl görünür',
      'Karşılığında',
      'Geri çekme',
    ]) {
      expect(find.text(b), findsOneWidget, reason: '$b eksik');
    }
    expect(find.textContaining('KVKK m.5/1'), findsOneWidget);
    // Karşılıklılık açıkça söylenir.
    expect(find.textContaining('yalnız katılanlara açıktır'), findsOneWidget);
    // Kimlik ve tutar paylaşılmaz.
    expect(find.textContaining('TL tutarların'), findsOneWidget);
  });

  testWidgets('Katılıyorum rızayı yazar, Şimdi değil yazmaz', (tester) async {
    var katildi = 0;
    var vazgecti = 0;
    await pump(tester,
        onKatil: () async => katildi++, onSimdiDegil: () => vazgecti++);
    await tester.tap(find.text('Şimdi değil'));
    await tester.pumpAndSettle();
    expect(katildi, 0);
    expect(vazgecti, 1);
    await tester.tap(find.text('Katılıyorum'));
    await tester.pumpAndSettle();
    expect(katildi, 1);
  });
}
