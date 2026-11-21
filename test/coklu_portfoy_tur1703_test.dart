import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Çoklu portföy turu (17.03): sınır uyarısı, satın alınca iş sürer, güvenli
/// silme birincil, tek portföyde çip adı. Görsel sıra
/// `coklu_portfoy_ui_test`'te widget olarak; burada kaynak kilitleri.
String _oku(String yol) => File(yol).readAsStringSync();

void main() {
  test('portfoy_secici: sınır dolu → sinirUyarisi(portfoy_limit), çıplak paywall yok', () {
    final k = _oku('lib/widgets/portfoy_secici.dart');
    expect(k, contains("kaynak: 'portfoy_limit'"));
    expect(k, contains('sinirUyarisi('));
    expect(k, contains('portfolioLimitFree'));
    expect(k, isNot(contains('PaywallScreen.show')));
  });

  test(
    'portfoy_secici: tek portföyde Tümü çipi ana portföy adını gösterir',
    () {
      final k = _oku('lib/widgets/portfoy_secici.dart');
      expect(
        k,
        contains(
          'liste.isEmpty\n            ? (ref.watch(anaPortfoyAdiProvider) ?? l.portfoyAnaUzun)',
        ),
      );
      expect(k, contains('onTap: () => sec(PortfoySecimi.tumu)'));
    },
  );

  test(
    'kısmi aktarım ve ortak paylaşım: paywall beklenir, satın alınca devam',
    () {
      final kismi = _oku('lib/widgets/kismi_aktarim_sayfasi.dart');
      expect(kismi, contains("feature: 'kismi_aktarim'"));
      expect(kismi, contains("final aldi = await PaywallScreen.show(context,"));
      expect(kismi, contains('_kismi = true'));
      final ortak = _oku('lib/widgets/ortak_paylasim_sayfasi.dart');
      expect(ortak, contains("feature: 'ortak_portfoy_secimi'"));
      expect(ortak, contains('await PaywallScreen.show(context'));
      expect(
        ortak,
        contains('showOrtakPaylasimSayfasi(context, ortak: ortak)'),
      );
    },
  );

  test(
    'silme sayfası: Aktar ve sil üstte, Varlıklarla sil altta; ağırlık ≤ w600',
    () {
      final k = ekranKaynagiSync('lib/screens/portfoy_yonetimi_screen.dart');
      expect(
        k.indexOf("'portfoy-aktar-sil'"),
        lessThan(k.indexOf("'portfoy-sil-onay'")),
      );
      expect(k, isNot(contains('FontWeight.w700')));
      expect(
        _oku('lib/widgets/portfoy_secici.dart')
            .contains('secili ? FontWeight.w600'),
        isTrue,
      );
    },
  );
}
