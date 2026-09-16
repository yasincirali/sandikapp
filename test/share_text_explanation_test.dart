import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/recap_service.dart';

/// Paylaşım metnindeki "Nasıl hesaplandı" bölümü (2026-09-16).
///
/// **Neden var.** Paylaşılan metin ekrandan KOPUK dolaşıyor: alan gören kişi
/// kartı değil yalnızca satırları okuyor ve "enflasyonun 5 puan önündeyim"
/// iddiasını doğrulayacak hiçbir şeyi yok. Kart içindeyken ham sayılar ve
/// ölçüm aralığı ekranda duruyordu; metne geçerken düşüyorlardı.
void main() {
  group('Nasıl hesaplandı bölümü', () {
    String tamMetin() => RecapService.composeShareText(
          baslik: 'sandık · Son 1 yıl',
          degisimPct: 36.51,
          degisimEtiketi: 'Piyasa getirim',
          enflasyonPuan: 5.0,
          reelGetiriPct: 3.80,
          enIyi: const RecapAsset('THYAO', 82.15),
          xirrPct: 41.2,
          nominalPct: '+%36,5',
          tufePct: '%31,5',
          donemAralik: '31.08.25 – 31.08.26',
          nominalAralik: '31.08.25 – 31.08.26',
        );

    test('piyasa getirisinin nakit akışından arındırıldığı YAZILI', () {
      // Ekranda bile sorulan soru: "para yatırdım, yüzdem neden artmadı".
      final m = tamMetin();
      expect(m.contains('Nasıl hesaplandı'), isTrue);
      expect(m.contains('net para girişi'), isTrue);
      expect(m.contains('saf piyasa hareketidir'), isTrue);
    });

    test('puan farkı çıkarması elle doğrulanabilir', () {
      // İki ham sayı ve sonuç aynı satırda: okuyan kişi 36,5 − 31,5 = 5,0
      // çıkarmasını yapabilmeli, yoksa satır kara kutu.
      final m = tamMetin();
      expect(m.contains('+%36,5 (getirim) − %31,5 (TÜFE) = 5,0 puan'), isTrue);
    });

    test('TÜFE işaretsiz — çift işaret okunaksızdı', () {
      expect(tamMetin().contains('− +%31,5'), isFalse);
    });

    test('TÜFE penceresinin bugüne GELMEDİĞİ söyleniyor', () {
      // Endeks aylık yayımlanıyor; okuyan kişi rakamı bugüne kadarki bir
      // aralık sanarsa TÜİK'le kıyaslayıp tutmadığını görür.
      final m = tamMetin();
      expect(m.contains('son açıklanan ayda biter'), isTrue);
      expect(m.contains('TÜİK'), isTrue);
      expect(m.contains('Enflasyon ölçüm aralığı: 31.08.25 – 31.08.26'),
          isTrue);
    });

    test('reel getirinin puan farkından FARKLI olduğu yazılı', () {
      expect(tamMetin().contains('Puan farkından farklıdır'), isTrue);
    });

    test('XIRR ile piyasa getirisinin farkı açıklanıyor', () {
      expect(tamMetin().contains('farklı olması normaldir'), isTrue);
    });

    test('en iyi/en zayıfın ÖMÜRLÜK olduğu yazılı — döneme ait değil', () {
      expect(tamMetin().contains('ömürlük'), isTrue);
    });

    test('verilmeyen alanın açıklaması da yazılmaz', () {
      // Koşulluluk: enflasyon yoksa TÜFE cümlesi de yok.
      final m = RecapService.composeShareText(
        baslik: 'x',
        degisimPct: 5,
      );
      expect(m.contains('TÜİK'), isFalse);
      expect(m.contains('Reel getiri:'), isFalse);
      expect(m.contains('XIRR:'), isFalse);
      expect(m.contains('net para girişi'), isTrue);
    });

    test('yıl sonu özetinde enflasyon PENCERESİ metne girer', () {
      // Başlık takvim yılını söylüyor ("Özetim 2026") ama enflasyon sayfası
      // son 12 ayın kayan penceresi ve TÜFE aylık yayımlandığı için son
      // açıklanan ayda biter. Metinde yazılmazsa okuyan kişi başlıktaki
      // yılı varsayar.
      final d = RecapData(
        period: 'yearly',
        character: PortfolioCharacter.dengeli,
        trackedDays: 300,
        typeCount: 3,
        marketReturnPct: 36.5,
        inflationSpread: 5.0,
        inflationStart: DateTime(2025, 11, 30),
        inflationEnd: DateTime(2026, 11, 30),
      );
      final m = RecapService.shareText(d, year: 2026);
      expect(m.contains('Özetim 2026'), isTrue);
      expect(m.contains('Kasım 25 – Kasım 26'), isTrue,
          reason: 'pencere başlıktaki yıldan farklı — yazılmak zorunda');
    });

    test('pencere yoksa enflasyon aralığı satırı hiç yazılmaz', () {
      final d = RecapData(
        period: 'yearly',
        character: PortfolioCharacter.dengeli,
        trackedDays: 300,
        typeCount: 3,
        marketReturnPct: 36.5,
        inflationSpread: 5.0,
      );
      final m = RecapService.shareText(d, year: 2026);
      expect(m.contains('Enflasyon ölçüm aralığı'), isFalse);
    });

    test('hiç sayı yoksa bölüm HİÇ açılmaz — boş başlık olmaz', () {
      final m = RecapService.composeShareText(baslik: 'x');
      expect(m.contains('Nasıl hesaplandı'), isFalse);
    });

    test('açıklama tutar sızdırmaz — kural metnin tamamı için', () {
      // `recap_service_test` ana satırlar için kilitliyor; açıklama
      // bölümü formül anlatıyor, rakam değil.
      final aciklama = tamMetin().split('Nasıl hesaplandı')[1];
      expect(aciklama.contains('₺'), isFalse);
      // Yıl iki haneli yazılıyor (gizlilik kuralı, bkz.
      // `PeriodSummaryService._aralikMetni`), yani tarihler zaten dört
      // haneli sayı üretmiyor; yine de kalıbı çıkarıp kontrol ediyoruz.
      final tarihsiz =
          aciklama.replaceAll(RegExp(r'\d{2}\.\d{2}\.\d{2}'), '');
      expect(RegExp(r'\d{4,}').hasMatch(tarihsiz), isFalse,
          reason: 'dört haneli sayı tutar demektir');
    });
  });
}
