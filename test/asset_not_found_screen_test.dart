import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/asset_not_found_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/friendly_error.dart';

/// Dış bağlantı sahte / yetkisiz / silinmiş bir id ile gelirse hata ekranı
/// açılır; sessiz geçilmez.
void main() {
  testWidgets('hata ekranı: başlık, mesaj ve geri', (tester) async {
    // Gerçekte bir kök ekranın ÜSTÜNE push edilir; geri oku yalnızca
    // canPop iken çizilir, o yüzden test de push ile açar.
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
          brightness: Brightness.dark, extensions: const [SandikPalette.dark]),
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).push(
            adaptiveRoute<void>(builder: (_) => const AssetNotFoundScreen()),
          ),
          child: const Text('aç'),
        ),
      ),
    ));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Varlık bulunamadı'), findsOneWidget);
    expect(find.textContaining('portföyünde yok'), findsOneWidget);
    // Geri oku: kullanıcı kapatabilmeli.
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(AssetNotFoundScreen), findsNothing);
  });

  test('mesaj friendlyError süzgecinden olduğu gibi geçer', () {
    // Türkçe karakterli kısa mesaj → ham gösterilmez ama sabit metin korunur.
    final m = friendlyError(const VarlikBulunamadiHatasi());
    expect(m, contains('portföyünde yok'));
    expect(m, isNot(contains('Exception')));
    expect(m.length, lessThanOrEqualTo(120));
  });
}
