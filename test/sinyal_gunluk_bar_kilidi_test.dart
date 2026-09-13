import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/utils/chart_interval_policy.dart';

/// Sinyal üretimi GÜN VE ÜSTÜ bara kilitlidir — grafik bar seçicisi bunu
/// DEĞİŞTİREMEZ.
///
/// (Bugün iki yüzey iki farklı kaba barda: `signal_provider` haftalık,
/// `performance_screen` günlük. Bu ayrışma burada düzeltilmiyor; kilidin
/// konusu "asla dakikalık bar".)
///
/// ## Neden bu test var
/// `TechnicalAnalysisService` bar SAYISI ile çalışır: `RSI(14)` "son 14 bar"
/// demektir ve barın ne kadar sürdüğünü bilmez. Eşikler (`overbought = 70`,
/// `oversold = 30`) GÜNLÜK bar için kalibre edilmiştir. Aynı motoru 5
/// dakikalık seriye bağlarsak:
///   · `RSI(14)` sessizce "son 70 dakika" anlamına gelir,
///   · intraday'de RSI uçlara çok daha sık değdiği için motor gün içinde
///     defalarca AL/SAT üretir,
///   · `DEDUP_COOLDOWN_SAAT = 2` günlük ritme göre seçilmişti; 5dk barda
///     24 bar eder ve kullanıcıya bildirim yağar.
///
/// Bunların hiçbiri çökme değil — sessizce YANLIŞ bildirim. Bu yüzden
/// kilit teste bağlandı: grafik tarafında bar seçici eklendi diye birinin
/// "madem intraday veri var, sinyale de bağlayalım" demesi kolay.
///
/// Kilit kalkacaksa önce şunlar yapılmalı (bkz. ResolutionTier dokümanı):
/// eşiklerin intraday rejimde yeniden kalibrasyonu, cooldown'ın bar
/// süresinden türetilmesi, `prices.length < 30` kapısının yeniden
/// tanımlanması ve gösterge etiketinin barı taşıması (`RSI (14 × 1sa)`).
void main() {
  group('sinyal yolu günlük bara kilitli', () {
    test('sinyal pencereleri GÜNLÜK ya da daha KABA bar verir', () {
      // ÖLÇÜLDÜ (2026-09-14), varsayılmadı:
      //   · signal_provider: periodDays 180 → `pickForSpan` eşiği `< 180`
      //     olduğu için WEEKLY (~26 nokta),
      //   · performance_screen: kSinyalPenceresiGun = 90 → DAILY.
      // İki sinyal yüzeyi bugün farklı barda çalışıyor. Bu mevcut bir
      // durum; burada DÜZELTİLMİYOR, yalnızca intraday'e kaymaları
      // engelleniyor. Kilidin koruduğu şey "hangi kaba bar" değil,
      // "asla dakikalık bar" olması.
      expect(HistoryService.tierForPeriod(180), ResolutionTier.weekly);
      expect(HistoryService.tierForPeriod(90), ResolutionTier.daily);
      for (final gun in [90, 180]) {
        expect(HistoryService.tierForPeriod(gun).barSuresi,
            greaterThanOrEqualTo(const Duration(days: 1)),
            reason: '$gun günlük sinyal penceresi gün altı bara düştü — '
                'eşikler bu rejimde kalibresiz');
      }
    });

    test('sinyal penceresi hiçbir dakikalık tier\'a düşmez', () {
      const dakikalik = {
        ResolutionTier.oneMin,
        ResolutionTier.fiveMin,
        ResolutionTier.fifteenMin,
      };
      // Sinyal tarafında kullanılan pencereler (signal_provider: 180,
      // performance_screen: kSinyalPenceresiGun = 90).
      for (final gun in [180, 90, 365]) {
        expect(dakikalik.contains(HistoryService.tierForPeriod(gun)), isFalse,
            reason: '$gun günlük sinyal penceresi dakikalık bara düştü');
      }
    });

    test('signal_provider KAYNAKTA günlük pencereyi çağırıyor', () {
      // Kaynak metnine bakmak kırılgan ama burada KASITLI: kilit, çalışma
      // zamanı davranışı değil, çağrının KENDİSİ. Biri `periodDays`i bar
      // seçicisine bağlarsa bu satır değişir ve test kırılır.
      final src = File('lib/providers/signal_provider.dart').readAsStringSync();
      expect(src, contains('periodDays: 180'),
          reason: 'sinyal penceresi değişmiş — intraday\'e bağlandıysa '
              'bu dosyanın başındaki ön koşullar tamamlanmalı');
      // Grafik bar seçicisi sinyal yoluna sızmamalı.
      expect(src, isNot(contains('ChartIntervalPolicy')),
          reason: 'grafik bar politikası sinyal sağlayıcısına sızmış');
      expect(src, isNot(contains('manualTier')),
          reason: 'kullanıcının grafik bar seçimi sinyal üretimine sızmış');
    });

    test('sunucu tarafı da 1d interval\'e sabit', () {
      // supabase/functions/_shared/price_history.ts — push sinyallerini
      // üreten yol. İstemci kilidi tek başına yetmez: bildirimler sunucudan
      // gidiyor.
      final src =
          File('supabase/functions/_shared/price_history.ts').readAsStringSync();
      expect(src, contains('interval=1d'),
          reason: 'sunucu sinyal serisi günlük bardan çıkmış');
    });

    test('grafik politikası sinyal penceresinde intraday SUNMAZ', () {
      // İki katman birbirinden bağımsız ama tutarlı olmalı: 180 gün için
      // grafik de zaten intraday sunmuyor (Yahoo vermiyor).
      final barlar = ChartIntervalPolicy.gecerliBarlar(180);
      expect(barlar, isNot(contains(ResolutionTier.fiveMin)));
      expect(barlar, contains(ResolutionTier.daily));
    });
  });
}
