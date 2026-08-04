import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Alt navigasyon barının sistem inset'i regresyonu (Android 16 / edge-to-edge).
///
/// **Bağlam:** targetSdk 36'dan itibaren Android edge-to-edge'i zorunlu kılıyor;
/// `windowOptOutEdgeToEdgeEnforcement` artık yok sayılıyor. İçerik gesture
/// çubuğunun ALTINA uzuyor, uygulama inset'i kendisi bırakmak zorunda.
///
/// Bar sabit yükseklik kullansaydı son 48px (gesture bar) dokunulamaz olurdu.
/// `main_navigation_screen.dart:132` bunun yerine `MediaQuery.viewPaddingOf`
/// okuyup padding olarak uyguluyor. Bu testler o davranışı sabitler.
///
/// Buradaki ağaç `_buildBottomBar`'ın yapısal kopyasıdır — metot
/// `_MainNavigationScreenState`'e private ve Riverpod istiyor, doğrudan pump
/// edilemiyor. Kaynak değişirse burası da güncellenmeli.
/// (Bkz. TECHNICAL_DEBT.md — "_buildAssetTile test edilebilir değil".)

/// İçerik yüksekliği: her sekme 44pt HIG dokunma minimumunun üzerinde kalsın.
const double kBarContentHeight = 60;

/// Inset 0 olduğunda (gesture bar'sız cihaz) bırakılan taban boşluk.
const double kFallbackBottomPad = 12;

Widget buildBottomBar({required double bottomViewPadding}) {
  return MediaQuery(
    data: MediaQueryData(
      padding: EdgeInsets.only(bottom: bottomViewPadding),
      viewPadding: EdgeInsets.only(bottom: bottomViewPadding),
    ),
    child: Directionality(
      textDirection: TextDirection.ltr,
      // Gerçek uygulamada bar `Scaffold.bottomNavigationBar` slotunda duruyor
      // ve orada doğal yüksekliğine sıkıştırılıyor. Testte böyle bir ebeveyn
      // olmazsa ClipRect tüm viewport'u kaplar (600px) ve ölçüm anlamsızlaşır.
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Builder(
          builder: (context) {
            final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
            return ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: EdgeInsets.only(
                    bottom: bottomInset > 0 ? bottomInset : kFallbackBottomPad,
                  ),
                  child: const SizedBox(
                    height: kBarContentHeight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Icon(Icons.home_rounded),
                        Icon(Icons.donut_large_rounded),
                        Icon(Icons.add_circle),
                        Icon(Icons.show_chart_rounded),
                        Icon(Icons.person_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  group('alt navigasyon barı sistem inset\'i', () {
    // Pixel 7 gesture bar'ı 48px; bar bu kadar yukarı itilmezse son sekmeler
    // gesture alanının altında kalır ve dokunma sistem tarafından yutulur.
    testWidgets('gesture bar yüksekliği kadar padding bırakır', (tester) async {
      await tester.pumpWidget(buildBottomBar(bottomViewPadding: 48));

      final barSize = tester.getSize(find.byType(ClipRect));
      expect(barSize.height, kBarContentHeight + 48);
    });

    testWidgets('inset yokken sabit taban boşluğa düşer', (tester) async {
      await tester.pumpWidget(buildBottomBar(bottomViewPadding: 0));

      final barSize = tester.getSize(find.byType(ClipRect));
      expect(barSize.height, kBarContentHeight + kFallbackBottomPad);
    });

    // Asıl regresyon: ikonlar inset bölgesinin dışında kalmalı. Sabit yükseklik
    // kullanılsaydı bu beklenti düşerdi.
    testWidgets('ikonlar gesture bar bölgesinin dışında kalır', (tester) async {
      const inset = 48.0;
      await tester.pumpWidget(buildBottomBar(bottomViewPadding: inset));

      final barBottom = tester.getRect(find.byType(ClipRect)).bottom;
      final gestureZoneTop = barBottom - inset;

      for (final icon in find.byType(Icon).evaluate()) {
        final iconBottom = tester.getRect(find.byWidget(icon.widget)).bottom;
        expect(
          iconBottom,
          lessThanOrEqualTo(gestureZoneTop),
          reason: 'ikon gesture çubuğunun altında kalıyor — dokunma yutulur',
        );
      }
    });

    // iPhone X+ home indicator (34pt) ve tablet gibi farklı inset'lerde de
    // aynı kural geçerli: yükseklik inset ile birlikte büyümeli.
    testWidgets('farklı inset değerlerinde yükseklik ölçeklenir',
        (tester) async {
      for (final inset in <double>[20, 34, 48, 64]) {
        await tester.pumpWidget(buildBottomBar(bottomViewPadding: inset));
        final barSize = tester.getSize(find.byType(ClipRect));
        expect(
          barSize.height,
          kBarContentHeight + inset,
          reason: 'inset $inset için yükseklik yanlış',
        );
      }
    });

    testWidgets('dar ekranda beş sekme taşmaz', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildBottomBar(bottomViewPadding: 48));

      expect(tester.takeException(), isNull);
    });
  });
}
