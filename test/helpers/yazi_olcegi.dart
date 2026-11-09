import 'package:flutter_test/flutter_test.dart';

/// Taşma testlerinin **büyük yazı ekseni** (Dynamic Type / Android yazı
/// boyutu).
///
/// Neden (büyük yazı taraması 2026-10-12): taşma testleri 320–430pt
/// genişliği tarıyordu ama yazıyı 1,0×'te bırakıyordu. Cihazda büyük yazı
/// açan kullanıcıda (iOS en üst kademe ≈3,1×) Sıralama, sinyal paneli,
/// grafik çubuğu, alarm sayfası ve ana kart taşıyordu; hiçbir test
/// yakalamadı. Uygulama içi yazı ayarı 1,3×'te durur ama cihazın kendi
/// ölçeğini asla kısmaz (`KullaniciYaziOlcegi`), bu yüzden eksen cihaz
/// ölçeğini taklit eder.
const yaziOlcekleri = <double>[1.0, 2.0, 3.1];

double _gecerli = 1.0;

/// [govde]'deki her testi [yaziOlcekleri]'nin her biriyle ayrı grupta koşar.
/// Pompalayan yardımcı [yaziOlceginiUygula]'yı çağırmalıdır.
void yaziOlcegiEkseni(void Function() govde) {
  for (final o in yaziOlcekleri) {
    group('yazı $o×', () {
      setUp(() => _gecerli = o);
      govde();
    });
  }
}

/// Geçerli eksen değerini cihaz yazı ölçeği olarak uygular.
void yaziOlceginiUygula(WidgetTester tester) {
  tester.platformDispatcher.textScaleFactorTestValue = _gecerli;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}
