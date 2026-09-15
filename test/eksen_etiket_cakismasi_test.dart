
import 'package:flutter_test/flutter_test.dart';
import 'helpers/kaynak.dart';

/// X ekseni etiketleri ÜST ÜSTE BİNMEMELİ.
///
/// ## Yakaladığı hata (kullanıcı bildirimi 2026-09-12, ekran görüntüsüyle)
/// Gün içi eksende "11 Eyl 04:0011 Eyl 08:0011 Eyl 12:00…" şeklinde
/// okunamaz bir şerit oluşuyordu.
///
/// Sebep iki değişikliğin birleşimi:
///   1. Piyasa kapalıyken eksen birden çok günü kapsıyor (kuyruk).
///   2. Çok günlü eksende etiket "04:00"dan "11 Eyl 04:00"a UZADI.
///
/// Adım ise sabit 240 dk (4 saat) kalmıştı — tek günlük eksen için
/// doğruydu, uzun etiketle birlikte yan yana altı etiket sığmıyordu.
///
/// Düzeltme: çok günlü gün içi eksende adım span'a göre ölçekleniyor
/// (hedef ~5 etiket) ve etiket kutusu genişliyor.
void main() {
  final kaynak = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart')
      .replaceAll('\r\n', '\n');

  group('adım etiket uzunluğuna göre açılır', () {
    test('çok günlü gün içi eksende adım SABİT değil', () {
      expect(kaynak.contains('final gunIciSpanGun ='), isTrue,
          reason: 'Span hesaplanmıyor.');
      expect(kaynak.contains('gunIciSpanGun > 1'), isTrue,
          reason: 'Çok günlü dal yok — adım 240 dk sabit kalır ve uzun '
              'etiketler çakışır.');
    });

    test('tek günlük eksende 240 dk KORUNUR', () {
      // Hafta içi normal gün içi grafiği: 00:00 / 04:00 / … doğru ritim.
      expect(kaynak.contains(': gunIciEksenAdimiDk)'), isTrue,
          reason: 'Tek günlük adım kaldırılmış.');
    });

    test('tick\'ler YUVARLAK saate düşer', () {
      // Yuvarlanmazsa "13:47" gibi etiketler çıkar.
      //
      // Hedef 5 etiketten 3'e indirildi (2026-09-12): ölçüldü — 44
      // saatlik eksende 5 etiket üretiliyordu ama ~330px genişliğe
      // yalnızca 3 tanesi sığıyor, yan yana yapışıyorlardı. Kullanıcı
      // çakışmayı iki tur üst üste bildirdi.
      //
      // Adım 3 SAATİN katına yuvarlanıyor: kaba adımlarda da 09:00 /
      // 12:00 gibi okunur değerler çıksın.
      expect(kaynak.contains('/ 3 / 180).ceilToDouble() * 180'), isTrue,
          reason: 'Adım 3 saatin katına yuvarlanmıyor — etiketler çakışır.');
    });

    test('non-intraday adımı DEĞİŞMEDİ', () {
      // Regresyon kapısı: 1H/1A/6A/1Y ekseni bu düzeltmeden etkilenmemeli.
      expect(
        kaynak.contains(
            'yuvarlakAdim((viewMaxX - viewMinX) / 5).clamp(1.0, double.infinity)'),
        isTrue,
        reason: 'Gün dışı adım mantığı bozulmuş.',
      );
    });
  });

  group('etiket kutusu', () {
    test('çok günlü eksende GENİŞLER', () {
      expect(kaynak.contains('? 88'), isTrue,
          reason: '"11 Eyl 04:00" 74px\'e sığmaz, kırpılır.');
    });

    test('tek günlük eksende 74 KALIR', () {
      expect(kaynak.contains(': 74,'), isTrue,
          reason: 'Dar etiket gereksiz yer kaplar.');
    });

    test('taşan metin ELLIPSIS olur — asla sarmaz', () {
      // Sarma, etiketi iki satıra çıkarıp grafiğin altını bozardı.
      expect(kaynak.contains('overflow: TextOverflow.ellipsis'), isTrue);
      expect(kaynak.contains('softWrap: false'), isTrue);
    });
  });

  test('eksen kenarındaki etiket ÇİZİLMEZ', () {
    // fl_chart tick'i etiketin ortasına koyuyor; kenardaki etiket çizim
    // alanının dışına taşar. Bu koruma da çakışmanın parçası.
    expect(kaynak.contains('val <= meta.min + edge || val >= meta.max - edge'),
        isTrue);
  });
}
