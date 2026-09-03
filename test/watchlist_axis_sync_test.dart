import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/widgets/watchlist_chart.dart';

/// **Aynı grafikteki her seri AYNI pencereden gelmeli.**
///
/// ## Neden bu test var
/// Takip listesi grafiğinde portföy çizgisi diğer serilerle hizasızdı:
/// ekranın en solundan düz başlıyor, izlenen varlıklar ise ortalardan
/// başlıyordu (kullanıcı ekran görüntüsü, GÜNLÜK sekmesi).
///
/// Kök neden iki AYRI veri yolunun iki AYRI pencere üretmesiydi:
///   · izlenen varlıklar → `getSymbolHistory` → `rangeForPeriod` + `clipToPeriod`
///   · portföy çizgisi   → `getPortfolioHistory` → KENDİ range merdiveni,
///     kırpma YOK
///
/// Ölçülen sonuç (GÜNLÜK): sembol serisi `1d` çekip 1 güne kırpılırken portföy
/// `5d` çekip hiç kırpılmıyordu → **96 saatlik** pencere kayması.
///
/// Bu yalnızca kozmetik değildi. `normalizeSeries` dönem başını serinin İLK
/// noktasından alır; portföy dönemin dışındaki bir noktaya göre normalize
/// olunca hem çizgi hem açıklamadaki rakam yanlış çıkıyordu — ölçülen hata
/// %1,00 yerine %10,02 idi.
///
/// ## İkinci hata: hafta sonu
/// Saatlik grid hafta sonu slotlarını atlar, ama pencere `now`'dan geriye
/// sayıyordu. Pazar günü GÜNLÜK seçildiğinde 24 slotun tamamı Cts/Paz'a
/// düşüyor ve portföy çizgisi TAMAMEN kayboluyordu (ölçüldü: Pazar → 0 slot).
/// `clipToPeriod` bu sorunu sembol tarafında son VERİ noktasına çapalanarak
/// çözmüştü; portföy tarafı aynı korumadan yoksundu.
///
/// ## Bu testin sınırı
/// Ağa çıkmaz. Pencere cebirini denetler; Yahoo'nun döndürdüğü gerçek noktaları
/// doğrulamaz.
void main() {
  group('iki veri yolu aynı pencereyi kullanır', () {
    test('her dönemde range ORTAK merdivenden gelir', () {
      // Değişmez: `getPortfolioHistory` artık kendi kopyasını tutmuyor,
      // `rangeForPeriod`'u çağırıyor. Bu test o merdivenin takip listesinin
      // KULLANDIĞI dönemleri kapsadığını sabitler.
      //
      // Eski kopyanın ürettiği değerler (regresyon olarak yasak):
      //   1 gün → '5d'  (doğrusu '1d')
      //   7 gün → '5d'  (doğrusu '1mo')
      const eskiKopyaninUrettigi = {1: '5d', 7: '5d'};

      for (final p in watchlistPeriods) {
        final range = HistoryService.rangeForPeriod(p.days);
        final eski = eskiKopyaninUrettigi[p.days];
        if (eski != null) {
          expect(range, isNot(eski),
              reason: '${p.label}: portföy merdiveni sembol merdiveniyle '
                  'yeniden ayrıştı — iki seri farklı pencereden gelir');
        }
      }

      // Bilinen doğru değerler.
      expect(HistoryService.rangeForPeriod(1), '1d');
      expect(HistoryService.rangeForPeriod(7), '1mo');
    });

    test('kırpma penceresi iki yolda da AYNI kuralla kapanır', () {
      // `clipToPeriod` her iki yolda da uygulanır; aynı ham seri aynı dönemde
      // aynı pencereye inmeli.
      final now = DateTime(2026, 9, 4, 18);
      int ms(DateTime d) => d.millisecondsSinceEpoch;

      // Beş günlük saatlik ham seri (portföyün eskiden döndürdüğü genişlik).
      final ham = <int, double>{
        for (var i = 0; i <= 120; i++)
          ms(now.subtract(Duration(hours: i))): 1000.0 + i,
      };

      final kirpilmis = HistoryService.clipToPeriod(ham, 1);
      final ts = kirpilmis.keys.toList()..sort();
      final genislik = Duration(milliseconds: ts.last - ts.first);

      expect(genislik.inHours, lessThanOrEqualTo(24),
          reason: 'GÜNLÜK penceresi bir günü aşamaz — aşarsa portföy çizgisi '
              'izlenen varlıkların soluna taşar');
    });

    test('yüzde tabanı dönem İÇİNDE kalır', () {
      // Asıl zarar buydu: kırpılmamış seri dönem dışındaki bir noktaya göre
      // normalize oluyor, grafik de açıklama da yanlış rakam gösteriyordu.
      final now = DateTime(2026, 9, 4, 18);
      int ms(DateTime d) => d.millisecondsSinceEpoch;

      // Son 1 günde %1, önceki 4 günde %9 kazanmış bir portföy.
      final ham = <int, double>{};
      for (var i = 0; i <= 120; i++) {
        ham[ms(now.subtract(Duration(hours: i)))] = i <= 24
            ? 1010.0 - (i / 24.0) * 10.0
            : 1000.0 - ((i - 24) / 96.0) * 82.0;
      }

      final kirpisiz = normalizeSeries(ham)!;
      final kirpili = normalizeSeries(HistoryService.clipToPeriod(ham, 1))!;

      expect(kirpili.totalReturnPct, closeTo(1.0, 0.05),
          reason:
              'GÜNLÜK sekmesinde gösterilen oran son bir günün oranı olmalı');
      expect(kirpisiz.totalReturnPct, greaterThan(9.0),
          reason: 'kırpılmamış serinin hatalı olduğu ölçüldü — bu satır '
              'hatanın büyüklüğünü belgeler');
    });
  });

  group('hafta sonu portföy çizgisini silmez', () {
    test('Pazar günü grid son iş gününe çapalanır', () {
      // Ölçülmüş hata: Pazar → 0 slot → çizgi hiç çizilmez.
      final pazar = DateTime(2026, 9, 6, 15);
      final capa = HistoryService.sonIsGunu(pazar);

      expect(capa.weekday, DateTime.friday,
          reason: 'saatlik grid hafta sonunu atlar; pencere de hafta sonundan '
              'başlarsa tamamen boşalır');
      expect(capa.hour, 15, reason: 'günün saati korunmalı');
    });

    test('Cumartesi de Cuma ya çekilir', () {
      final cumartesi = DateTime(2026, 9, 5, 9);
      expect(HistoryService.sonIsGunu(cumartesi).weekday, DateTime.friday);
    });

    test('hafta içi gün DEĞİŞMEZ', () {
      // Çapa yalnızca hafta sonunda devreye girmeli; hafta içi bir günü
      // geriye çekmek bir seansı sessizce kaybettirirdi.
      for (final gun in [
        DateTime(2026, 8, 31, 12), // Pzt
        DateTime(2026, 9, 2, 12), // Çar
        DateTime(2026, 9, 4, 12), // Cum
      ]) {
        expect(HistoryService.sonIsGunu(gun), gun,
            reason: '${gun.weekday}. gün hafta içi — dokunulmamalı');
      }
    });

    test('ÜRETİM IZGARASI haftanın yedi günü de dolu', () {
      // `gridSlotlari` `getPortfolioHistory`'nin GERÇEKTEN kullandığı
      // fonksiyon; `now` dışarıdan verilebildiği için hafta sonu dalı hafta
      // içi koşan bir testte de çalışır. (İlk yazımda bu ızgara yerel olarak
      // taklit ediliyordu ve çapa sabote edildiğinde test geçiyordu.)
      const ad = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cts', 'Paz'];

      for (var g = 0; g < 7; g++) {
        final gun = DateTime(2026, 8, 31, 15).add(Duration(days: g));
        final slotlar = HistoryService.gridSlotlari(
          now: gun,
          periodDays: 1,
          hourly: true,
        );

        expect(slotlar.length, greaterThanOrEqualTo(2),
            reason: '${ad[gun.weekday - 1]} günü GÜNLÜK ızgarası '
                '${slotlar.length} slot — portföy çizgisi çizilemez '
                '(normalizeSeries iki noktanın altında null döner)');
      }
    });

    test('ızgara hafta sonu SLOTU üretmez', () {
      // Çapa, hafta sonunu atlama kuralını bozmamalı: Cts/Paz slotları hâlâ
      // elenmeli, yoksa grafikte düz bir plato belirir.
      for (var g = 0; g < 7; g++) {
        final gun = DateTime(2026, 8, 31, 15).add(Duration(days: g));
        for (final ts in HistoryService.gridSlotlari(
          now: gun,
          periodDays: 1,
          hourly: true,
        )) {
          final d = DateTime.fromMillisecondsSinceEpoch(ts);
          expect(d.weekday, isNot(DateTime.saturday));
          expect(d.weekday, isNot(DateTime.sunday));
        }
      }
    });

    test('uzun dönemde ızgara hafta sonunu ELEMEZ', () {
      // Günlük ızgarada eleme YAPILMAMALI — haftada 5 vs 7 nokta uzun
      // dönemde önemsiz, ama eleme yapılırsa 30 günlük seri 22 noktaya iner.
      final slotlar = HistoryService.gridSlotlari(
        now: DateTime(2026, 9, 4, 15),
        periodDays: 30,
        hourly: false,
      );

      expect(slotlar.length, greaterThan(25),
          reason: '30 günlük ızgara ${slotlar.length} nokta — hafta sonu '
              'eleniyor olmamalı');
    });
  });

  group('ORTAK PENCERE — seriler aynı anda başlar ve biter', () {
    // ## Bulgu (kullanıcı ekran görüntüsü, GÜNLÜK sekmesi)
    // Takip grafiğinin alt ekseni "10:50 · 22:25 · 10:00 · 21:35" gösteriyordu:
    // aralıklar eşitti ama SPAN 46 saatti — GÜNLÜK sekmesinde olmaması gereken
    // bir genişlik. Karşılaştır ekranı aynı sorunu göstermiyordu.
    //
    // ## Kök neden
    // `clipToPeriod` her seriyi KENDİ son veri noktasına çapalar. Tek seri için
    // doğru (hafta sonu son seansı korur), aynı grafikte üç seri için yıkıcı:
    //   · USDTRY=X 7/24 tikler        → penceresi "şimdi"de biter
    //   · BIST hissesi 18:00'de durur → penceresi seans kapanışında biter
    //   · portföy ızgarası            → son iş gününe çapalanır
    // Üç farklı pencere birleşince eksen 54 saate kadar çıkıyor ve hisse
    // grafiğin solundan 12 saat SONRA başlıyordu (ölçüldü).

    int ms(DateTime d) => d.millisecondsSinceEpoch;

    /// Hafta sonu senaryosu: forex tikliyor, borsa Cuma kapanmış.
    Map<String, Map<int, double>> haftaSonu() => {
          'USDTRY=X': {
            for (var i = 0; i <= 576; i++)
              ms(DateTime(2026, 9, 5, 21, 35)
                  .subtract(Duration(minutes: 5 * i))): 40.0 + i * 0.001,
          },
          'ALE': {
            for (var i = 0; i <= 200; i++)
              ms(DateTime(2026, 9, 4, 18).subtract(Duration(minutes: 5 * i))):
                  10.0 + i * 0.01,
          },
          WatchlistChart.portfolioSeriesKey: {
            for (var i = 0; i <= 48; i++)
              ms(DateTime(2026, 9, 4, 15).subtract(Duration(hours: i))):
                  1000.0 + i,
          },
        };

    ({int span, int seriSayisi, Set<int> bitisler}) olc(
        Map<String, Map<int, double>> h) {
      final tum = <int>[];
      final bitisler = <int>{};
      for (final s in h.values) {
        tum.addAll(s.keys);
        bitisler.add(s.keys.reduce((a, b) => a > b ? a : b));
      }
      tum.sort();
      return (
        span: tum.last - tum.first,
        seriSayisi: h.length,
        bitisler: bitisler,
      );
    }

    test('eksen SPANI dönemi aşmaz', () {
      // Asıl bulgu. Kırpma olmadan 54 saate çıkıyordu.
      final o = olc(ortakPencereyeHizala(haftaSonu(), 1));
      final saat = Duration(milliseconds: o.span).inHours;

      expect(saat, lessThanOrEqualTo(24),
          reason: 'GÜNLÜK ekseni $saat saat — "GÜNLÜK" etiketiyle iki günlük '
              'pencere gösteriliyor');
    });

    test('tüm seriler AYNI anda biter', () {
      // Kullanıcının "bitiş alanları sorunlu" bulgusu. Seriler farklı
      // anlarda bitiyorsa grafiğin sağ ucu basamaklı görünür.
      final o = olc(ortakPencereyeHizala(haftaSonu(), 1));

      expect(o.bitisler.length, 1,
          reason: 'seriler ${o.bitisler.length} farklı anda bitiyor — '
              'ortak pencere uygulanmamış');
    });

    test('hiçbir seri DÜŞMEZ', () {
      final o = olc(ortakPencereyeHizala(haftaSonu(), 1));

      expect(o.seriSayisi, 3,
          reason: 'başlangıçta üç seri vardı, ${o.seriSayisi} kaldı — '
              'pencere çapası bir seriyi tamamen dışarıda bırakıyor');
    });

    test('KAPANIŞ SONRASI tikleyen seri silinmez', () {
      // Bu hatayı bir kez YAPTIM: pencereyi en ERKEN son noktaya çapalamak,
      // kapanıştan sonra veri üreten serileri siliyordu. BIST 18:00'de
      // kapanıyor, USDTRY=X gece tiklemeye devam ediyor → USD'nin pencereye
      // giren nokta sayısı 1'e düşüyor ve seri düşürülüyordu.
      // Ölçüldü: üç serilik grafikte USDTRY=X tümüyle kayboldu.
      final h = ortakPencereyeHizala({
        'ALE': {
          for (var i = 0; i <= 96; i++)
            ms(DateTime(2026, 9, 4, 10).add(Duration(minutes: 5 * i))):
                10.0 + i * 0.001,
        },
        'USDTRY=X': {
          for (var i = 0; i <= 24; i++)
            ms(DateTime(2026, 9, 4, 20).subtract(Duration(minutes: 5 * i))):
                40.0,
        },
      }, 1);

      expect(h.keys, containsAll(<String>['ALE', 'USDTRY=X']),
          reason: 'kapanıştan sonra tikleyen seri grafikten silindi: '
              '${h.keys.toList()}');
    });

    test('tüm seriler AYNI anda BAŞLAR', () {
      // Kullanıcının ikinci turdaki bulgusu: "hâlâ başlangıç noktaları farklı
      // yerlerden başlıyor". Kırpma tek başına yetmiyordu — bir BIST hissesi
      // 10:00'da başlarken USDTRY=X gece boyunca tikliyor, hisse ekranın
      // %64'ünden sonra başlıyordu. Uçlar bilinen değerle DOLDURULUR.
      final h = ortakPencereyeHizala({
        'ALE': {
          for (var i = 0; i <= 96; i++)
            ms(DateTime(2026, 9, 4, 10).add(Duration(minutes: 5 * i))):
                10.0 + i * 0.001,
        },
        'USDTRY=X': {
          for (var i = 0; i <= 288; i++)
            ms(DateTime(2026, 9, 4, 20).subtract(Duration(minutes: 5 * i))):
                40.0,
        },
        WatchlistChart.portfolioSeriesKey: {
          for (var i = 0; i <= 24; i++)
            ms(DateTime(2026, 9, 4, 20).subtract(Duration(hours: i))): 1000.0,
        },
      }, 1);

      final baslar = <int>{};
      for (final s in h.values) {
        baslar.add(s.keys.reduce((a, b) => a < b ? a : b));
      }

      expect(baslar.length, 1,
          reason: 'seriler ${baslar.length} farklı noktadan başlıyor — '
              'grafikte kimi soldan kimi ortadan başlar');
    });

    test('doldurma SAHTE getiri üretmez', () {
      // Doldurma bir yalan söylememeli: seans öncesine ilk bilinen değer
      // yazılır, yani çizgi %0'dan düz başlar. Toplam getiri DEĞİŞMEZ.
      final ale = <int, double>{
        for (var i = 0; i <= 96; i++)
          ms(DateTime(2026, 9, 4, 10).add(Duration(minutes: 5 * i))):
              10.0 + i * (0.5 / 96),
      };
      final gercek = normalizeSeries(ale)!;

      final h = ortakPencereyeHizala({
        'ALE': ale,
        'USDTRY=X': {
          for (var i = 0; i <= 288; i++)
            ms(DateTime(2026, 9, 4, 20).subtract(Duration(minutes: 5 * i))):
                40.0,
        },
      }, 1);
      final hizali = normalizeSeries(h['ALE']!)!;

      expect(hizali.totalReturnPct, closeTo(gercek.totalReturnPct, 1e-9),
          reason: 'doldurma getiriyi değiştirdi: gerçek '
              '%${gercek.totalReturnPct} → %${hizali.totalReturnPct}');
    });

    test('pencere dışındaki noktalar atılır', () {
      final h = ortakPencereyeHizala(haftaSonu(), 1);
      final bas =
          h.values.expand((s) => s.keys).reduce((a, b) => a < b ? a : b);

      for (final e in h.entries) {
        for (final k in e.value.keys) {
          expect(k, greaterThanOrEqualTo(bas),
              reason: '${e.key} pencerenin solunda nokta taşıyor');
        }
      }
    });

    test('iki noktadan az kalan seri düşer', () {
      // `normalizeSeries` iki noktanın altında null döner; tek noktalı bir
      // seriyi taşımak grafikte çizilmeyen bir anahtar bırakırdı.
      final h = ortakPencereyeHizala({
        'UZUN': {
          for (var i = 0; i <= 48; i++)
            ms(DateTime(2026, 9, 4, 15).subtract(Duration(hours: i))): 100.0,
        },
        // Penceresi dolduran seriden ÇOK önce biten tek noktalı seri.
        'TEK': {ms(DateTime(2026, 9, 4, 15)): 50.0},
      }, 1);

      for (final e in h.entries) {
        expect(e.value.length, greaterThanOrEqualTo(2),
            reason: '${e.key} tek noktayla taşınıyor');
      }
    });

    test('boş girdi boş çıktı verir — çökmez', () {
      expect(ortakPencereyeHizala(const {}, 1), isEmpty);
      expect(ortakPencereyeHizala({'A': const {}}, 1), isEmpty);
    });

    test('normalize KIRPMADAN SONRA yapılır', () async {
      // Sıra değişmezi: yüzde tabanı serinin ilk noktasıdır. Önce normalize
      // edilseydi her seri kendi penceresinin başına göre ölçülür, ortak
      // pencereye kırpma da tabanı düzeltmezdi — kıyas anlamsızlaşırdı.
      final src =
          await File('lib/providers/watchlist_provider.dart').readAsString();
      final hizala = src.indexOf('ortakPencereyeHizala(ham, days)');
      final normalize = src.indexOf('normalizeSeries(e.value)');

      expect(hizala, greaterThan(0));
      expect(normalize, greaterThan(hizala),
          reason: 'normalize, hizalamadan ÖNCE çağrılıyor');
    });
  });

  group('SERVİSİN KENDİ ÇIKTISI — gerçek çağrı', () {
    // Yukarıdaki testler cebri denetler; bunlar `getPortfolioHistory`'yi
    // GERÇEKTEN çağırır. Ayrım önemli: ilk yazımda tüm testler grid'i yerel
    // olarak yeniden kuruyordu ve hafta sonu çapası sabote edildiğinde HÂLÂ
    // geçiyorlardı — üretim kodunun çağrı yerine hiç dokunmuyorlardı.
    //
    // Ağ yok: `isManualPrice` + çözülemeyen ticker → servis `currentPrice`'a
    // düşer (`_flatFallback`), seri deterministik olur.
    Asset lot(DateTime added) => Asset(
          id: 'a1',
          userId: 'u1',
          name: 'ZZZTEST',
          ticker: 'ZZZTESTSYM',
          type: AssetType.hisse,
          quantity: 10,
          purchasePrice: 100,
          currency: 'TRY',
          notes: '',
          isManualPrice: true,
          purchaseFxRate: 1.0,
          currentPrice: 100,
          addedDate: added,
          kind: AssetKind.buy,
        );

    test('GÜNLÜK seri her gün çizilebilir — hafta sonu dahil', () async {
      // Ölçülmüş hata: Pazar günü grid tamamen boşalıyor ve portföy çizgisi
      // grafikten kayboluyordu. `normalizeSeries` iki noktanın altında null
      // döner, yani "1 nokta" da "çizgi yok" demektir.
      //
      // Bu test bugünün hangi gün olduğuna bağlıdır — hafta sonu koşulduğunda
      // asıl regresyonu yakalar. Hafta içi koşulduğunda da anlamlı: serinin
      // pencereyi doldurduğunu doğrular.
      final seri = await HistoryService.instance.getPortfolioHistory(
          [lot(DateTime.now().subtract(const Duration(days: 90)))], 1);

      expect(seri.length, greaterThanOrEqualTo(2),
          reason: 'GÜNLÜK portföy serisi çizilemiyor (bugün '
              '${DateTime.now().weekday}. gün) — normalizeSeries null döner '
              've kıyas çizgisi grafikten kaybolur');
    });

    test('dönen seri seçilen dönemi AŞMAZ', () async {
      // Kırpmanın gerçekten uygulandığını servisin çıktısından doğrular.
      // Kırpma kaldırılırsa GÜNLÜK'te beş günlük seri döner ve portföy
      // çizgisi izlenen varlıkların soluna taşar.
      final seri = await HistoryService.instance.getPortfolioHistory(
          [lot(DateTime.now().subtract(const Duration(days: 90)))], 1);

      final ts = seri.keys.toList()..sort();
      final genislik = Duration(milliseconds: ts.last - ts.first);

      expect(genislik.inHours, lessThanOrEqualTo(24),
          reason:
              'GÜNLÜK penceresi ${genislik.inHours} saat — bir günü aşıyor');
    });

    test('portföy ve sembol AYNI range i çeker', () async {
      // En kritik değişmez ve tek gerçek koruma: iki merdiven ayrışırsa iki
      // seri farklı pencereden gelir ve grafik hizasız çizilir.
      //
      // `debugSonKullanilanRange` olmadan bu sabote edilebiliyordu: `range`
      // yerel bir değişken, ağa çıkmayan test onu göremiyordu.
      for (final p in watchlistPeriods) {
        await HistoryService.instance.getPortfolioHistory(
          [lot(DateTime.now().subtract(const Duration(days: 400)))],
          p.days,
        );

        expect(HistoryService.debugSonKullanilanRange,
            HistoryService.rangeForPeriod(p.days),
            reason: '${p.label}: portföy '
                '"${HistoryService.debugSonKullanilanRange}" çekiyor, '
                'sembol "${HistoryService.rangeForPeriod(p.days)}" — '
                'iki seri farklı pencereden gelir');
      }
    });

    test('GÜNLÜK portföy serisi PERFORMANS ekranıyla AYNI', () async {
      // Kullanıcı bulgusu: "portföyüm performans ekranında günlük grafikte
      // nasıl gözüküyorsa o şekilde gözükmeli, sıklığı vs."
      //
      // Ölçülen fark: takip listesi `getPortfolioHistory(_, 1)` ile SAATLİK
      // ızgara (60 dk slot, 25 nokta) çiziyordu; performans ekranı ise
      // `getPortfolioHistoryHourlyBreakdown(_, 24)` ile 5 DAKİKALIK
      // çözünürlük. Aynı portföyün aynı günü iki ekranda iki farklı
      // sıklıkta görünüyordu.
      //
      // İzlenen varlıklar GÜNLÜK'te zaten `ResolutionTier.fiveMin`; kaba olan
      // yalnızca kıyas çizgisiydi.
      final lotlar = [lot(DateTime.now().subtract(const Duration(days: 90)))];

      final performans = (await HistoryService.instance
              .getPortfolioHistoryHourlyBreakdown(lotlar, 24))
          .total;
      final takip =
          await HistoryService.instance.getPortfolioHistoryHourly(lotlar, 24);

      expect(takip.keys.toSet(), performans.keys.toSet(),
          reason: 'iki ekran aynı günü farklı ızgarada çiziyor');

      // Çözünürlük gerçekten 5 dakika mı?
      final ts = takip.keys.toList()..sort();
      if (ts.length > 1) {
        final araliklar = <int>{
          for (var i = 1; i < ts.length; i++)
            Duration(milliseconds: ts[i] - ts[i - 1]).inMinutes,
        };
        expect(araliklar, everyElement(lessThanOrEqualTo(5)),
            reason: 'slot aralıkları $araliklar — 5 dakikalık olmalı');
      }
    });

    test('sağlayıcı GÜNLÜK te gün içi servisini KULLANIR', () async {
      // Cebir doğru olsa da provider hâlâ saatlik yolu çağırıyorsa düzeltme
      // kullanıcıya ulaşmaz.
      final src =
          await File('lib/providers/watchlist_provider.dart').readAsString();

      expect(src.contains('getPortfolioHistoryHourly('), isTrue,
          reason: 'GÜNLÜK sekmesi performans ekranıyla aynı motoru '
              'kullanmalı');
      expect(src.contains('days <= 1'), isTrue,
          reason: 'gün içi dalı dönem koşuluyla ayrılmalı');
    });

    test('1A serisi de dönemi aşmaz', () async {
      final seri = await HistoryService.instance.getPortfolioHistory(
          [lot(DateTime.now().subtract(const Duration(days: 400)))], 30);

      final ts = seri.keys.toList()..sort();
      final genislik = Duration(milliseconds: ts.last - ts.first);

      expect(genislik.inDays, lessThanOrEqualTo(30),
          reason: '1A penceresi ${genislik.inDays} gün');
    });
  });
}
