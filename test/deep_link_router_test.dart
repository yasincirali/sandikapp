import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/main_navigation_screen.dart';
import 'package:portfoy_takip/services/deep_link_router.dart';

/// Widget ve Canlı Etkinlik dokunuşunun hedefi.
///
/// Kullanıcı isteği (2026-09-12): "hem widget hem de canlı aktivitelerde
/// tıklandığında performans ekranı günlük grafik açılmalı."
///
/// Canlı Etkinlik iOS'a özgü ve bu makinede iOS derlemesi yok — yani
/// dokunuşun kendisi burada çalıştırılamaz. Bu yüzden KARAR saf bir
/// fonksiyona ayrıldı: "hangi URI nereye gider" sorusu platform olmadan
/// doğrulanabiliyor. Native taraf yalnızca doğru URI'yi üretmekle
/// yükümlü ve onu ayrı bir test denetliyor
/// (`deep_link_native_uri_test.dart`).
void main() {
  group('hedef sekme', () {
    test('widget dokunuşu performans sekmesine gider', () {
      expect(
        DeepLinkRouter.hedefSekmeMetin('sandik://widget/home?homeWidget=1'),
        MainNavigationScreen.performansSekmesi,
      );
    });

    test('canlı etkinlik dokunuşu da AYNI yere gider', () {
      expect(
        DeepLinkRouter.hedefSekmeMetin(
            'sandik://live-activity/summary?homeWidget=1'),
        MainNavigationScreen.performansSekmesi,
      );
    });

    test('query parametresi olmadan da eşleşir', () {
      // `?homeWidget` iOS eklentisinin süzgeci için var; eşleme kararı
      // ona bağlı OLMAMALI. Android tarafı parametresiz gönderse bile
      // yönlendirme çalışmalı.
      expect(
        DeepLinkRouter.hedefSekmeMetin('sandik://widget/home'),
        MainNavigationScreen.performansSekmesi,
      );
    });
  });

  group('tanınmayan girdi — yönlendirme YOK', () {
    test('null ve boş', () {
      expect(DeepLinkRouter.hedefSekmeMetin(null), isNull);
      expect(DeepLinkRouter.hedefSekmeMetin(''), isNull);
    });

    test('başka şema', () {
      // `https://` ile gelen bir bağlantı bu yönlendiriciye ait değil.
      expect(DeepLinkRouter.hedefSekmeMetin('https://sandik.app/widget/home'),
          isNull);
    });

    test('tanınmayan host', () {
      expect(DeepLinkRouter.hedefSekmeMetin('sandik://ayarlar'), isNull);
      expect(DeepLinkRouter.hedefSekmeMetin('sandik://'), isNull);
    });

    test('bozuk URI ÇÖKMEZ', () {
      // Native taraf beklenmedik bir şey gönderirse uygulama açılmayı
      // sürdürmeli — derin bağlantı ikincil bir yoldur.
      for (final bozuk in ['::::', 'sandik:/', '   ', 'sandik']) {
        expect(() => DeepLinkRouter.hedefSekmeMetin(bozuk), returnsNormally,
            reason: '"$bozuk" çökertiyor.');
      }
    });
  });

  test('performans sekmesi indeksi ekranın SIRASIYLA tutarlı', () {
    // Bu sabit elle yazılmış bir indeks; `_screens` listesi değişirse
    // sessizce yanlış sekmeye götürür. Kaynakta sıranın hâlâ
    // beklenen şekilde olduğunu denetliyoruz.
    final kaynak = File('lib/screens/main_navigation_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    final bas = kaynak.indexOf('final List<Widget> _screens = [');
    expect(bas, isNot(-1), reason: '_screens listesi bulunamadı.');
    final son = kaynak.indexOf('];', bas);
    final liste = kaynak.substring(bas, son);

    // Sıradaki 4. öğe (indeks 3) performans ekranı olmalı.
    final satirlar = liste
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.contains('(') && !l.contains('_screens'))
        .toList();

    expect(satirlar.length, greaterThan(MainNavigationScreen.performansSekmesi),
        reason: '_screens listesi beklenenden kısa.');
    expect(
      satirlar[MainNavigationScreen.performansSekmesi]
          .contains('PortfolioPerformanceScreen'),
      isTrue,
      reason: 'indeks ${MainNavigationScreen.performansSekmesi} artık '
          'performans ekranı değil: "${satirlar[MainNavigationScreen.performansSekmesi]}"',
    );
  });
}
