import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/ohlc.dart';
import 'package:portfoy_takip/widgets/grafik_arac_cubugu.dart';
import 'package:portfoy_takip/main.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/services/saydamlik_tercihi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/pozisyon_islemleri.dart';
import 'package:portfoy_takip/widgets/sandik_baglam_menusu.dart';
import 'package:portfoy_takip/widgets/sandik_cam.dart';

import 'helpers/kaynak.dart';

/// Cam başlık, yüzen kapsül ve bağlam menüsü (cam/HIG incelemesi,
/// 2026-10-12; bayrak `goz_alici`).
///
/// Kilitlenen sözleşme:
/// - bayrak kapalıyken eski düzen: cam yok, pay 0, menü yok;
/// - bayrak açıkken içerik başlığın ALTINDA başlar, kaydırınca altından
///   akar; bulanıklık yalnız iOS'ta ve yalnız içerik altına girince;
/// - Android, yüksek kontrast ve iOS "Saydamlığı azalt" hiç blur çizmez
///   (opak yol);
/// - "Hareketi azalt" açıkken başlık küçülmez;
/// - bağlam menüsü kısayoldur: satıra dokunmak hâlâ satırı açar.
/// Platform taklidi test GÖVDESİ içinde geri alınmalı (çerçeve gövde
/// bitince denetler; `tearDown` geç kalır).
void _tw(String ad, Future<void> Function(WidgetTester) govde) =>
    testWidgets(ad, (t) async {
      try {
        await govde(t);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

void main() {
  tearDown(() => RemoteConfigService.testAcik = {});

  // İskeleti kuran ekranın `State.context`'i iskeletin ÜSTÜNDE: oradan
  // okunan pay hep 0 çıkar ve ilk satır cam başlığın altında kalır
  // (Performans'ta Filtre çipi dokunulmaz oldu, tam paket yakaladı). Pay
  // yalnız `payIle` ile ya da gövdenin kendi widget'ından okunur.
  test('iskeleti kuran ekran payı kendi context\'inden okumaz', () {
    for (final yol in [
      'lib/screens/portfolio_screen.dart',
      'lib/screens/portfolio_performance_screen.dart',
      'lib/screens/profile_screen.dart',
    ]) {
      final k = ekranKaynagiSync(yol);
      expect(k, contains('SandikKaydirmaBasligi('), reason: yol);
      expect(k, isNot(contains('SandikKaydirmaBasligi.ustPay(context)')),
          reason: '$yol: payIle kullan');
    }
  });

  Widget sekme({bool azalt = false, bool kontrast = false}) => MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            padding: const EdgeInsets.only(top: 47),
            viewPadding: const EdgeInsets.only(top: 47),
            disableAnimations: azalt,
            highContrast: kontrast,
          ),
          child: Scaffold(
            body: SandikKaydirmaBasligi(
              kimlik: 'test-${azalt}_$kontrast',
              baslik: const SizedBox(
                height: 52,
                child: SandikKucululenBaslik(
                  child: Text('Portföy', key: ValueKey('baslik')),
                ),
              ),
              // Ekranlardaki gibi `payIle`: pay gövdenin içinden okunur.
              govde: SandikKaydirmaBasligi.payIle(
                (ustPay) => ListView(
                  padding: EdgeInsets.only(top: ustPay),
                  children: [
                    for (var i = 0; i < 40; i++)
                      SizedBox(
                        height: 60,
                        child: Text('satır $i', key: ValueKey('s$i')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  _tw('bayrak kapalı: eski SafeArea > Column, cam ve pay yok',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await t.pumpWidget(sekme());
    await t.pump();
    expect(find.byType(BackdropFilter), findsNothing);
    // İlk satır başlığın hemen altında (Column), üstünde değil.
    expect(t.getTopLeft(find.byKey(const ValueKey('s0'))).dy,
        closeTo(47 + 52, 0.5));
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pump();
    expect(find.byType(BackdropFilter), findsNothing);
  });

  _tw('iOS: içerik başlığın altında başlar, kaydırınca cam gelir',
      (t) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await t.pumpWidget(sekme());
    await t.pump();
    await t.pump();
    // Başlık durum çubuğunu da kaplar; ilk satır ikisinin altında.
    expect(t.getTopLeft(find.byKey(const ValueKey('s0'))).dy,
        closeTo(47 + 52, 0.5));
    // Hareketsizken blur yok (arkada içerik yok, boşuna ödenmez).
    expect(find.byType(BackdropFilter), findsNothing);

    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pump();
    expect(find.byType(BackdropFilter), findsOneWidget);
    // Başlık küçüldü (parmağı izler; zamana bağlı animasyon yok).
    final olcek = t
        .widget<Transform>(find.descendant(
            of: find.byType(SandikKucululenBaslik),
            matching: find.byType(Transform)))
        .transform
        .storage[0];
    expect(olcek, lessThan(1));

    // Başa dönünce cam kalkar.
    await t.drag(find.byType(ListView), const Offset(0, 600));
    await t.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
  });

  _tw('Android ve yüksek kontrast: blur hiç çizilmez', (t) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await t.pumpWidget(sekme());
    await t.pump();
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pump();
    expect(find.byType(BackdropFilter), findsNothing);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await t.pumpWidget(sekme(kontrast: true));
    await t.pump();
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pump();
    expect(find.byType(BackdropFilter), findsNothing);
  });

  // Ayar Flutter'a gelmiyor, kanaldan okunur; uygulama açıkken değişince
  // yüzey yeniden başlatmadan opaklaşmalı (HIG; mağazaya gitmeden kapandı).
  _tw('iOS Saydamlığı azalt: cam çizilmez, değişince hemen uyar',
      (t) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final azalt = SaydamlikTercihi.instance.azalt;
    try {
      await t.pumpWidget(sekme());
      await t.pump();
      await t.drag(find.byType(ListView), const Offset(0, -300));
      await t.pump();
      expect(find.byType(BackdropFilter), findsOneWidget);

      azalt.value = true;
      await t.pump();
      expect(find.byType(BackdropFilter), findsNothing);

      azalt.value = false;
      await t.pump();
      expect(find.byType(BackdropFilter), findsOneWidget);
    } finally {
      azalt.value = false;
    }
  });

  _tw('Hareketi azalt: başlık küçülmez', (t) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await t.pumpWidget(sekme(azalt: true));
    await t.pump();
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pump();
    expect(
        find.descendant(
            of: find.byType(SandikKucululenBaslik),
            matching: find.byType(Transform)),
        findsNothing);
  });

  Widget kapsul({required bool yuzen}) => MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        home: Scaffold(
          extendBody: yuzen,
          body: const SizedBox.expand(),
          bottomNavigationBar: PozisyonIslemCubugu(
            yuzen: yuzen,
            islemler: PozisyonIslemi.values,
            onIslem: (_) {},
          ),
        ),
      );

  _tw('yüzen kapsül: iOS camı, düğmeler 44 pt üstü', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await t.pumpWidget(kapsul(yuzen: true));
    expect(find.byType(BackdropFilter), findsOneWidget);
    for (final i in PozisyonIslemi.values) {
      final boy = t.getSize(find.byKey(ValueKey('pozisyon-islemi-${i.name}')));
      expect(boy.height, greaterThanOrEqualTo(SandikTouch.min));
    }
    // Eski şerit: cam yok.
    await t.pumpWidget(kapsul(yuzen: false));
    expect(find.byType(BackdropFilter), findsNothing);
  });

  Widget menulu({required VoidCallback onTap, required VoidCallback onAl}) =>
      MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        home: Scaffold(
          body: Center(
            child: SandikBaglamMenusu(
              baslik: 'THYAO',
              eylemler: [
                SandikBaglamEylemi(
                    etiket: 'Al', ikon: Icons.add_rounded, onSec: onAl),
                SandikBaglamEylemi(
                    etiket: 'Sil',
                    ikon: Icons.delete_outline_rounded,
                    yikici: true,
                    onSec: () {}),
              ],
              child: SandikTappable(
                onTap: onTap,
                semanticLabel: 'satır',
                child: const SizedBox(
                    width: 300, height: 60, child: Text('THYAO satırı')),
              ),
            ),
          ),
        ),
      );

  _tw('bağlam menüsü: bayrak kapalıyken yok', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await t.pumpWidget(menulu(onTap: () {}, onAl: () {}));
    expect(find.byType(CupertinoContextMenu), findsNothing);
  });

  _tw('bağlam menüsü iOS: sistem menüsü, dokunuş satırı açar',
      (t) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var acildi = 0;
    var alindi = 0;
    await t.pumpWidget(menulu(onTap: () => acildi++, onAl: () => alindi++));
    expect(find.byType(CupertinoContextMenu), findsOneWidget);

    await t.tap(find.text('THYAO satırı'));
    await t.pumpAndSettle();
    expect(acildi, 1, reason: 'kısayol satırın dokunuşunu yutmamalı');

    // Sistem menüsü basılı tutma animasyonu bitince açılır.
    final basis = await t.startGesture(t.getCenter(find.text('THYAO satırı')));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await basis.up();
    await t.pumpAndSettle();
    expect(find.byType(CupertinoContextMenuAction), findsNWidgets(2));
    await t.tap(find.widgetWithText(CupertinoContextMenuAction, 'Al'));
    await t.pumpAndSettle();
    expect(alindi, 1);
    expect(find.byType(CupertinoContextMenuAction), findsNothing);
  });

  // Önizleme kök katmanda: (1) satırın sağlayıcı kabı orada yok, (2) ona
  // satırın genişliği verilmiyor. Gerçek kart (Expanded'lı satır + sağlayıcı
  // okuyan rozet) ikisinde de çöküyordu; demo ekran görüntüsü yakaladı.
  _tw('bağlam menüsü iOS: önizleme sağlayıcıyı okur ve taşmaz', (t) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final ad = Provider<String>((_) => 'kaptan');
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ProviderScope(
            overrides: [ad.overrideWithValue('iç kap')],
            child: SizedBox(
              width: 360,
              height: 68,
              child: SandikBaglamMenusu(
                baslik: 'KCHOL',
                eylemler: [
                  SandikBaglamEylemi(
                      etiket: 'Al', ikon: Icons.add_rounded, onSec: () {}),
                ],
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Expanded(child: Text('KCHOL')),
                          Consumer(builder: (_, ref, __) => Text(ref.watch(ad))),
                        ]),
                        const Spacer(),
                        const Text('620 lot'),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ));
    final basis = await t.startGesture(t.getCenter(find.text('KCHOL')));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await basis.up();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byType(CupertinoContextMenuAction), findsOneWidget);
    // Önizleme satırın kendi (iç) kabını okur, kökü değil.
    expect(find.text('iç kap'), findsWidgets);
    expect(find.text('kaptan'), findsNothing);
  });

  _tw('bağlam menüsü Android: uzun basınca alt sayfa, yıkıcı sonda',
      (t) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var alindi = 0;
    await t.pumpWidget(menulu(onTap: () {}, onAl: () => alindi++));
    await t.longPress(find.text('THYAO satırı'));
    await t.pumpAndSettle();
    final al = t.getTopLeft(find.widgetWithText(ListTile, 'Al')).dy;
    final sil = t.getTopLeft(find.widgetWithText(ListTile, 'Sil')).dy;
    expect(sil, greaterThan(al));
    await t.tap(find.widgetWithText(ListTile, 'Al'));
    await t.pumpAndSettle();
    expect(alindi, 1);
  });

  _tw('bağlam menüsü ekran okuyucu eylemleri taşır', (t) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final handle = t.ensureSemantics();
    await t.pumpWidget(menulu(onTap: () {}, onAl: () {}));
    final dugum = t.getSemantics(find.byType(SandikBaglamMenusu));
    expect(dugum.getSemanticsData().customSemanticsActionIds, hasLength(2));
    handle.dispose();
  });

  Widget araclar() => ProviderScope(
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              width: 390,
              child: GrafikAracCubugu(
                katmanlar: true,
                ma20Acik: false,
                logAcik: false,
                mumAcik: true,
                aralik: MumAraligi.saat1,
                gecerliAraliklar: const [MumAraligi.dk5, MumAraligi.saat1],
                pencereDakika: 60 * 24 * 30,
              ),
            ),
          ),
        ),
      );

  _tw('grafik araçları: bayrakla tek sıra, sırası aynı', (t) async {
    await t.pumpWidget(araclar());
    final ikiSira = t.getTopLeft(find.text('EMA50')).dy !=
        t.getTopLeft(find.text('LOG')).dy;
    expect(ikiSira, isTrue, reason: 'bayrak kapalı: eski iki satır');

    RemoteConfigService.testAcik = {'goz_alici'};
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpWidget(araclar());
    final y = t.getTopLeft(find.text('LOG')).dy;
    for (final c in ['MA20', 'EMA50', 'EMA200']) {
      expect(t.getTopLeft(find.text(c)).dy, y, reason: c);
    }
    // Sıra korunur: görünüm çipleri, sonra ortalamalar.
    expect(t.getTopLeft(find.text('LOG')).dx,
        lessThan(t.getTopLeft(find.text('MA20')).dx));
    expect(t.takeException(), isNull);
  });
}
