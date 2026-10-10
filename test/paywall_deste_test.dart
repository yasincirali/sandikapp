import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/screens/paywall_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/kart_destesi.dart';

import 'helpers/kaynak.dart';

/// Kart desteli paywall (bayrak `paywall_deste`, yasin 2026-10-08).
///
/// Üç katman: (1) hangi kilitten açıldıysa deste o kartla başlar ve açık
/// olmayan özelliğin kartı çıkmaz; (2) destenin geometrisi prototiple aynı
/// (dolanma kareleri, katman değişim anı, geçme eşiği); (3) bayrak kapalıyken
/// eski paywall birebir, açıkken yeni gövde.
void main() {
  group('desteSirasi — kaynağın kartı başta', () {
    test('kaynaklar doğru karta eşlenir', () {
      const beklenen = {
        'asset_limit_7': PaywallKarti.varlik,
        'asset_limit_dialog': PaywallKarti.varlik,
        'bulk_add_asset_limit': PaywallKarti.varlik,
        'watchlist_limit': PaywallKarti.varlik,
        'signal_frequency': PaywallKarti.sinyal,
        'signal_settings_card': PaywallKarti.sinyal,
        'signal_on_ayar': PaywallKarti.sinyal,
        'signal_settings_42': PaywallKarti.sinyal,
        'sinyal_varlik': PaywallKarti.sinyal,
        'compare_series': PaywallKarti.karsilastir,
        'partner_limit': PaywallKarti.ortak,
        'para_akisi_karti': PaywallKarti.akis,
        'hacim_radari': PaywallKarti.hacim,
        'kripto_baski': PaywallKarti.hacim,
        'analiz_notu': PaywallKarti.not,
        'ekstre_ai': PaywallKarti.ekstre,
        'sinyal_kilit': PaywallKarti.sinyal,
        'yillik_rapor': PaywallKarti.rapor,
        'portfoy_disa_aktar': PaywallKarti.rapor,
        'masraf_dokumu': PaywallKarti.rapor,
        'temettu_tahmini': PaywallKarti.temettu,
        'aylik_rapor': PaywallKarti.not,
        // Fon X-Ray (2026-10-10): varlık kartı ve portföy ekranı.
        'fon_xray': PaywallKarti.xray,
        'portfoy_xray': PaywallKarti.xray,
        'portfoy_limit': PaywallKarti.portfoy,
        // #148/#150 kilitleri (2026-10-10): kısmi aktarım ve ortağın
        // göreceği portföy → portföy kartı; mum/EMA → grafik kartı.
        'portfoy_kismi_aktar': PaywallKarti.portfoy,
        'ortak_paylasim': PaywallKarti.portfoy,
        'grafik_mum': PaywallKarti.grafik,
        'grafik_ema': PaywallKarti.grafik,
        'coklu_hesap': PaywallKarti.hesap,
      };
      beklenen.forEach((kaynak, kart) {
        expect(kaynaktanKart(kaynak), kart, reason: kaynak);
      });
      expect(kaynaktanKart('profile_banner'), isNull);
    });

    test('koddaki her paywall kaynağı bir karta düşer ya da bilinçli null', () {
      // Yeni bir kilit eklenip burada eşlenmezse deste varlık kartıyla
      // açılır: kullanıcı neden paywall'da olduğunu göremez.
      const bilerekGenel = {'profile_banner'};
      final kaynaklar = <String>{};
      for (final yol in [
        'lib/screens/add_asset_screen.dart',
        'lib/screens/bulk_add_asset_screen.dart',
        'lib/screens/comparison_screen.dart',
        'lib/screens/signal_settings_screen.dart',
        'lib/screens/profile_screen.dart',
        'lib/screens/paywall_screen.dart',
        'lib/screens/csv_import_screen.dart',
        'lib/screens/analiz_notu_screen.dart',
        'lib/widgets/para_akisi_karti.dart',
        'lib/widgets/hacim_radari_karti.dart',
        'lib/screens/asset_detail/sinyal_widgetlari.dart',
        // Olgun Premium seti (2026-10-10).
        'lib/widgets/sinyal_kilit_karti.dart',
        'lib/widgets/masraf_karti.dart',
        'lib/screens/yillik_rapor_screen.dart',
        'lib/screens/temettu_tahmini_screen.dart',
        'lib/screens/aylik_rapor_screen.dart',
        'lib/screens/settings_screen.dart',
        // Fon X-Ray (2026-10-10).
        'lib/widgets/fon_dagilimi_karti.dart',
        'lib/screens/portfoy_xray_screen.dart',
        // Çoklu portföy (2026-10-10).
        'lib/widgets/portfoy_secici.dart',
        'lib/widgets/portfoy_secim_sayfasi.dart',
        'lib/screens/portfoy_yonetimi_screen.dart',
        'lib/widgets/kismi_aktarim_sayfasi.dart',
        'lib/widgets/ortak_paylasim_sayfasi.dart',
        'lib/widgets/hesap_secici.dart',
        // Grafik katmanları (#150): kaynak `dokun(..., 'grafik_mum')`
        // konumsal argümanla geçer; ikinci desen onu yakalar.
        'lib/screens/asset_detail/grafik_katmanlari.dart',
      ]) {
        final src = ekranKaynagiSync(yol);
        for (final m
            in RegExp(r"(?:source|kaynak): '([a-z_]+)").allMatches(src)) {
          kaynaklar.add(m.group(1)!);
        }
        for (final m in RegExp(r"'(grafik_[a-z]+)'").allMatches(src)) {
          kaynaklar.add(m.group(1)!);
        }
      }
      expect(kaynaklar, containsAll(['grafik_mum', 'grafik_ema']));
      kaynaklar.remove('invite'); // mağaza bağlantısı kaynağı, paywall değil
      for (final k in kaynaklar) {
        if (bilerekGenel.contains(k)) continue;
        expect(kaynaktanKart(k), isNotNull, reason: 'eşlenmemiş kaynak: $k');
      }
    });

    test('varsayılan sıra, radar, ekstre, portföy ve hesap açıkken tüm kartlar',
        () {
      expect(
          desteSirasi('profile_banner',
              radar: true, ekstreAi: true, portfoy: true, hesap: true),
          PaywallKarti.values);
    });

    test('hesap kartı yalnız coklu_hesap açıkken', () {
      expect(desteSirasi('coklu_hesap', radar: true, ekstreAi: true),
          isNot(contains(PaywallKarti.hesap)));
      expect(
          desteSirasi('coklu_hesap', radar: false, ekstreAi: false, hesap: true)
              .first,
          PaywallKarti.hesap);
    });

    test('portföy kartı yalnız coklu_portfoy açıkken (varsayılan yok)', () {
      expect(desteSirasi('profile_banner', radar: true, ekstreAi: true),
          isNot(contains(PaywallKarti.portfoy)));
      expect(desteSirasi('portfoy_limit', radar: false, ekstreAi: false).first,
          PaywallKarti.varlik,
          reason: 'bayrak kapalıyken kaynak varsayılan sıraya düşer');
      expect(
          desteSirasi('portfoy_limit',
                  radar: false, ekstreAi: false, portfoy: true)
              .first,
          PaywallKarti.portfoy);
    });

    test('kaynağın kartı başa alınır, gerisi sırasını korur', () {
      expect(
        desteSirasi('compare_series', radar: false, ekstreAi: false),
        [
          PaywallKarti.karsilastir,
          PaywallKarti.varlik,
          PaywallKarti.rapor,
          PaywallKarti.temettu,
          PaywallKarti.xray,
          PaywallKarti.sinyal,
          PaywallKarti.grafik,
          PaywallKarti.ortak,
        ],
      );
    });

    test('açık olmayan özelliğin kartı çıkmaz', () {
      final s = desteSirasi('profile_banner', radar: false, ekstreAi: false);
      expect(s, isNot(contains(PaywallKarti.akis)));
      expect(s, isNot(contains(PaywallKarti.hacim)));
      expect(s, isNot(contains(PaywallKarti.not)));
      expect(s, isNot(contains(PaywallKarti.ekstre)));
      // Radar kapalıyken radar kaynağı varsayılan sıraya düşer.
      expect(desteSirasi('hacim_radari', radar: false, ekstreAi: false).first,
          PaywallKarti.varlik);
    });
  });

  group('deste geometrisi', () {
    test('kademeler: ön, iki görünen arka, dipte görünmez', () {
      expect(desteKonumu(0).y, 0);
      expect(desteKonumu(0).olcek, 1);
      expect(desteKonumu(1).y, 13);
      expect(desteKonumu(2).olcek, closeTo(0.91, 1e-9));
      expect(desteKonumu(2).opaklik, 1);
      expect(desteKonumu(2.5).opaklik, closeTo(0.5, 1e-9));
      expect(desteKonumu(3).opaklik, 0);
      expect(desteKonumu(7).y, desteKonumu(3).y);
    });

    test('dolanma: sürüklemenin bıraktığı yerden başlar, dipte biter', () {
      const bas = DestePozu(x: -120, y: -3.6);
      final ilk =
          alttaGidenPoz(0, genislik: 350, taraf: -1, kartSayisi: 5, bas: bas);
      expect(ilk.x, -120);
      final tepe = alttaGidenPoz(0.42,
          genislik: 350, taraf: -1, kartSayisi: 5, bas: bas);
      expect(tepe.x, closeTo(-350 * 0.66, 1e-6));
      final son =
          alttaGidenPoz(1, genislik: 350, taraf: -1, kartSayisi: 5, bas: bas);
      expect(son.y, desteKonumu(4).y);
      expect(son.opaklik, 0);
    });

    test('katman değişimi destenin yanındayken olur', () {
      expect(alttaGidenUstte(0.40), isTrue);
      expect(alttaGidenUstte(0.43), isFalse);
      expect(ustteGelenUstte(0.57), isFalse);
      expect(ustteGelenUstte(0.58), isTrue);
    });

    test('geri: dipten gelen kart öne oturur', () {
      final son = ustteGelenPoz(1, genislik: 350, kartSayisi: 5);
      expect(son.x, 0);
      expect(son.y, 0);
      expect(son.olcek, 1);
      expect(son.opaklik, 1);
      expect(ustteGelenPoz(0, genislik: 350, kartSayisi: 5).opaklik, 0);
    });

    test('geçme eşiği: uzun çekiş ya da hızlı fiske', () {
      expect(suruklemeGecer(100, 0, 350), isTrue); // > %26
      expect(suruklemeGecer(80, 0, 350), isFalse);
      expect(suruklemeGecer(30, 800, 350), isTrue); // fiske
      expect(suruklemeGecer(10, 2000, 350), isFalse); // dokunuş titremesi
    });
  });

  group('KartDestesi widget', () {
    Widget deste(GlobalKey<KartDestesiState> key, {bool hareketAz = false}) =>
        MaterialApp(
          theme: ThemeData(extensions: const [SandikPalette.dark]),
          home: MediaQuery(
            data: MediaQueryData(
                size: const Size(400, 800), disableAnimations: hareketAz),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(SandikSpace.lgs),
                child: KartDestesi(
                  key: key,
                  oncekiEtiketi: 'önceki',
                  sonrakiEtiketi: 'sonraki',
                  ipucu: 'kaydır',
                  kartlar: [
                    for (final ad in ['A', 'B', 'C', 'D'])
                      DesteKarti(
                          zemin: SandikPalette.dark.surface2,
                          semantik: ad,
                          child: Text('kart $ad')),
                  ],
                ),
              ),
            ),
          ),
        );

    testWidgets('sonraki oku ve iki yöne kaydırma ileri sayar', (t) async {
      final key = GlobalKey<KartDestesiState>();
      await t.pumpWidget(deste(key));
      expect(key.currentState!.onIndeks, 0);

      await t.tap(find.byTooltip('sonraki'));
      await t.pumpAndSettle();
      expect(key.currentState!.onIndeks, 1);

      // Sola uzun çekiş.
      await t.drag(find.text('kart B'), const Offset(-200, 0));
      await t.pumpAndSettle();
      expect(key.currentState!.onIndeks, 2);

      // Sağa uzun çekiş de ileri sayar (deste sonsuz).
      await t.drag(find.text('kart C'), const Offset(200, 0));
      await t.pumpAndSettle();
      expect(key.currentState!.onIndeks, 3);

      // Sonsuz: sondan başa döner.
      await t.tap(find.byTooltip('sonraki'));
      await t.pumpAndSettle();
      expect(key.currentState!.onIndeks, 0);
    });

    testWidgets('kısa çekiş geri yaylanır, geri oku dipteki kartı getirir',
        (t) async {
      final key = GlobalKey<KartDestesiState>();
      await t.pumpWidget(deste(key));
      await t.timedDrag(find.text('kart A'), const Offset(-40, 0),
          const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(key.currentState!.onIndeks, 0);

      await t.tap(find.byTooltip('önceki'));
      await t.pumpAndSettle();
      expect(key.currentState!.onIndeks, 3);
    });

    testWidgets('dokunuş süren geçişi bitirir, ikinci dokunuş yutulmaz',
        (t) async {
      final key = GlobalKey<KartDestesiState>();
      await t.pumpWidget(deste(key));
      await t.tap(find.byTooltip('sonraki'));
      await t.pump(SandikMotion.state);
      await t.tap(find.byTooltip('sonraki'));
      await t.pumpAndSettle();
      expect(key.currentState!.onIndeks, 2);
    });

    testWidgets('hareketi azalt: geçiş animasyonsuz', (t) async {
      final key = GlobalKey<KartDestesiState>();
      await t.pumpWidget(deste(key, hareketAz: true));
      await t.tap(find.byTooltip('sonraki'));
      await t.pump();
      expect(key.currentState!.onIndeks, 1);
      // Tek karede yerinde: sonraki karelerde kart kımıldamaz.
      final ilk = t.getTopLeft(find.text('kart B'));
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.text('kart B')), ilk);
    });

    testWidgets('ekran okuyucu yalnız öndeki kartı duyar', (t) async {
      final key = GlobalKey<KartDestesiState>();
      final h = t.ensureSemantics();
      await t.pumpWidget(deste(key));
      expect(find.bySemanticsLabel(RegExp(r'^A, 1 / 4$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('kart B')), findsNothing);
      h.dispose();
    });
  });

  group('PaywallScreen bayrağı', () {
    tearDown(() => RemoteConfigService.testAcik = {});

    Widget ekran(String kaynak) => ProviderScope(
          child: MaterialApp(
            theme: ThemeData(extensions: const [SandikPalette.dark]),
            locale: const Locale('tr'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: PaywallScreen(source: kaynak),
          ),
        );

    testWidgets('kapalıyken eski paywall: deste yok', (t) async {
      await t.pumpWidget(ekran('compare_series'));
      await t.pumpAndSettle();
      expect(find.byType(KartDestesi), findsNothing);
      expect(find.text('Satın alımı geri yükle'), findsOneWidget);
    });

    testWidgets('açıkken deste kaynağın kartıyla açılır, fiyat en büyük',
        (t) async {
      RemoteConfigService.testAcik = {'paywall_deste'};
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ekran('compare_series'));
      await t.pumpAndSettle();

      final deste = t.state<KartDestesiState>(find.byType(KartDestesi));
      expect(deste.onIndeks, 0);
      expect(find.text('KARŞILAŞTIR'), findsOneWidget);

      // Mağaza yanıt vermedi: RC fiyatı, deneme vaadi yok.
      expect(find.text('649,99₺/yıl'), findsOneWidget);
      expect(find.text('Bugün'), findsNothing);
      expect(find.text('Yıllık abone ol'), findsOneWidget);
      // Geri yükle başlıkta bir kez.
      expect(find.text('Satın alımı geri yükle'), findsOneWidget);

      final fiyat = t.widget<Text>(find.text('649,99₺/yıl')).style!.fontSize!;
      final slogan =
          t.widget<Text>(find.text('Sandığının içini aç.')).style!.fontSize!;
      expect(fiyat, greaterThan(slogan));

      await t.tap(find.text('Aylık'));
      await t.pumpAndSettle();
      expect(find.text('79,99₺/ay'), findsOneWidget);
      expect(find.text('Aylık abone ol'), findsOneWidget);
    });
  });
}
