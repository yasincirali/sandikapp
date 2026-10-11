
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';
import 'helpers/kaynak.dart';

/// Teknik gösterge panelinin fiyat penceresi.
///
/// ## Yakaladığı hata (2026-09-10)
/// Panel 180 gün istiyordu ve göstergeler HİÇBİR varlıkta çizilmiyordu —
/// ekranda kalıcı olarak "fiyat geçmişi şu an çekilemedi" yazıyordu.
/// Kullanıcı bunu bir fonda bildirdi ama ölçüm hisseleri de kapsadığını
/// gösterdi (THYAO 26 nokta, TEFAS:DPP 26 nokta, eşik 30).
///
/// Sebep TEFAS ya da Yahoo değildi — API'ler 125 nokta döndürüyordu.
/// `HistoryService`in çözünürlük merdiveni 180 günü HAFTALIK katmana
/// düşürüyor ve günlük noktaları haftalık kovalara sıkıştırıyordu.
///
/// Panel ise GÜNLÜK seri varsayar: MACD 26, Bollinger 20, ADX 2×14 nokta
/// ister ve bu sayılar GÜN cinsindendir.
///
/// Bu dosya ağa ÇIKMAZ; kuralı merdivenin kendisinden okur.
void main() {
  group('sinyal penceresi', () {
    test('GÜNLÜK katmanda kalır — haftalığa düşmez', () {
      // Asıl değişmez bu. Pencere haftalığa düşerse nokta sayısı ~4'e
      // bölünür ve panel eşiğin altında kalıp hiç çizilmez (2026-09-10).
      // 2026-10-11'den beri katman AÇIKÇA verilir; pencere sunucuyla
      // aynı 6 ay (denetim bulgu 8).
      expect(kSinyalCozunurlugu, ResolutionTier.daily);
    });

    test('pencere tek başına haftalığa düşerdi — katman parametresi şart', () {
      // 180 günü kendi başına isteyen haftalık katman alır; bu yüzden her
      // çağrı `cozunurluk: kSinyalCozunurlugu` geçmek zorunda (aşağıda).
      expect(HistoryService.tierForPeriod(kSinyalPenceresiGun),
          ResolutionTier.weekly);
    });

    test('en uzun göstergeyi ve Premium parametre sınırını besler', () {
      // Günlük katmanda ~0,68 nokta/gün (hafta sonu + tatil): 180 gün ≈
      // 122 nokta. En uzun ayar EMA uzun 100, MACD 80+30 = 110.
      final tahminiNokta = (kSinyalPenceresiGun * 0.68).floor();
      final enUzun = [
        for (final t in GostergeParametreleri.tanimlar.entries)
          if (t.key != IndicatorId.macd)
            for (final p in t.value) p.enCok,
      ].reduce((a, b) => a > b ? a : b);
      final macdEnUzun = GostergeParametreleri.tanimlar[IndicatorId.macd]!
          .where((p) => p.anahtar != 'hizli')
          .fold<int>(0, (a, p) => a + p.enCok);
      expect(tahminiNokta, greaterThanOrEqualTo(enUzun));
      expect(tahminiNokta, greaterThanOrEqualTo(macdEnUzun));
    });

    test('şerit ve panel AYNI pencereyi ister', () {
      // İkisi `HistoryService` önbelleğini paylaşıyor. Farklı pencere
      // isterlerse iki ayrı ağ çağrısı olur ve aynı varlık için FARKLI
      // sinyal gösterebilirler.
      final kaynak = ekranKaynagiSync('lib/screens/asset_detail_screen.dart')
          .replaceAll('\r\n', '\n');

      // Ham sayı kalmamalı — iki çağrı da sabite bağlı olmalı.
      expect(kaynak.contains('periodDays: 180'), isFalse,
          reason: 'Bir çağrı hâlâ 180 gün istiyor.');
      // Üç çağrı: şerit, panel ve açılış kapısının ön çekimi (2026-09-28,
      // `acilis_kapisi.dart`) — ön çekim de AYNI anahtarı ister ki şerit ve
      // panel seriyi önbellekten alsın, ağa ikinci kez çıkmasın.
      expect(
        RegExp(r'periodDays: kSinyalPenceresiGun,\s*cozunurluk: kSinyalCozunurlugu')
            .allMatches(kaynak)
            .length,
        3,
        reason: 'Şerit, panel ya da açılış ön çekiminden biri sabite '
            'bağlı değil.',
      );
    });
  });
}
