import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// **Etikette yazan dönem ile çizilen veri aynı pencereden gelmeli.**
///
/// ## Neden bu test var
/// Takip listesinde "GÜNLÜK" seçildiğinde BEŞ günlük, "6A" seçildiğinde BİR
/// yıllık değişim gösteriliyordu. Kozmetik bir kusur değildi: satır yüzdesi
/// (`watchlist_provider.dart`) serinin ilk ve son noktasından hesaplanır, yani
/// kullanıcı doğrudan yanlış rakama bakıyordu.
///
/// Kök neden `HistoryService`'te üç eşlemenin birbirinden habersiz olmasıydı:
///   1. `rangeForPeriod` merdiveninde `'1d'` ve `'6mo'` basamakları YOKTU —
///      1 gün `'5d'`e, 180 gün `'1y'`e düşüyordu.
///   2. Dönen seri `periodDays`'e hiç kırpılmıyordu; range dönemden geniş
///      olduğunda fazlalık öylece grafiğe giriyordu.
///   3. Ağdaki interval range'den türüyordu, çözünürlük katmanından değil —
///      katman "5 dakikalık" derken veri saatlik geliyordu.
///
/// 6A ile 1Y aynı range'e düştüğü için önbellek anahtarı da (`sym_range`)
/// aynıydı: iki sekme BİREBİR aynı seriyi gösteriyordu.
///
/// ## Bu testin sınırı
/// Ağa çıkmaz. Eşlemeleri ve kırpma cebirini denetler; Yahoo'nun bir
/// range/interval çiftini gerçekten kabul ettiğini doğrulamaz.
void main() {
  group('dönem → range merdiveni', () {
    test('hiçbir iki dönem aynı önbellek anahtarına düşmez', () {
      // En kritik değişmez. Önbellek anahtarı `sym_range_interval`; iki dönem
      // bu ikilinin ikisinde de eşleşirse aynı seriyi paylaşır ve sekmeler
      // arasında hiçbir rakam değişmez — 6A ile 1Y'de yaşanan tam olarak
      // buydu.
      //
      // Not: 1H ile 1A aynı range'i (`1mo`) kullanır ve bu DOĞRUDUR — ayrımı
      // interval (`1h` ↔ `1d`) ile kırpma sağlar. Değişmez range'in tekliği
      // değil, ikilinin tekliğidir.
      final anahtarlar = watchlistPeriods
          .map((p) => '${HistoryService.rangeForPeriod(p.days)}'
              '_${HistoryService.tierForPeriod(p.days).yahooInterval}')
          .toList();

      expect(anahtarlar.toSet().length, anahtarlar.length,
          reason: 'dönemler aynı range+interval ikilisini paylaşamaz: '
              '$anahtarlar');
    });

    test('range dönemi KAPSAR — asla dar kalmaz', () {
      // Range dönemden dar olursa seri sessizce kırpılır ve grafik seçilen
      // dönemin yalnızca bir dilimini gösterir.
      const rangeGunleri = <String, int>{
        '1d': 1,
        '5d': 5,
        '1mo': 30,
        '3mo': 90,
        '6mo': 180,
        '1y': 365,
        '5y': 1825,
      };

      for (final p in watchlistPeriods) {
        final range = HistoryService.rangeForPeriod(p.days);
        final kapsam = rangeGunleri[range];
        expect(kapsam, isNotNull, reason: 'bilinmeyen range: $range');
        expect(kapsam, greaterThanOrEqualTo(p.days),
            reason: '${p.label} (${p.days} gün) için $range yetersiz');
      }
    });

    test('bilinen bozuk vakalar geri gelmez', () {
      // Üretimde ölçülmüş iki hata.
      expect(HistoryService.rangeForPeriod(1), '1d',
          reason: 'GÜNLÜK beş günlük veri çekiyordu');
      expect(HistoryService.rangeForPeriod(180), '6mo',
          reason: '6A bir yıllık veri çekiyordu');
      expect(HistoryService.rangeForPeriod(180),
          isNot(HistoryService.rangeForPeriod(365)),
          reason: '6A ile 1Y aynı seriyi gösteriyordu');
    });
  });

  group('çözünürlük katmanı veriyle uyumlu', () {
    test('katman interval i range ile çelişmez', () {
      // `getSymbolHistory` interval i KATMANDAN alır. Katman "5 dakikalık"
      // derken range bir haftalıksa Yahoo isteği reddeder ya da kaba veri
      // döner; ikisi de sessiz bozulmadır.
      // `1wk` + `6mo`/`1y` ikilisi Yahoo'ya karşı DOĞRULANDI (2026-09-03):
      // range=6mo&interval=1wk → 28 nokta, granularity `1wk`
      // range=1y&interval=1wk  → 54 nokta, granularity `1wk`
      // Katman `pickForSpan`'e devredildiğinde bu ikili ortaya çıktı; kabul
      // edilmeden önce gerçek API ile denendi.
      const uyumlu = <String, Set<String>>{
        '5m': {'1d'},
        '1h': {'5d', '1mo'},
        '1d': {'1mo', '3mo', '6mo', '1y'},
        '1wk': {'6mo', '1y', '5y'},
      };

      for (final p in watchlistPeriods) {
        final range = HistoryService.rangeForPeriod(p.days);
        final interval = HistoryService.tierForPeriod(p.days).yahooInterval;
        expect(uyumlu[interval], contains(range),
            reason: '${p.label}: $interval interval i $range ile uyumsuz');
      }
    });
  });

  group('kırpma — clipToPeriod', () {
    /// `gunOnce` gün önceki bir zaman damgası.
    int ts(int gunOnce) =>
        DateTime.now().subtract(Duration(days: gunOnce)).millisecondsSinceEpoch;

    test('pencere dışındaki noktalar atılır', () {
      final seri = {
        ts(20): 100.0,
        ts(10): 110.0,
        ts(3): 120.0,
        ts(1): 130.0,
      };

      final k = HistoryService.clipToPeriod(seri, 7);

      expect(k.length, 2, reason: 'yalnızca son 7 günün noktaları kalmalı');
      expect(k.values, containsAll(<double>[120.0, 130.0]));
    });

    test('pencerede iki noktadan az kalırsa SON İKİ nokta döner', () {
      // Günde tek fiyat açıklayan TEFAS fonlarının vakası. Ham serinin
      // tamamına dönmek "GÜNLÜK" etiketiyle bir aylık değişim göstermek
      // olurdu — kaçındığımız hatanın kendisi.
      final seri = {
        ts(30): 100.0,
        ts(20): 110.0,
        ts(10): 120.0,
      };

      final k = HistoryService.clipToPeriod(seri, 1);

      expect(k.length, 2);
      expect(k.values, containsAll(<double>[110.0, 120.0]),
          reason: 'en yeni iki nokta korunmalı');
      expect(k.values, isNot(contains(100.0)),
          reason: 'ham serinin tamamına dönülmemeli');
    });

    test('iki noktadan kısa seri olduğu gibi geçer', () {
      final seri = {ts(40): 100.0};
      expect(HistoryService.clipToPeriod(seri, 1), seri);
    });

    test('tamamı pencere içindeyse hiçbir nokta kaybolmaz', () {
      final seri = {ts(5): 100.0, ts(3): 110.0, ts(1): 120.0};
      expect(HistoryService.clipToPeriod(seri, 30).length, 3);
    });

    test('pencere SON NOKTAYA çapalanır — hafta sonu seansı silmez', () {
      // Pazar günü "GÜNLÜK" seçildiğinde son seans Cuma'dadır. `now`'dan
      // geriye sayan bir kırpma Cuma'nın tamamını dışarıda bırakır ve grafik
      // boşalır; son noktadan geriye saymak bir seans dolusu veri bırakır.
      // Çapa BİR KEZ okunur. Eskiden `ts(3)` üç kez ayrı ayrı çağrılıyordu ve
      // her çağrı `DateTime.now()`'a gidiyordu; aralarında milisaniye
      // geçtiğinde noktalar birbirine göre kayıyor, kırpma penceresi bir
      // noktayı dışarıda bırakıyordu. Tam paket koşumunda kırılıp tek başına
      // geçen bir test bu yüzden ortaya çıktı (gece yarısını geçen koşum).
      final acilis = ts(3);
      final cuma = {
        acilis: 100.0, // Cuma açılış
        acilis + 3600 * 1000: 101.0,
        acilis + 7200 * 1000: 102.0,
      };

      final k = HistoryService.clipToPeriod(cuma, 1);

      expect(k.length, 3,
          reason: 'seansın tamamı korunmalı — üç gün önce olsa bile');
    });
  });
}
