import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_kullanim_provider.dart';
import 'package:portfoy_takip/screens/paywall_screen.dart';

import 'helpers/kaynak.dart';

/// Ar-Ge 23 Kas 0203: Profil'in Premium satırı, Premium sayfası ve tek
/// satırların ritmi (madde 1-5).
void main() {
  group('#1 sınır sayacı seçimi (saf)', () {
    SinirSayaci k(SinirKalemi kalem, int sayi, int sinir) =>
        (kalem: kalem, sayi: sayi, sinir: sinir);

    test('7/10 eşiğin altında: ek yok', () {
      expect(enYakinSinir([k(SinirKalemi.varlik, 7, 10)]), isNull);
    });

    test('8/10 tam eşik, 9/10 ek var', () {
      expect(enYakinSinir([k(SinirKalemi.varlik, 8, 10)])?.sayi, 8);
      final s = enYakinSinir([k(SinirKalemi.varlik, 9, 10)])!;
      expect((s.kalem, s.sayi, s.sinir), (SinirKalemi.varlik, 9, 10));
    });

    test('birden çok kalemde oranı en yüksek olan', () {
      final s = enYakinSinir([
        k(SinirKalemi.varlik, 8, 10), // %80
        k(SinirKalemi.takip, 5, 5), // %100
        k(SinirKalemi.alarm, 17, 20), // %85
      ])!;
      expect(s.kalem, SinirKalemi.takip);
      // Eşitlikte sıra kazanır (varlık önde).
      expect(
          enYakinSinir([k(SinirKalemi.varlik, 4, 5), k(SinirKalemi.alarm, 16, 20)])!
              .kalem,
          SinirKalemi.varlik);
      // Eşik altındaki kalem seçilmez.
      expect(
          enYakinSinir([k(SinirKalemi.varlik, 3, 10), k(SinirKalemi.alarm, 16, 20)])!
              .kalem,
          SinirKalemi.alarm);
    });

    test('sınırı aşan sayı da yazılır, sınırı 0 kalem düşünülmez', () {
      expect(enYakinSinir([k(SinirKalemi.varlik, 12, 10)])?.sayi, 12);
      expect(enYakinSinir([k(SinirKalemi.takip, 3, 0)]), isNull);
    });
  });

  group('#1 sağlayıcı kapıları', () {
    ProviderContainer kap(List<Override> o) {
      final c = ProviderContainer(overrides: o);
      addTearDown(c.dispose);
      return c;
    }

    test('Premium\'da sayaç yok', () {
      final c = kap([
        paywallVisibleProvider.overrideWithValue(true),
        effectivePremiumProvider.overrideWithValue(true),
      ]);
      expect(c.read(premiumSinirSayaciProvider), isNull);
    });

    test('paywall kapalıyken ya da kilit askıdayken sayaç yok', () {
      expect(
          kap([paywallVisibleProvider.overrideWithValue(false)])
              .read(premiumSinirSayaciProvider),
          isNull);
      expect(
          kap([
            paywallVisibleProvider.overrideWithValue(true),
            effectivePremiumProvider.overrideWithValue(false),
            premiumKilitliProvider.overrideWithValue(false),
          ]).read(premiumSinirSayaciProvider),
          isNull);
    });
  });

  group('#1-2 Profil satırı', () {
    final ekran = ekranKaynagiSync('lib/screens/profile_screen.dart');

    test('sayaç sağlayıcıdan, metin ve kaynak', () {
      expect(ekran, contains('ref.watch(premiumSinirSayaciProvider)'));
      expect(ekran, contains("'profile_banner_sinir'"));
      expect(ekran, contains('l10n.premiumDurumGecSayac(durum, sayacMetni)'));
      // Etiket metnin tamamı.
      expect(ekran, contains('etiket: metin,'));
      expect(kaynaktanKart('profile_banner_sinir'), PaywallKarti.varlik);
    });

    test('bitmiş Premium "yeniden başlat" der', () {
      expect(
          ekran,
          contains('bitis == null ? l10n.premiumDurumGec : '
              'l10n.premiumDurumYeniden'));
      expect(trMetni('premiumDurumYeniden'), "Premium'u yeniden başlat");
      expect(trMetni('premiumSayacVarlik'), '{sayi}/{sinir} varlık');
      expect(trMetni('premiumDurumGecSayac'), '{durum} · {sayac}');
    });
  });

  group('#3 Premium sayfası', () {
    final src = ekranKaynagiSync('lib/widgets/premium_abonelik_satiri.dart');

    test('kart çerçevesi ve ikon yok, başlık yalnız plan', () {
      final build = src.substring(src.indexOf('class PremiumAbonelikSatiri'),
          src.indexOf('class _YillikTasarrufSatiri'));
      expect(build, isNot(contains('SandikCard(')));
      expect(build, isNot(contains('workspace_premium')));
      expect(build, contains('l10n.prmPlanYillik'));
      expect(trMetni('prmPlanYillik'), 'Yıllık plan');
      expect(trMetni('prmPlanAylik'), 'Aylık plan');
      expect(trMetni('prmPlanHediye'), 'Hediye');
    });
  });

  group('#4-5 tek satırlar', () {
    for (final yol in [
      'lib/widgets/zekat_sheet.dart',
      'lib/widgets/hedef_sheet.dart',
      'lib/screens/halka_arz_screen.dart',
    ]) {
      test('$yol: 8 pt alt boşluk, ortak ikon kutusu, text58 ok', () {
        final s = ekranKaynagiSync(yol);
        expect(s, contains('bottom: SandikSpace.sm'));
        expect(s, isNot(contains('bottom: SandikSpace.lg')));
        expect(s, contains('SandikIkonKutusu('));
        expect(s, isNot(contains('color: c.text36')));
      });
    }

    test('ortak portföy satırı ve Ayarlar aynı kutuyu kullanır', () {
      final p = ekranKaynagiSync('lib/screens/profile_screen.dart');
      final ortak = p.substring(p.indexOf('Widget _buildOrtaklikKarti()'));
      expect(ortak.substring(0, ortak.indexOf('\n  }\n')),
          contains('SandikIkonKutusu(Icons.people_outline_rounded)'));
      final ayar = ekranKaynagiSync('lib/screens/settings_screen.dart');
      final tile = ayar.substring(ayar.indexOf('class _SettingsTileState'));
      expect(tile.substring(0, tile.indexOf('\n}\n')),
          allOf(contains('SandikIkonKutusu(icon, renk: color)'),
              contains('color: context.c.text58')));
      // Grubun sonundaki 32 pt ve kilometre şeridinin 24 pt'si aynen.
      expect(p, contains('const SizedBox(height: SandikSpace.xl),\n'
          '                        // Ayarlar:'));
    });
  });
}
