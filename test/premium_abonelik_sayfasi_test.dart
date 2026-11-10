import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/premium_abonelik_satiri.dart';

import 'helpers/kaynak.dart';

/// Profil › Premium satırının açtığı alt sayfa (yasin 10 Kas ekran
/// görüntüsü): kart içeriği kadar olmalı, sayfanın 9/16 sınırına kadar
/// uzayıp altında boş kutu bırakmamalı.
void main() {
  testWidgets('Premium alt sayfasındaki kart içeriği kadar uzun', (t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showSandikSheet<void>(
                  context: ctx,
                  baslik: 'Sandık Premium',
                  builder: (_) => const PremiumAbonelikSatiri(hak: null),
                ),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('aç'));
    await t.pumpAndSettle();
    final kart = t.getSize(find.byType(SandikCard));
    // İçerik: başlık satırı + 44 pt düğme satırı + bir satır ipucu.
    expect(kart.height, lessThan(260),
        reason: 'kart sayfa boyunca uzamamalı (boş kutu)');
  });

  test('Raporlar düğmesi aylık rapor dönemini önceden dinler', () {
    // Sayfa açıldıktan sonra gelen satır sayfayı basamak basamak uzatıyordu.
    final src = ekranKaynagiSync('lib/widgets/raporlar_kapisi.dart');
    final dugme = src.substring(src.indexOf('class RaporlarDugmesi'),
        src.indexOf('Future<void> raporlarSayfasiniAc'));
    expect(dugme.contains('ref.watch(aylikRaporDonemiProvider)'), isTrue);
    expect(src.contains('AnimatedSize('), isTrue);
  });
}
