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

    // Performans: satır başına sabit iş, tek sıralama. 2000 hareket bir
    // kare bütçesinin (16 ms) çok altında kurulur.
    test('2000 hareket bir karenin altında', () {
      final lots = [
        for (var i = 0; i < 2000; i++)
          _lot('l$i', 1, DateTime(2026, 1, 1).add(Duration(hours: i))),
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
      // En iyi 5 koşu: paralel test yükü tek ölçümü şişirebilir; ölçülen
      // şey algoritmanın maliyeti, makinenin o anki yükü değil.
      var enIyi = 1 << 30;
      late Map<String, ({double once, double sonra})> m;
      for (var i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        m = kos();
        sw.stop();
        if (sw.elapsedMicroseconds < enIyi) enIyi = sw.elapsedMicroseconds;
      }
      expect(m.length, 2000);
      expect(enIyi, lessThan(16000), reason: '$enIyi µs');
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
}

class _Portfoy extends PortfolioNotifier {
  _Portfoy(this.lotlar);
  final List<Asset> lotlar;
  @override
  Future<PortfolioState> build() async => PortfolioState(assets: lotlar);
}
