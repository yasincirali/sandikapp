import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/percent_comparison_chart.dart';

/// **Grafik kutusunun dışına taşmaz; GÜNLÜK daha seyrek çizilir.**
///
/// İki kullanıcı bulgusu:
///   · "Pinch out yapınca grafik dışarı taşıyor bu çözülmeli."
///   · "Grafik precisionları biraz daha düşürülebilir günlük için, sadece —
///     diğerleri düzgün çalışıyor."
void main() {
  group('taşma — çizim kendi kutusunda kalır', () {
    /// **Neden kaynak metni denetleniyor:** taşma yalnızca `LineChart`'ın
    /// pinch sırasındaki ARA lerp karelerinde oluşuyor. Widget testinde o
    /// kareyi yakalamak için gerçek bir pinch jestini fl_chart'ın implicit
    /// animasyonuyla senkron sürmek gerekir; kırılgan ve yavaş olurdu.
    /// Denetlenen değişmez ise tek satırlık ve kesin: **bu dosyada
    /// `Clip.none` bulunmamalı.**
    test('zoomable_chart.dart içinde Clip.none kalmadı', () {
      final src = File('lib/widgets/zoomable_chart.dart').readAsStringSync();

      // Yorum satırları hariç: açıklamalar eski hatayı ANLATIYOR ve içinde
      // `Clip.none` geçebilir.
      final kod = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .where((l) => !l.trimLeft().startsWith('///'))
          .join('\n');

      expect(kod, isNot(contains('Clip.none')),
          reason: 'Stack varsayılanı zaten hardEdge; `Clip.none` yazmak '
              'çizginin kartın dışına, başlığın ve dönem seçicinin üstüne '
              'basmasına izin verir (pinch sırasında ölçüldü). Taşmaya '
              'gerçekten ihtiyaç duyan bir çocuk eklenirse bu testi '
              'silmek yerine gerekçesini buraya yaz.');
    });

    test('her iki Stack de açıkça hardEdge', () {
      // "Clip.none yok" tek başına yetmez: satır tamamen silinseydi de
      // geçerdi. Niyetin YAZILI olması, bir sonraki düzenlemede yanlışlıkla
      // geri alınmasını zorlaştırır.
      final src = File('lib/widgets/zoomable_chart.dart').readAsStringSync();
      expect('clipBehavior: Clip.hardEdge'.allMatches(src).length,
          greaterThanOrEqualTo(2),
          reason: 'grafik Stack i ve crosshair katmanı ayrı ayrı kırpılmalı');
    });
  });

  group('nokta yoğunluğu — GÜNLÜK daha seyrek', () {
    // Tipik telefon: ~360px kısıt, 42px Y ekseni rezervi düşünce ~318px
    // çizim alanı.
    const telefon = 360.0;

    test('GÜNLÜK, diğer dönemlerden BELİRGİN olarak seyrek', () {
      final gunIci = PercentComparisonChart.hedefNoktaSayisi(
          kisitGenisligi: telefon, periodDays: 1);
      final aylik = PercentComparisonChart.hedefNoktaSayisi(
          kisitGenisligi: telefon, periodDays: 30);

      expect(gunIci, lessThan(aylik),
          reason: 'gün içi seri 5 dakikalık; diğerleriyle aynı sıklıkta '
              'çizilince tarak gibi görünüyordu');
      // "Biraz daha düşürülebilir" ölçülebilir bir eşiğe bağlanır: en az
      // yarıya inmeli, yoksa değişiklik gözle fark edilmez.
      expect(gunIci * 2, lessThanOrEqualTo(aylik),
          reason: 'fark en az iki kat olmalı — daha azı görünür bir '
              'iyileşme sağlamıyor');
    });

    test('diğer dönemler DEĞİŞMEDİ', () {
      // Kullanıcı: "diğerleri düzgün çalışıyor." Gün içi kuralının onlara
      // sızması bir regresyon olurdu.
      for (final gun in [7, 30, 180, 365]) {
        expect(
          PercentComparisonChart.hedefNoktaSayisi(
              kisitGenisligi: telefon, periodDays: gun),
          PercentComparisonChart.hedefNoktaSayisi(
              kisitGenisligi: telefon, periodDays: 30),
          reason: '$gun günlük dönem gün içi kuralına kaymış',
        );
      }
    });

    test('dar ekranda gün içi kuralı alt sınıra ezilmez', () {
      // Alt sınır 40 iken 200px'lik bir ekranda 200/7 ≈ 23 → 40'a
      // yükseltiliyordu ve kural pratikte devre dışı kalıyordu.
      final dar = PercentComparisonChart.hedefNoktaSayisi(
          kisitGenisligi: 200, periodDays: 1);
      final darAylik = PercentComparisonChart.hedefNoktaSayisi(
          kisitGenisligi: 200, periodDays: 30);

      expect(dar, lessThan(darAylik),
          reason: 'dar ekranda da gün içi seyrek kalmalı');
      expect(dar, greaterThanOrEqualTo(20),
          reason: 'seyreltme 4 noktanın altında zaten çalışmaz; '
              'anlamlı bir taban korunmalı');
    });

    test('geniş ekran daha çok detay gösterir', () {
      // Kural piksele bağlı olduğu için tablet/yatay modda otomatik olarak
      // detay artmalı — sabit bir sayı orada bilgi kaybı demekti.
      expect(
        PercentComparisonChart.hedefNoktaSayisi(
            kisitGenisligi: 1200, periodDays: 1),
        greaterThan(PercentComparisonChart.hedefNoktaSayisi(
            kisitGenisligi: telefon, periodDays: 1)),
      );
    });

    test('sonsuz kısıtta varsayılan genişliğe düşer', () {
      // LayoutBuilder sonsuz genişlik verebilir; NaN nokta sayısı grafiği
      // tümden çizilemez hâle getirirdi.
      final sonsuz = PercentComparisonChart.hedefNoktaSayisi(
          kisitGenisligi: double.infinity, periodDays: 1);
      expect(sonsuz, greaterThan(0));
      expect(sonsuz, lessThanOrEqualTo(400));
    });
  });
}
