import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/config/pref_keys.dart';
import 'package:portfoy_takip/models/portfoy_siralama.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sandik_siralama_dugmesi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Tek sıralama düğmesi + Portföy seçiminin kalıcılığı (Ar-Ge 2026-10-25
/// 12:45 #3, kabul 13:15 #2). Takip listesinin davranışı
/// `takip_sirasi_widget_test`'te; HIG ölçümü `hig_ortak_bilesen_test`.
void main() {
  group('iki ekran ortak bileşeni kullanır', () {
    for (final yol in [
      'lib/screens/portfolio_screen.dart',
      'lib/screens/watchlist_screen.dart',
    ]) {
      test(yol, () {
        final k = ekranKaynagiSync(yol);
        expect(k, contains('SandikSiralamaDugmesi<'),
            reason: 'sıralama düğmesi ortak bileşenden gelmeli');
        for (final eski in [
          'class _SortButton',
          'class _SortSheet',
          'class _SiralamaSayfasi',
        ]) {
          expect(k, isNot(contains(eski)),
              reason: '$eski kopyası geri gelmemeli');
        }
      });
    }
  });

  group('PortfoySiralama kodu', () {
    test('kodlar benzersiz ve kendine döner', () {
      final kodlar = {for (final s in PortfoySiralama.values) s.kod};
      expect(kodlar.length, PortfoySiralama.values.length);
      for (final s in PortfoySiralama.values) {
        expect(PortfoySiralama.kodla(s.kod), s);
      }
    });

    test('yok / tanınmayan / index kodu → bugünkü varsayılan "Değere göre"',
        () {
      expect(PortfoySiralama.varsayilan, PortfoySiralama.valueDesc);
      for (final k in [null, '', 'bilinmeyen', '2']) {
        expect(PortfoySiralama.kodla(k), PortfoySiralama.valueDesc);
      }
    });

    // Kodlar diske yazıldı; değişirse kullanıcının seçimi sessizce sıfırlanır.
    test('kodlar sabit', () {
      expect([for (final s in PortfoySiralama.values) s.kod], [
        'deger_azalan',
        'deger_artan',
        'kar_azalan',
        'kar_artan',
        'kar_yuzde_azalan',
        'kar_yuzde_artan',
        'bugun_hareket',
      ]);
    });
  });

  group('Portföy sıralaması kalıcı ve kişiye özel', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      setPreferencesUser(null);
    });
    tearDown(() => setPreferencesUser(null));

    void kullaniciDegisti(ProviderContainer c, String? uid) {
      setPreferencesUser(uid);
      for (final p in kullaniciyaOzelTercihler) {
        c.invalidate(p);
      }
    }

    test('listede (kullanıcı değişince yeniden okunur)', () {
      expect(kullaniciyaOzelTercihler, contains(portfoySiralamaProvider));
    });

    test('kayıt yoksa "Değere göre"', () async {
      await initPreferencesCache();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(portfoySiralamaProvider), PortfoySiralama.valueDesc.kod);
    });

    test('yeniden açılışta seçim aynı; diske kod yazılır', () async {
      await initPreferencesCache();
      final ilk = ProviderContainer();
      kullaniciDegisti(ilk, 'A');
      await ilk
          .read(portfoySiralamaProvider.notifier)
          .set(PortfoySiralama.gainPctDesc.kod);
      ilk.dispose();

      // Soğuk açılış: yeni kapsayıcı, önbellek diskten.
      await initPreferencesCache();
      final ikinci = ProviderContainer();
      addTearDown(ikinci.dispose);
      expect(PortfoySiralama.kodla(ikinci.read(portfoySiralamaProvider)),
          PortfoySiralama.gainPctDesc);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('${PrefKeys.portfoySiralama}_A'),
          'kar_yuzde_azalan');
    });

    test('hesap değişince ayrı: B, A\'nın seçimini görmez', () async {
      await initPreferencesCache();
      final c = ProviderContainer();
      addTearDown(c.dispose);

      kullaniciDegisti(c, 'A');
      await c
          .read(portfoySiralamaProvider.notifier)
          .set(PortfoySiralama.gainDesc.kod);

      kullaniciDegisti(c, 'B');
      expect(c.read(portfoySiralamaProvider), PortfoySiralama.valueDesc.kod);
      await c
          .read(portfoySiralamaProvider.notifier)
          .set(PortfoySiralama.valueAsc.kod);

      kullaniciDegisti(c, 'A');
      expect(c.read(portfoySiralamaProvider), PortfoySiralama.gainDesc.kod);
    });
  });

  group('SandikSiralamaDugmesi davranışı', () {
    const secenekler = [
      SandikSiralamaSecenegi(
          deger: 'a',
          baslik: 'Değere göre',
          altBaslik: 'Yüksekten düşüğe',
          ikon: Icons.arrow_downward_rounded),
      SandikSiralamaSecenegi(
          deger: 'b', baslik: 'Kâra göre', ikon: Icons.trending_up_rounded),
    ];

    Future<void> kur(WidgetTester t, Widget dugme) async {
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [SandikPalette.dark]),
        home: Scaffold(body: Center(child: dugme)),
      ));
    }

    testWidgets('etiketli: seçili başlık görünür; başka satır seçer, aynısı '
        'seçmez; sayfa her durumda kapanır', (t) async {
      final secilen = <String>[];
      await kur(
          t,
          SandikSiralamaDugmesi<String>.etiketli(
            secenekler: secenekler,
            secili: 'a',
            semantikEtiket: 'Sıralama: Değere göre',
            onSec: secilen.add,
          ));
      expect(find.text('Değere göre'), findsOneWidget);
      expect(find.bySemanticsLabel('Sıralama: Değere göre'), findsOneWidget);

      await t.tap(find.text('Değere göre'));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.text('Kâra göre'), findsOneWidget);
      // Seçili satıra dokun: değişiklik yok, sayfa kapanır.
      await t.tap(find.text('Yüksekten düşüğe'));
      await t.pumpAndSettle();
      expect(secilen, isEmpty);
      expect(find.byType(ListTile), findsNothing);

      await t.tap(find.text('Değere göre'));
      await t.pumpAndSettle();
      await t.tap(find.text('Kâra göre'));
      await t.pumpAndSettle();
      expect(secilen, ['b']);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('ikon: 44 pt, ekran okuyucu etiketi; seçili satır '
        '"seçili" bildirilir', (t) async {
      final handle = t.ensureSemantics();
      await kur(
          t,
          SandikSiralamaDugmesi<String>.ikon(
            secenekler: secenekler,
            secili: 'b',
            varsayilan: 'a',
            semantikEtiket: 'Varlıkları sırala',
            onSec: (_) {},
          ));
      final kutu = t.getSize(find.byWidgetPredicate(
          (w) => w is SandikSiralamaDugmesi));
      expect(kutu.width, greaterThanOrEqualTo(SandikTouch.min));
      expect(kutu.height, greaterThanOrEqualTo(SandikTouch.min));
      expect(find.bySemanticsLabel('Varlıkları sırala'), findsOneWidget);

      await t.tap(find.byIcon(Icons.sort_rounded));
      await t.pumpAndSettle();
      final secili = t.widget<ListTile>(find.ancestor(
          of: find.text('Kâra göre'), matching: find.byType(ListTile)));
      expect(secili.selected, isTrue);
      final diger = t.widget<ListTile>(find.ancestor(
          of: find.text('Değere göre'), matching: find.byType(ListTile)));
      expect(diger.selected, isFalse);
      handle.dispose();
    });
  });
}
