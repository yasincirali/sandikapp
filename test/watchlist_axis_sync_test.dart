import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/services/history_service.dart';

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
