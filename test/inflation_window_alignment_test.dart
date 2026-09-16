import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/inflation_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';

/// TÜFE ve nominal getiri AYNI pencereyi ölçmek zorundadır (2026-09-16).
///
/// Ölçülen arıza: TÜFE penceresi son açıklanmış aydan geriye sayılıyordu
/// (doğrusu bu), nominal getiri ise BUGÜNDEN (`donemBaslangici(now, 12)`).
/// İkisi "nominal − TÜFE" diye çıkarılıyordu ama farklı aralıklara aitti:
///
///   · 1Y → ~1,5 ay kayma,
///   · 1A → pencereler HİÇ KESİŞMİYOR (portföyün 16 Ağustos–16 Eylül
///     getirisi, Temmuz ayının enflasyonuyla kıyaslanıyordu).
///
/// Fark, ölçülmemiş bir aralığın getirisini içeriyordu. Bu dosya pencerenin
/// tek kaynaktan geldiğini ve uçların TÜFE'ye hizalı olduğunu kilitler.
void main() {
  DateTime ay(int y, int m) => DateTime(y, m, 1);

  setUp(() => InflationService.instance.resetForTest());
  tearDown(() => InflationService.instance.resetForTest());

  group('InflationService.pencere uçları', () {
    test('1Y: uçlar son açıklanmış aydan tam 12 ay geriye', () async {
      InflationService.instance.seedForTest({
        ay(2025, 8): 100.0,
        ay(2025, 9): 103.0,
        ay(2026, 8): 131.51,
      });
      final w = await InflationService.instance
          .pencere(365, now: DateTime(2026, 9, 16));

      expect(w, isNotNull);
      expect(w!.ilkAy, ay(2025, 8));
      expect(w.sonAy, ay(2026, 8));
      expect(w.ayAdedi, 12);
      expect(w.pct, closeTo(31.51, 1e-9));
    });

    test('seri uçları AY SONLARIDIR — ayın 1\'i değil', () async {
      // Endeks bir ayın ÖLÇÜMÜ, ortalaması değil. TÜİK "Ağustos → Ağustos"
      // derken iki ölçüm noktasını kıyaslıyor; portföy de aynı iki noktada
      // değerlenmeli. Ayın 1'ini almak pencereyi bir ay uzatır ve farkı
      // sistematik olarak bozardı.
      InflationService.instance.seedForTest({
        ay(2025, 8): 100.0,
        ay(2026, 8): 130.0,
      });
      final w = await InflationService.instance
          .pencere(365, now: DateTime(2026, 9, 16));

      expect(w!.seriBaslangici, DateTime(2025, 8, 31));
      expect(w.seriBitisi, DateTime(2026, 8, 31));
    });

    test('1A: pencere son açıklanmış AYIN kendisi', () async {
      // Arızanın en kötü hâli: nominal 16 Ağustos–16 Eylül'ü ölçerken TÜFE
      // Temmuz'u ölçüyordu — sıfır örtüşme.
      InflationService.instance.seedForTest({
        ay(2026, 7): 100.0,
        ay(2026, 8): 102.5,
      });
      final w = await InflationService.instance
          .pencere(30, now: DateTime(2026, 9, 16));

      expect(w!.ayAdedi, 1);
      expect(w.seriBaslangici, DateTime(2026, 7, 31));
      expect(w.seriBitisi, DateTime(2026, 8, 31));
      expect(w.pct, closeTo(2.5, 1e-9));
    });

    test('6A: tam altı ay', () async {
      InflationService.instance.seedForTest({
        ay(2026, 2): 100.0,
        ay(2026, 8): 115.0,
      });
      final w = await InflationService.instance
          .pencere(180, now: DateTime(2026, 9, 16));
      expect(w!.ayAdedi, 6);
      expect(w.pct, closeTo(15.0, 1e-9));
    });

    test('bayat seride null — hizalanacak pencere yok', () async {
      InflationService.instance.seedForTest({
        ay(2025, 1): 100.0,
        ay(2026, 1): 130.0,
      });
      final w = await InflationService.instance
          .pencere(365, now: DateTime(2026, 9, 16));
      expect(w, isNull);
    });

    test('boş tabloda null', () async {
      InflationService.instance.seedForTest(const {});
      expect(await InflationService.instance.pencere(365), isNull);
    });

    test('inflationForPeriod pencere ile AYNI yüzdeyi verir', () async {
      // İki API tek hesaptan beslenmeli; ayrışırlarsa çağıranlar yine iki
      // farklı sayı görür — bu dosyanın kapattığı arızanın ta kendisi.
      InflationService.instance.seedForTest({
        ay(2025, 8): 100.0,
        ay(2026, 8): 131.51,
      });
      final now = DateTime(2026, 9, 16);
      final a = await InflationService.instance.inflationForPeriod(365, now: now);
      final b = await InflationService.instance.pencere(365, now: now);
      expect(a, b!.pct);
    });
  });

  group('uçtan uca: fark ölçülmemiş aralık İÇERMEZ', () {
    test('hizalı hesap ile hizasız hesap FARKLI sonuç verir', () {
      // Arızanın sayısal kanıtı. Portföy son 13 ayda düzgün büyüyor;
      // aynı portföy iki farklı pencerede ölçülünce iki farklı nominal
      // çıkıyor ve TÜFE sabit olduğu için "kaç puan önde" de değişiyor.
      //
      // Değerler: her ay sonu +%2 büyüme.
      final seri = <int, double>{};
      var deger = 1000.0;
      for (var i = 0; i < 14; i++) {
        final t = DateTime(2025, 7 + i + 1, 0); // ay sonları
        seri[t.millisecondsSinceEpoch] = deger;
        deger *= 1.02;
      }
      final bd = PortfolioHistoryBreakdown(
        total: seri,
        byType: const {},
        byPosition: const {},
        positionType: const {},
      );

      // Hizalı: Ağustos 2025 sonu → Ağustos 2026 sonu (TÜFE penceresi).
      final hizali = PeriodSummaryService.compute(
        period: SummaryPeriod.birYil,
        assets: const [],
        breakdown: bd,
        now: DateTime(2026, 8, 31),
        pencereBaslangici: DateTime(2025, 8, 31),
      ).getiriPct;

      // Hizasız (eski davranış): bugünden 12 ay geriye, 16 Eylül'e kadar.
      final hizasiz = PeriodSummaryService.compute(
        period: SummaryPeriod.birYil,
        assets: const [],
        breakdown: bd,
        now: DateTime(2026, 9, 16),
      ).getiriPct;

      expect(hizali, isNotNull);
      expect(hizasiz, isNotNull);
      // İki sayı AYRIŞIYOR: eski kod bu farkı TÜFE'den çıkarıyordu.
      expect((hizali! - hizasiz!).abs(), greaterThan(1.0),
          reason: 'pencere kayması ölçülebilir bir sapma üretiyor — '
              'düzeltmenin gerekçesi bu');
      // Hizalı hesap tam 12 ayın bileşiği: 1,02^12 − 1 ≈ %26,82.
      expect(hizali, closeTo(26.824, 0.01));
    });
  });

  group('PeriodSummaryService.compute pencereBaslangici', () {
    test('verilen başlangıç takvimden türetileni EZER', () {
      // Hizalamanın mekanizması: `now`'ı oynatmak yetmez çünkü `pencere()`
      // başlangıcı `now`'dan türetiyor. Dışarıdan uç geçirilebilmeli.
      final bd = PortfolioHistoryBreakdown(
        total: {
          DateTime(2025, 8, 31).millisecondsSinceEpoch: 1000.0,
          DateTime(2026, 8, 31).millisecondsSinceEpoch: 1200.0,
        },
        byType: const {},
        byPosition: const {},
        positionType: const {},
      );

      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birYil,
        assets: const [],
        breakdown: bd,
        now: DateTime(2026, 8, 31),
        pencereBaslangici: DateTime(2025, 8, 31),
      );

      expect(s.start, DateTime(2025, 8, 31));
      expect(s.baslangicTRY, 1000.0);
      expect(s.sonTRY, 1200.0);
      expect(s.getiriPct, closeTo(20.0, 1e-9));
    });
  });
}
