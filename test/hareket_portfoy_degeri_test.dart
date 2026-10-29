import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/gorunum_kapsami.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/hareket_portfoy_degeri_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/utils/tr_format.dart' show dayKey;

/// Hareket satırının "Portföy önce → sonra" değeri (yasin, 2026-10-29:
/// "alım satım öncesi ve sonrası toplam bakiyeleri görelim … tutarsızlık
/// olmamalı, performansı da çöz"). Sözleşme `hareketPortfoyDegerleri`
/// belge yorumunda: "sonra" = Performans serisinin işlemi İÇEREN ilk
/// noktası (bugünse canlı uç), aynı noktaya düşen işlemler zincirlenir.
Asset _lot(
  String id,
  double qty,
  DateTime tarih, {
  AssetKind kind = AssetKind.buy,
  double alis = 100,
  double? satis = 120,
  String currency = 'TRY',
  String ticker = 'THYAO.IS',
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: alis,
      sellPrice: satis,
      currency: currency,
      notes: '',
      isManualPrice: false,
      currentPrice: 110,
      addedDate: tarih,
      kind: kind,
    );

double _tl(double v, String c) => c == 'USD' ? v * 40 : v;

int _gun(DateTime d) => dayKey(d).millisecondsSinceEpoch;

void main() {
  final simdi = DateTime(2026, 3, 20, 15);

  group('saf fonksiyon', () {
    test('gün içi işlem ertesi günün noktasına düşer; zincir', () {
      final alim = _lot('a1', 10, DateTime(2026, 3, 10, 10), alis: 50);
      final satim = _lot('s1', 4, DateTime(2026, 3, 10, 15),
          kind: AssetKind.sell, satis: 60);
      final seri = {
        _gun(DateTime(2026, 3, 10)): 1000.0, // işlemleri İÇERMEZ
        _gun(DateTime(2026, 3, 11)): 5000.0,
      };
      final m = hareketPortfoyDegerleri(
        seriGirdisi: [alim, satim],
        gunlukSeri: seri,
        canliToplam: 9999,
        simdi: simdi,
        toTRY: _tl,
      );
      // Son işlem (satış) noktanın değerini alır; önce = sonra + satış.
      expect(m['s1'], (once: 5240.0, sonra: 5000.0));
      // Bir önceki işlemin "sonra"sı, sonrakinin "önce"si.
      expect(m['a1']!.sonra, m['s1']!.once);
      expect(m['a1']!.once, 5240.0 - 500.0);
    });

    test('saatsiz (gece yarısı) kayıt kendi gününün noktasına düşer', () {
      final m = hareketPortfoyDegerleri(
        seriGirdisi: [_lot('a1', 10, DateTime(2026, 3, 10))],
        gunlukSeri: {_gun(DateTime(2026, 3, 10)): 3000.0},
        canliToplam: null,
        simdi: simdi,
        toTRY: _tl,
      );
      expect(m['a1'], (once: 2000.0, sonra: 3000.0));
    });

    test('dün geceden sonraki işlemler canlı uca bağlanır', () {
      final m = hareketPortfoyDegerleri(
        seriGirdisi: [
          _lot('dun', 1, DateTime(2026, 3, 19, 11)), // S = bugün
          _lot('bugun', 2, DateTime(2026, 3, 20, 10)), // S = yarın
        ],
        gunlukSeri: {_gun(DateTime(2026, 3, 20)): 1.0},
        canliToplam: 10000,
        simdi: simdi,
        toTRY: _tl,
      );
      expect(m['bugun'], (once: 9800.0, sonra: 10000.0));
      expect(m['dun'], (once: 9700.0, sonra: 9800.0));
    });

    test('nokta yoksa değer yok; canlı uç bilinmiyorsa değer yok', () {
      final m = hareketPortfoyDegerleri(
        seriGirdisi: [
          _lot('eski', 1, DateTime(2025, 1, 1, 12)),
          _lot('bugun', 1, DateTime(2026, 3, 20, 10)),
        ],
        gunlukSeri: const {},
        canliToplam: null,
        simdi: simdi,
        toTRY: _tl,
      );
      expect(m, isEmpty);
    });

    test('satış fiyatı bilinmiyorsa zincir orada kopar', () {
      final m = hareketPortfoyDegerleri(
        seriGirdisi: [
          _lot('a1', 10, DateTime(2026, 3, 10, 9)),
          _lot('s1', 2, DateTime(2026, 3, 10, 10),
              kind: AssetKind.sell, satis: null),
          _lot('a2', 1, DateTime(2026, 3, 10, 11)),
        ],
        gunlukSeri: {_gun(DateTime(2026, 3, 11)): 5000.0},
        canliToplam: null,
        simdi: simdi,
        toTRY: _tl,
      );
      expect(m['a2'], (once: 4900.0, sonra: 5000.0));
      expect(m.containsKey('s1'), isFalse);
      expect(m.containsKey('a1'), isFalse);
    });

    test('USD tutar satır tutarı gibi TRY\'ye çevrilir', () {
      final m = hareketPortfoyDegerleri(
        seriGirdisi: [
          _lot('a1', 2, DateTime(2026, 3, 10, 10), alis: 100, currency: 'USD'),
        ],
        gunlukSeri: {_gun(DateTime(2026, 3, 11)): 50000.0},
        canliToplam: null,
        simdi: simdi,
        toTRY: _tl,
      );
      expect(m['a1'], (once: 50000.0 - 8000.0, sonra: 50000.0));
    });

    test('temettü, silinmiş lot zincire girmez', () {
      final m = hareketPortfoyDegerleri(
        seriGirdisi: [
          _lot('a1', 10, DateTime(2026, 3, 10, 9)),
          _lot('t1', 0, DateTime(2026, 3, 10, 10), kind: AssetKind.dividend),
        ],
        gunlukSeri: {_gun(DateTime(2026, 3, 11)): 5000.0},
        canliToplam: null,
        simdi: simdi,
        toTRY: _tl,
      );
      expect(m.keys, ['a1']);
      expect(m['a1']!.sonra, 5000.0);
    });

    // Performans: satır başına sabit iş, tek sıralama. Duvar saati paralel
    // test yükünde şişiyor (CI'da 16 ms eşiği 17 ms'yle kırıldı); ölçülen
    // şey algoritmanın BÜYÜMESİ: 4 kat hareket ~4 kat süre (n log n), n²
    // olsaydı ~16 kat. Mutlak üst sınır gevşek bir emniyet: hesap kare
    // içinde değil, ilk kareden sonra ve yalnız defter değişince koşar.
    int enIyiSure(int n) {
      final lots = [
        for (var i = 0; i < n; i++)
          _lot('l$i', 1, DateTime(2026, 1, 1).add(Duration(minutes: i * 30))),
      ];
      final seri = {
        for (var d = 0; d < 90; d++)
          _gun(DateTime(2026, 1, 1 + d)): 1e6 + d,
      };
      Map<String, ({double once, double sonra})> kos() =>
          hareketPortfoyDegerleri(
            seriGirdisi: lots,
            gunlukSeri: seri,
            canliToplam: 1e6,
            simdi: simdi,
            toTRY: _tl,
          );
      kos(); // ısınma (JIT)
      var enIyi = 1 << 30;
      for (var i = 0; i < 7; i++) {
        final sw = Stopwatch()..start();
        final m = kos();
        sw.stop();
        expect(m.length, n);
        if (sw.elapsedMicroseconds < enIyi) enIyi = sw.elapsedMicroseconds;
      }
      return enIyi;
    }

    test('hareket sayısıyla doğrusala yakın büyür (n² değil)', () {
      final kucuk = enIyiSure(1000);
      final buyuk = enIyiSure(4000);
      expect(buyuk, lessThan(kucuk * 8 + 2000),
          reason: '1000: $kucuk µs, 4000: $buyuk µs');
      expect(buyuk, lessThan(250000), reason: '4000 hareket: $buyuk µs');
    });
  });

  // Tutarlılık: satırın "sonra"sı Performans'ın çizdiği sayının KENDİSİ.
  // Beklenen değer ayrı bir yoldan yeniden hesaplanmaz; Performans'ın
  // çağırdığı motor, Performans'ın kurduğu girdiyle (`performansSeriDefterleri`)
  // ve Performans'ın kendi penceresiyle (1A, ilk alımdan bugüne) çağrılır.
  group('Performans ile tutarlılık', () {
    setUpAll(() => DbLogger.silentInTests = true);
    tearDownAll(() => DbLogger.silentInTests = false);
    tearDown(() {
      HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
      HistoryService.clearCache();
    });

    test('sonra == seri noktası, önce(n) == sonra(n−1), bugün == canlı uç',
        () async {
      final now = DateTime.now();
      final g = dayKey(now);
      HistoryService.clearCache();
      HistoryService.seriCekici = (sym, range, interval) async => [
            for (var d = 400; d >= 0; d--)
              (
                g.subtract(Duration(days: d)).add(const Duration(hours: 10))
                    .millisecondsSinceEpoch,
                50.0 + (400 - d) * 0.25,
              ),
          ];
      final d10 = g.subtract(const Duration(days: 10));
      final lots = [
        _lot('a1', 100, d10.add(const Duration(hours: 10)), alis: 50),
        _lot('s1', 30, d10.add(const Duration(hours: 15)),
            kind: AssetKind.sell, satis: 55),
        _lot('a2', 20, g.subtract(const Duration(days: 7)), alis: 60),
        _lot('a3', 5, now.subtract(const Duration(minutes: 1)), alis: 70),
      ];
      final c = ProviderContainer(overrides: [
        portfolioProvider.overrideWith(() => _Portfoy(lots)),
      ]);
      addTearDown(c.dispose);
      await c.read(portfolioProvider.future);
      const k = (kisi: '', portfoy: PortfoySecimi.tumu);
      final abone = c.listen(hareketPortfoyDegerleriProvider(k), (_, __) {});
      addTearDown(abone.close);
      // Seri gelmeden liste boş harita okur (miktarlar çizilir).
      expect(abone.read(), isEmpty);
      await c.read(hareketGunlukSeriProvider(k).future);
      final m = abone.read();

      // Performans'ın çağrısı (1A, ilk alım gününden bugüne, günlük katman).
      final defterler = performansSeriDefterleri([lots]);
      final perf = await HistoryService.instance
          .getPortfolioHistoryAtResolution(
        assets: [for (final l in defterler) ...l],
        from: d10,
        to: DateTime.now(),
        tier: ResolutionTier.daily,
      );
      final d11 = _gun(d10.add(const Duration(days: 1)));
      expect(perf[d11], isNotNull);
      expect(m['s1']!.sonra, perf[d11]);
      expect(m['a1']!.sonra, m['s1']!.once);
      expect(m['a2']!.sonra, perf[_gun(g.subtract(const Duration(days: 7)))]);
      // Canlı uç: Performans `_buildChartWithData`'nın `currentTotalOverride`
      // hesabı.
      final canli = ownerScopedTotalValue(defterler,
          sonFiyat: PriceService.instance.sonBilinenFiyat);
      expect(m['a3']!.sonra, canli);
      expect(m['a3']!.once, canli - 5 * 70);
    });
  });

  // E2E (2026-10-29): Performans geçmişi canlı kura/altına hizalayarak
  // yeniden hesaplarken satırlar defter değişimini bekliyordu; dakikalar
  // sonra ₺931.267 / ₺931.288. Kilit: (1) canlı kotasyon değişince satır,
  // Performans'ın o an çağırdığı motorun sayısına yeniden eşitlenir;
  // (2) Performans günlük seriyi yayınladıysa satır o ÖRNEĞİ okur.
  group('canlı kotasyon ve Performans yayını', () {
    final eskiKur = HistoryService.canliKur;
    final eskiAralik = HareketGunlukSeriNotifier.tazelemeAraligi;
    setUpAll(() => DbLogger.silentInTests = true);
    tearDownAll(() => DbLogger.silentInTests = false);
    tearDown(() {
      HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
      HistoryService.canliKur = eskiKur;
      HareketGunlukSeriNotifier.tazelemeAraligi = eskiAralik;
      PerformansSeriYayini.instance.temizle();
      HistoryService.clearCache();
    });

    Future<
        ({
          ProviderContainer c,
          ProviderSubscription<Map<String, ({double once, double sonra})>> abone,
          List<Asset> lots,
          DateTime d10,
        })> kur(void Function(double) kurAyarla) async {
      final g = dayKey(DateTime.now());
      HistoryService.clearCache();
      HistoryService.seriCekici = (sym, range, interval) async => [
            for (var d = 400; d >= 0; d--)
              (
                g.subtract(Duration(days: d)).add(const Duration(hours: 10))
                    .millisecondsSinceEpoch,
                sym.contains('USD') ? 40.0 : 10.0 + (400 - d) * 0.01,
              ),
          ];
      kurAyarla(40);
      final d10 = g.subtract(const Duration(days: 10));
      final lots = [
        _lot('a1', 10, d10.add(const Duration(hours: 10)),
            alis: 10, currency: 'USD', ticker: 'AAPL'),
      ];
      final c = ProviderContainer(overrides: [
        portfolioProvider.overrideWith(() => _Portfoy(lots, usdTry: 40)),
      ]);
      await c.read(portfolioProvider.future);
      final abone = c.listen(
          hareketPortfoyDegerleriProvider(
              hareketKapsami(kisi: '', portfoy: PortfoySecimi.tumu)),
          (_, __) {});
      await c.read(hareketGunlukSeriProvider(
              hareketKapsami(kisi: '', portfoy: PortfoySecimi.tumu))
          .future);
      return (c: c, abone: abone, lots: lots, d10: d10);
    }

    Future<Map<int, double>> performans(List<Asset> lots, DateTime from) =>
        HistoryService.instance.getPortfolioHistoryAtResolution(
          assets: [for (final l in performansSeriDefterleri([lots])) ...l],
          from: from,
          to: DateTime.now(),
          tier: ResolutionTier.daily,
        );

    test('canlı kur değişince satır yeniden Performans sayısına eşit',
        () async {
      var kurDegeri = 40.0;
      HistoryService.canliKur = () => kurDegeri;
      HareketGunlukSeriNotifier.tazelemeAraligi = Duration.zero;
      final t = await kur((v) => kurDegeri = v);
      addTearDown(t.c.dispose);
      final s = _gun(t.d10.add(const Duration(days: 1)));
      final ilk = t.abone.read()['a1']!.sonra;
      expect(ilk, (await performans(t.lots, t.d10))[s]);

      // Fiyat turu: canlı kur %1 oynadı, portföy durumu tazelendi.
      kurDegeri = 40.4;
      (t.c.read(portfolioProvider.notifier) as _Portfoy).kurGuncelle(40.4);
      final beklenen = (await performans(t.lots, t.d10))[s];
      expect(beklenen, isNot(ilk), reason: 'hizalama sayıyı değiştirmeli');
      for (var i = 0; i < 100; i++) {
        if (t.abone.read()['a1']?.sonra == beklenen) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(t.abone.read()['a1']!.sonra, beklenen);
    });

    test('Performans yayınladıysa satır o örneği okur', () async {
      final t = await kur((_) {});
      addTearDown(t.c.dispose);
      final s = _gun(t.d10.add(const Duration(days: 1)));
      PerformansSeriYayini.instance.yayinla(
          hareketKapsami(kisi: '', portfoy: PortfoySecimi.tumu),
          {s: 123456.0});
      await Future<void>.delayed(Duration.zero);
      expect(t.abone.read()['a1']!.sonra, 123456.0);
      // Yayın çekilince kendi serisine döner.
      PerformansSeriYayini.instance.yayinla(
          hareketKapsami(kisi: '', portfoy: PortfoySecimi.tumu), null);
      await Future<void>.delayed(Duration.zero);
      expect(t.abone.read()['a1']!.sonra, isNot(123456.0));
    });
  });
}

class _Portfoy extends PortfolioNotifier {
  _Portfoy(this.lotlar, {this.usdTry = 1.0});
  final List<Asset> lotlar;
  final double usdTry;
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: lotlar, usdTry: usdTry);

  /// Fiyat turu: aynı defter, yeni nesneler ve yeni kur.
  void kurGuncelle(double kur) => state = AsyncData(PortfolioState(
      assets: List.of(lotlar), usdTry: kur));
}
