import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/chart_line_width.dart';

/// **Grafik ne kutusunun ne de Y ekseninin dışına taşar; sıklık ve çizgi
/// kalınlığı performans ekranıyla birebir aynıdır.**
///
/// Kullanıcı bulguları:
///   · "Pinch out yapınca grafik dışarı taşıyor bu çözülmeli."
///   · "Swipe hareketinde chart çizgileri y ekseni sınırlarını aşıyor,
///     aşmamalı."
///   · "Line kalınlıklarını takip grafiğindeki tüm varlıklar için performans
///     ekranındaki gibi zaman aralığına göre değişecek şekilde ayarla...
///     sıklık değeri de performans ekranındaki charttaki gibi birebir olmalı."
///
/// Not: daha önce burada "GÜNLÜK daha seyrek çizilir" diye bir grup vardı
/// (piksel bazlı seyreltme). Kullanıcı sonradan sıklığın performans ekranıyla
/// BİREBİR olmasını istedi; seyreltme kaldırıldı, okunurluk artık çizgi
/// kalınlığından geliyor. Eski gerekçeyi silmemek için buraya yazıldı.
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

  group('taşma — çizgi Y ekseni sınırlarını aşmaz', () {
    /// Stack'in `Clip.hardEdge`'i yalnızca KARTIN dışına taşmayı keser;
    /// çizim alanının (plot area) kendi sınırını fl_chart'a `clipData`
    /// söyler. Onsuz, pan/pinch sırasındaki lerp karelerinde çizgiler
    /// minY/maxY'nin dışına düşüp Y ekseni etiketlerinin üstüne basıyordu
    /// (kullanıcı ekran görüntüsü: yeşil çizgi "+10,0%" etiketini kesiyor).
    test('percent_comparison_chart clipData.all taşıyor', () {
      final src =
          File('lib/widgets/percent_comparison_chart.dart').readAsStringSync();
      expect(src, contains('clipData: const FlClipData.all()'),
          reason: 'clipData olmadan çizgi Y ekseni bandına taşar');
    });

    test('performans ekranlarıyla AYNI bayrak', () {
      // Parite: aynı hatanın üç grafikte üç farklı cevabı olmamalı.
      for (final f in const [
        'lib/screens/performance_screen.dart',
        'lib/screens/portfolio_performance_screen.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('FlClipData.all()'),
            reason: '$f clipData bayrağını kaybetmiş');
      }
    });
  });

  group('nokta sıklığı — performans ekranıyla birebir', () {
    /// Grafik katmanı, `ResolutionTier`in verdiği sıklığı İKİNCİ KEZ
    /// ezmemeli. Piksel bazlı seyreltme GÜNLÜK seriyi 288 noktadan ~42'ye
    /// indiriyordu; performans ekranı aynı günü 288 noktanın tamamıyla
    /// çiziyor. Kullanıcı: "sıklık değeri de performans ekranındaki
    /// charttaki gibi birebir olmalı."
    test('çizim yolunda seyreltme YOK', () {
      final src = File('lib/widgets/percent_comparison_chart.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .where((l) => !l.trimLeft().startsWith('///'))
          .join('\n');

      expect(src, isNot(contains('seyreltSpots(')),
          reason: 'sıklık tek yerden (ResolutionTier) gelmeli; grafik '
              'katmanı onu ezerse iki ekran yeniden ayrışır');
      expect(src, isNot(contains('hedefNoktaSayisi')),
              reason: 'piksel bazlı nokta hedefi geri gelmiş');
    });

    test('viewport kırpması korunur — çizgi kenara ulaşır', () {
      // Kırpma seyreltme DEĞİLDİR: görünen nokta sayısını değiştirmez,
      // yalnızca ekran dışındaki noktaları fl_chart'a vermez.
      final src =
          File('lib/widgets/percent_comparison_chart.dart').readAsStringSync();
      expect(src, contains('_gorunurSpots'));
    });
  });

  group('çizgi kalınlığı — dönemle değişir, iki ekranda AYNI', () {
    test('merdiven performans ekranındaki değerlerin aynısı', () {
      // Performans ekranının tarihsel merdiveni — birebir korunmalı.
      expect(donemCizgiKalinligi(0), 1.6, reason: 'gün içi');
      expect(donemCizgiKalinligi(1), 1.6);
      expect(donemCizgiKalinligi(7), 2.0);
      expect(donemCizgiKalinligi(30), 2.4);
      expect(donemCizgiKalinligi(90), 2.0);
      expect(donemCizgiKalinligi(180), 1.8);
      expect(donemCizgiKalinligi(365), 1.5);
    });

    test('yoğun dönem ince, seyrek dönem kalın', () {
      // Kuralın SEBEBİ: nokta yoğunluğu arttıkça kalın çizgi zikzağı yutar.
      expect(donemCizgiKalinligi(1), lessThan(donemCizgiKalinligi(30)),
          reason: '5 dakikalık seri, günlük seriden ince çizilmeli');
      expect(donemCizgiKalinligi(7), lessThan(donemCizgiKalinligi(30)));
    });

    test('kıyas çizgisi her dönemde ayırt edilebilir', () {
      for (final gun in [1, 7, 30, 180, 365]) {
        final normal =
            kiyasCizgiKalinligi(periodDays: gun, vurgulu: false, odakta: false);
        final portfoy =
            kiyasCizgiKalinligi(periodDays: gun, vurgulu: true, odakta: false);
        // `closeTo`: 2,8 − 1,8 kayan noktada 0,9999999999999998 çıkıyor.
        expect(portfoy - normal, closeTo(vurguKalinlikArtisi, 1e-9),
            reason: '\$gun günde kıyas çizgisi diğerlerinden ayrılmıyor');
        expect(vurguKalinlikArtisi, greaterThanOrEqualTo(1.0),
            reason: '1px altındaki fark telefonda gözle seçilmiyor');
        expect(normal, donemCizgiKalinligi(gun),
            reason: 'vurgusuz seri dönemin tabanını almalı');
      }
    });

    test('odak kalınlığı da artırır — renk tek başına yetmez', () {
      final sade =
          kiyasCizgiKalinligi(periodDays: 30, vurgulu: false, odakta: false);
      final odakta =
          kiyasCizgiKalinligi(periodDays: 30, vurgulu: false, odakta: true);
      expect(odakta, greaterThan(sade));
    });

    test('üç ekran da ORTAK fonksiyonu çağırır', () {
      // Kopyalanmış merdiven = ekranların sessizce ayrışması.
      for (final f in const [
        'lib/widgets/percent_comparison_chart.dart',
        'lib/screens/performance_screen.dart',
        'lib/screens/portfolio_performance_screen.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src, contains('CizgiKalinligi('),
            reason: '$f kendi kalınlık merdivenini taşıyor olabilir');
      }
    });
  });
}
