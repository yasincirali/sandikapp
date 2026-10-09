import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart' show positionKey;
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/daily_summary.dart'
    show IntradaySeriesCache;
import 'package:portfoy_takip/services/en_cok_oynayan.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/live_activity_service.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';

/// Kilit ekranının "günü sürükleyen" satırı (goz_alici madde 4, kullanıcı
/// seçimi 2026-10-09 "Yalnız izin verene").
///
/// Kilitlenen üç şey:
///   * seçim |TRY katkısı| ile (Bugün kartı |yüzde| ile seçer),
///   * metinler sunucuyla aynı (`supabase/tests/kilit_surukleyen_test.ts`
///     aynı vektörleri koşar),
///   * gizlilik kapısı: bayrak + "Tutarları göster" + bakiye görünür; biri
///     eksikse satırın hiçbir alanı dolu gitmez.

Asset _lot(String id, String ticker, double qty, double fiyat,
        {String currency = 'TRY'}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: fiyat,
      currency: currency,
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 1, 1),
      kind: AssetKind.buy,
    );

final _gun = () {
  var d = DateTime.now();
  if (d.weekday == DateTime.saturday) {
    d = d.subtract(const Duration(days: 1));
  } else if (d.weekday == DateTime.sunday) {
    d = d.subtract(const Duration(days: 2));
  }
  return DateTime(d.year, d.month, d.day);
}();
final _seans = _gun.add(const Duration(hours: 14, minutes: 30));
int _ms(int saat, [int dk = 0]) =>
    _gun.add(Duration(hours: saat, minutes: dk)).millisecondsSinceEpoch;

class _Kanal {
  final calls = <Map<String, Object?>>[];
  static const _c = MethodChannel('com.sandik.app/live_activity');
  void kur() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_c, (call) async {
        if (call.method == 'isSupported') return true;
        calls.add(((call.arguments as Map?) ?? {}).cast<String, Object?>());
        return true;
      });
  void kaldir() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_c, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('metinler (sunucuyla aynı vektörler)', () {
    test('artış: işaretsiz yüzde, işaretli tam lira', () {
      final m = KilitSurukleyen.surukleyenMetinleri(50000, 51910)!;
      expect(m.pctText, '%3,82');
      expect(m.tutarText, '+₺1.910');
      expect(m.pozitif, isTrue);
    });

    test('düşüş', () {
      final m = KilitSurukleyen.surukleyenMetinleri(12000, 11543.4)!;
      expect(m.pctText, '%3,81');
      expect(m.tutarText, '-₺457');
      expect(m.pozitif, isFalse);
    });

    test('yuvarlanınca sıfır ya da tabansız değişim satır üretmez', () {
      expect(KilitSurukleyen.surukleyenMetinleri(100000, 100004), isNull);
      expect(KilitSurukleyen.surukleyenMetinleri(0, 500), isNull);
    });
  });

  group('seçim', () {
    final kucuk = _lot('k', 'KUCUK.IS', 10, 11); // 100 → 110: %10, +₺10
    final buyuk = _lot('b', 'BUYUK.IS', 100, 102); // 10.000 → 10.200: %2, +₺200
    final bd = PortfolioHistoryBreakdown(
      total: const {},
      byType: const {},
      byPosition: {
        positionKey(kucuk): {_ms(10): 100, _ms(14): 110},
        positionKey(buyuk): {_ms(10): 10000, _ms(14): 10200},
      },
      positionType: {
        positionKey(kucuk): AssetType.hisse,
        positionKey(buyuk): AssetType.hisse,
      },
      seansGunu: _gun,
    );

    test('Bugün kartı yüzdeyle, kilit ekranı tutarla seçer', () {
      expect(enCokOynayanBul(bd, lotlar: [kucuk, buyuk], now: _seans)!
          .positionKey, positionKey(kucuk));
      final s = gununSurukleyeni(bd, lotlar: [kucuk, buyuk], now: _seans)!;
      expect(s.positionKey, positionKey(buyuk));
      expect(s.acilisTRY, 10000);
    });

    test('ad kısa kod, değer canlı; tarifteki parçanın sırası bulunur', () {
      final state = PortfolioState(assets: [kucuk, buyuk], usdTry: 42);
      final s = KilitSurukleyen.kur(
        state: state,
        kume: [kucuk, buyuk],
        breakdown: bd,
        now: _seans,
        parcalar: const [
          {'s': 'KUCUK.IS', 'd': 110.0, 'p': 11.0},
          {'s': 'BUYUK.IS', 'd': 10200.0, 'p': 102.0},
        ],
      )!;
      expect(s.ad, 'BUYUK');
      expect(s.a0, 10000);
      expect(s.v, closeTo(10200, 1e-9));
      expect(s.i, 1);
      expect(s.tarif(), {'ad': 'BUYUK', 'a0': 10000.0, 'v': 10200.0, 'i': 1});
    });
  });

  group('gizlilik kapısı (sync)', () {
    late _Kanal kanal;
    final lot = _lot('a1', 'THYAO', 100, 300);
    PortfolioState state() => PortfolioState(
        assets: [lot], usdTry: 42, eurTry: 46, gbpTry: 54);

    setUpAll(() async {
      await initializeDateFormatting('tr_TR');
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });
    tearDownAll(() => debugDefaultTargetPlatformOverride = null);

    setUp(() {
      kanal = _Kanal()..kur();
      LiveActivityService.instance.resetForTest();
      final kume =
          state().activeAssets.where(FiyatKaynagi.seriyeGirer).toList();
      IntradaySeriesCache.instance.seedForTest(
        series: {_ms(10): 27000, _ms(14, 25): 30000},
        fetchedAt: _seans,
        seansGunu: _gun,
        kume: kume,
        byPosition: {
          positionKey(lot): {_ms(10): 27000, _ms(14, 25): 30000},
        },
        positionType: {positionKey(lot): AssetType.hisse},
      );
    });
    tearDown(() {
      kanal.kaldir();
      RemoteConfigService.testAcik = {};
      LiveActivityService.instance.showAmountsOnLockScreen = false;
      IntradaySeriesCache.instance.clear();
    });

    Future<Map<String, Object?>> senkron({bool gizli = false}) async {
      await LiveActivityService.instance
          .sync(state(), hideBalance: gizli, now: _seans);
      return kanal.calls.last;
    }

    test('bayrak + "Tutarları göster" açıkken satır dolu gider', () async {
      RemoteConfigService.testAcik = {'goz_alici'};
      LiveActivityService.instance.showAmountsOnLockScreen = true;
      final a = await senkron();
      expect(a['surukleyenAd'], 'THYAO');
      expect(a['surukleyenTutarText'], '+₺3.000');
      expect(a['surukleyenPctText'], '%11,11');
      expect(a['surukleyenPozitif'], isTrue);
    });

    test('"Tutarları göster" kapalıyken sembol gitmez', () async {
      RemoteConfigService.testAcik = {'goz_alici'};
      final a = await senkron();
      expect(a['surukleyenAd'], '');
      expect(a['surukleyenTutarText'], '');
    });

    test('bayrak kapalıyken sembol gitmez (eski davranış)', () async {
      LiveActivityService.instance.showAmountsOnLockScreen = true;
      final a = await senkron();
      expect(a['surukleyenAd'], '');
    });

    test('bakiye gizliyken sembol gitmez', () async {
      RemoteConfigService.testAcik = {'goz_alici'};
      LiveActivityService.instance.showAmountsOnLockScreen = true;
      final a = await senkron(gizli: true);
      expect(a['surukleyenAd'], '');
      expect(kanal.calls.expand((c) => c.values).whereType<String>(),
          isNot(contains('THYAO')));
    });
  });
}
