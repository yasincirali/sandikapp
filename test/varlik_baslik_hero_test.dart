import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/varlik_baslik_hero.dart';

import 'helpers/kaynak.dart';

/// Yol haritası 2.14 — Portföy satırından varlık ekranına başlık uçuşu.
///
/// Bayrak `varlik_hero_gecisi` KAPALI doğar; kapalıyken hiçbir `Hero`
/// kurulmaz (geçiş birebir eski). Açıkken uçuş iki yönde de istisnasız
/// tamamlanmalı ve metin kırılmadan ölçeklenmeli.
void main() {
  test('bayrak varsayılanı KAPALI', () {
    expect(RemoteConfigService.instance.varlikHeroGecisi, isFalse);
  });

  testWidgets('etiket null → Hero kurulmaz', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: VarlikBaslikHero(etiket: null, child: Text('THYAO')),
    ));
    expect(find.byType(Hero), findsNothing);
  });

  testWidgets('hareketi azalt → Hero kurulmaz', (t) async {
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: VarlikBaslikHero(
            etiket: varlikHeroEtiketi('k'), child: const Text('THYAO')),
      ),
    ));
    expect(find.byType(Hero), findsNothing);
  });

  testWidgets('uçuş push ve pop yönünde istisnasız tamamlanır', (t) async {
    final nav = GlobalKey<NavigatorState>();
    final etiket = varlikHeroEtiketi('poz-1');
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: VarlikBaslikHero(
            etiket: etiket,
            child: const Text('THYAO', style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
    ));

    nav.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: Center(
          child: VarlikBaslikHero(
            etiket: etiket,
            // Uçlarda farklı metin: döviz satırı adı, ekran kodu yazabilir.
            child: const Text('Türk Hava Yolları',
                style: TextStyle(fontSize: 28)),
          ),
        ),
      ),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    // Uçuşta iki uç da ölçeklenmiş hâlde, üst üste.
    expect(find.byType(FittedBox), findsNWidgets(2));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);

    nav.currentState!.pop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    expect(find.byType(FittedBox), findsNWidgets(2));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('THYAO'), findsOneWidget);
  });

  test('etiket satırdan ekrana açıkça taşınır', () {
    final portfoy = ekranKaynagiSync('lib/screens/portfolio_screen.dart');
    expect(portfoy.contains('varlikHeroEtiketi(position.key)'), isTrue,
        reason: 'Etiket gösterilen satırın anahtarından kurulmalı (tekil).');
    expect(portfoy.contains('heroEtiketi: hero,'), isTrue);
    final ozet = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    expect(ozet.contains('heroEtiketi: widget.heroEtiketi'), isTrue,
        reason: 'Ekran başlığı satırın etiketini kullanmalı.');
  });
}
