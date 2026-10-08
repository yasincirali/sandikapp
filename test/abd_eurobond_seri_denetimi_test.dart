import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/eurobond.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart'
    show PeriodSummaryService, SummaryPeriod;
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/services/sparkline_service.dart';

/// ABD hissesi ve eurobond — yedi dönemin HER yüzeyde gerçek seriyle
/// çizildiğinin denetimi (seri denetimi, 2026-10-08; yasin: "tüm varlıklar
/// için günlük, haftalık, aylık, 3 aylık, 6 aylık, yıllık ve 5 yıllık …
/// tutarlı ve düzgün gerçek datalarla").
///
/// Ağ yok: `HistoryService.seriCekici` sağlayıcının döndüreceği biçimde
/// nokta üretir (ABD hissesi USD, eurobond kirli/100 USD — `PriceService`
/// çıktısının ölçeği). Kur sabit 40: TL değer fiyat × 40 olmalı. Çift
/// çevrim (× 1600) ya da çevrimsizlik (× 1) burada yakalanır.
void main() {
  const kur = 40.0;
  const nominal = 10000.0;
  const adet = 3.0;
  final aaplSembol = 'AAPL';
  final tahvilSembol = eurobondSembolu('US900123DF45');

  Asset aapl() => Asset(
        id: 'aapl',
        userId: 'u',
        name: 'Apple',
        ticker: aaplSembol,
        type: AssetType.hisse,
        subCategory: StockSubCategory.abd.name,
        quantity: adet,
        purchasePrice: 200,
        currency: 'USD',
        notes: '',
        isManualPrice: false,
        currentPrice: 250,
        addedDate: DateTime(2015),
      );

  Asset tahvil() => Asset(
        id: 'eb',
        userId: 'u',
        name: 'Türkiye %9,875 2028',
        ticker: tahvilSembol,
        type: AssetType.eurobond,
        quantity: nominal,
        purchasePrice: 1.03,
        currency: 'USD',
        notes: '',
        isManualPrice: false,
        currentPrice: 1.07,
        addedDate: DateTime(2015),
      );

  /// Sağlayıcının o aralık için verdiği adım.
  Duration adim(String? interval, String range) =>
      switch (interval ?? _varsayilanAralik(range)) {
        '1m' => const Duration(minutes: 1),
        '5m' => const Duration(minutes: 5),
        '15m' => const Duration(minutes: 15),
        '1h' || '60m' => const Duration(hours: 1),
        '1wk' => const Duration(days: 7),
        _ => const Duration(days: 1),
      };

  /// Gün içi aralıkta yalnız seans saatleri (ABD 16:30–23:00 TR,
  /// Frankfurt 09:00–18:30 TR), hafta içi. Günlük/haftalıkta her adım.
  bool seansta(DateTime t, String sym, Duration a) {
    if (a >= const Duration(days: 1)) return true;
    if (t.weekday >= DateTime.saturday) return false;
    final dk = t.hour * 60 + t.minute;
    return sym == aaplSembol
        ? dk >= 16 * 60 + 30 && dk < 23 * 60
        : dk >= 9 * 60 && dk < 18 * 60 + 30;
  }

  /// Fiyat zamanla doğrusal artar: pencerenin başında [ilk], sonunda [son].
  List<(int, double)> uret(String sym, String range, String? interval,
      DateTime simdi) {
    final a = adim(interval, range);
    final gun = _rangeGun(range);
    final bas = simdi.subtract(Duration(days: gun));
    final (ilk, son) = sym == aaplSembol ? (200.0, 250.0) : (1.03, 1.07);
    final out = <(int, double)>[];
    for (var t = bas; !t.isAfter(simdi); t = t.add(a)) {
      if (!seansta(t, sym, a)) continue;
      final oran = t.difference(bas).inMinutes / (gun * 24 * 60);
      out.add((t.millisecondsSinceEpoch, ilk + (son - ilk) * oran));
    }
    return out;
  }

  late List<(String, String, String?)> istekler;

  void sahteSaglayici({DateTime? simdi}) {
    istekler = [];
    HistoryService.seriCekici = (sym, range, interval) async {
      istekler.add((sym, range, interval));
      final an = simdi ?? DateTime.now();
      if (sym == FiyatKaynagi.usdTry) {
        // Kur her an 40 — 7/24 ve gün içi.
        final a = adim(interval, range);
        final bas = an.subtract(Duration(days: _rangeGun(range)));
        return [
          for (var t = bas; !t.isAfter(an); t = t.add(a))
            (t.millisecondsSinceEpoch, kur),
        ];
      }
      if (sym == aaplSembol || sym == tahvilSembol) {
        return uret(sym, range, interval, an);
      }
      return const [];
    };
  }

  setUp(() {
    HistoryService.clearCache();
    HistoryService.instance.clearTierCache();
    HistoryService.canliKur = () => kur;
  });

  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    HistoryService.gunIciSaat = DateTime.now;
    HistoryService.canliKur =
        () => PriceService.instance.sonBilinenFiyat(FiyatKaynagi.usdTry);
  });

  /// Seri: boş değil, düz değil, her nokta fiyat × kur × miktar bandında.
  void seriDogrula(Map<int, double> seri, {required double altBirim,
      required double ustBirim, required double miktar, String? neden}) {
    expect(seri.length, greaterThanOrEqualTo(2), reason: neden);
    expect(seri.values.toSet().length, greaterThan(1),
        reason: '${neden ?? ''}: düz çizgi (canlı fiyat tohumu)');
    for (final v in seri.values) {
      expect(v, inInclusiveRange(altBirim * kur * miktar * 0.999,
          ustBirim * kur * miktar * 1.001),
          reason: '${neden ?? ''}: TL ölçeği (fiyat × kur × miktar) dışında '
              '— çift çevrim ya da çevrimsizlik');
    }
  }

  group('Performans / varlık ekranı — dönem motoru (AtResolution)', () {
    for (final p in SummaryPeriod.values.where((p) => !p.intraday)) {
      test('${p.label}: ABD hissesi ve eurobond gerçek seriyle', () async {
        sahteSaglayici();
        final now = DateTime.now();
        final from = PeriodSummaryService.pencere(p, now).start;
        final tier = ResolutionTierMeta.pickForSpan(
            now.difference(from).inMinutes / (60.0 * 24.0));
        for (final (varlik, alt, ust, miktar) in [
          (aapl(), 200.0, 250.0, adet),
          (tahvil(), 1.03, 1.07, nominal),
        ]) {
          // Varlık ekranı BİRİM seri çizer (`FiyatKaynagi.birimVarlik`).
          final birim = await HistoryService.instance
              .getPortfolioHistoryBreakdownAtResolution(
            assets: [FiyatKaynagi.birimVarlik(varlik)],
            from: from,
            to: now,
            tier: tier,
          );
          seriDogrula(birim.total,
              altBirim: alt, ustBirim: ust, miktar: 1,
              neden: '${p.label} ${varlik.ticker} birim');
          // Performans aynı motoru lot'la çağırır.
          final lot = await HistoryService.instance
              .getPortfolioHistoryBreakdownAtResolution(
            assets: [varlik],
            from: from,
            to: now,
            tier: tier,
          );
          seriDogrula(lot.total,
              altBirim: alt, ustBirim: ust, miktar: miktar,
              neden: '${p.label} ${varlik.ticker} lot');
          expect(lot.byType.keys, [varlik.type]);
        }
        expect(istekler.map((r) => r.$1), contains(tahvilSembol));
        expect(istekler.map((r) => r.$1), contains(aaplSembol));
      });
    }
  });

  group('GÜNLÜK — gün içi motoru (TR günü)', () {
    test('ABD seansı açıkken: hareket çizilir, tür "veri yok" değil',
        () async {
      // Çarşamba 20:00 TR: ABD seansı 16:30'da açıldı.
      final simdi = DateTime(2026, 10, 7, 20, 0);
      HistoryService.gunIciSaat = () => simdi;
      sahteSaglayici(simdi: simdi);
      final bd = await HistoryService.instance
          .getPortfolioHistoryHourlyBreakdown([aapl()], 24);
      expect(bd.gunIciVerisiYokTurler, isEmpty);
      final sirali = bd.total.keys.toList()..sort();
      // Açılıştan sonra hareket var; son nokta son fiyat × kur.
      final acilis = DateTime(2026, 10, 7, 16, 30).millisecondsSinceEpoch;
      final seans = [for (final k in sirali) if (k >= acilis) bd.total[k]!];
      expect(seans.toSet().length, greaterThan(1));
      expect(bd.total[sirali.last]! / (adet * kur), closeTo(250, 0.5));
    });

    test('ABD seansı açılmadan (10:00 TR): dünkü kapanış taşınır, boş değil',
        () async {
      final simdi = DateTime(2026, 10, 7, 10, 0);
      HistoryService.gunIciSaat = () => simdi;
      sahteSaglayici(simdi: simdi);
      final bd = await HistoryService.instance
          .getPortfolioHistoryHourlyBreakdown([aapl()], 24);
      expect(bd.total, isNotEmpty);
      // Yahoo `1d` son seansı verir (dün 16:30–23:00): bugünün slotları
      // gerçek veridir (dünün son fiyatı), "veri yok" notu çıkmaz.
      expect(bd.gunIciVerisiYokTurler, isEmpty);
      for (final v in bd.total.values) {
        expect(v / (adet * kur), inInclusiveRange(200, 250));
      }
    });

    test('eurobond Pazartesi 09:30: Cuma seansı taşınır, "veri yok" denmez',
        () async {
      // Sunucu `1d` dönemini son seansı kapsayacak şekilde açar
      // (`eurobond.ts` › SON_SEANS_GERIYE_GUN); sağlayıcı Cuma noktalarını
      // döndürür.
      final simdi = DateTime(2026, 10, 12, 9, 30);
      HistoryService.gunIciSaat = () => simdi;
      HistoryService.seriCekici = (sym, range, interval) async {
        if (sym == tahvilSembol) {
          final cuma = DateTime(2026, 10, 9);
          return [
            (cuma.add(const Duration(hours: 10)).millisecondsSinceEpoch, 1.06),
            (cuma.add(const Duration(hours: 15)).millisecondsSinceEpoch, 1.065),
          ];
        }
        if (sym == FiyatKaynagi.usdTry) {
          return [
            (simdi.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
                kur),
          ];
        }
        return const [];
      };
      final bd = await HistoryService.instance
          .getPortfolioHistoryHourlyBreakdown([tahvil()], 24);
      expect(bd.gunIciVerisiYokTurler, isEmpty);
      expect(bd.total, isNotEmpty);
      // Slotlar Cuma kapanışı (1,065) ile canlı kotasyon (1,07; "şimdi"
      // çapası) arasındadır — uydurma/sıfır değer yok.
      for (final v in bd.total.values) {
        expect(v / (kur * nominal), inInclusiveRange(1.065 - 1e-9, 1.07 + 1e-9));
      }
    });

    test('eurobond gün içi: Frankfurt noktaları çizilir', () async {
      final simdi = DateTime(2026, 10, 7, 15, 0);
      HistoryService.gunIciSaat = () => simdi;
      sahteSaglayici(simdi: simdi);
      final bd = await HistoryService.instance
          .getPortfolioHistoryHourlyBreakdown([tahvil()], 24);
      expect(bd.gunIciVerisiYokTurler, isEmpty);
      expect(bd.byType.keys, [AssetType.eurobond]);
      expect(bd.total.values.toSet().length, greaterThan(1));
    });
  });

  group('Takip listesi / varlık sayfası / Karşılaştır — sembol serisi', () {
    for (final p in SummaryPeriod.values) {
      test('${p.label}: TL seri, tek çevrim', () async {
        sahteSaglayici();
        for (final (sym, alt, ust) in [
          (aaplSembol, 200.0, 250.0),
          (tahvilSembol, 1.03, 1.07),
        ]) {
          final seri = await HistoryService.instance
              .getSymbolHistory(sym, periodDays: p.sembolGunu);
          seriDogrula(seri,
              altBirim: alt, ustBirim: ust, miktar: 1,
              neden: '${p.label} $sym');
        }
      });
    }
  });

  test('Karşılaştır (varlık ekranından): eski motor da gerçek seri', () async {
    sahteSaglayici();
    for (final p in SummaryPeriod.values) {
      for (final (varlik, alt, ust) in [
        (aapl(), 200.0, 250.0),
        (tahvil(), 1.03, 1.07),
      ]) {
        final seri = await HistoryService.instance.getPortfolioHistory(
            [FiyatKaynagi.birimVarlik(varlik)], p.sembolGunu);
        expect(seri.length, greaterThanOrEqualTo(2),
            reason: '${p.label} ${varlik.ticker}');
        for (final v in seri.values) {
          expect(v / kur, inInclusiveRange(alt * 0.999, ust * 1.001),
              reason: '${p.label} ${varlik.ticker}');
        }
      }
    }
  });

  group('kaynak kararları', () {
    test('seriye girer, sparkline destekler, USD kote', () {
      for (final a in [aapl(), tahvil()]) {
        expect(FiyatKaynagi.seriyeGirer(a), isTrue);
        expect(SparklineService.supports(a), isTrue);
        expect(FiyatKaynagi.usdKote(a), isTrue);
        expect(FiyatKaynagi.seriSembolleri(a), [a.ticker, FiyatKaynagi.usdTry]);
      }
      expect(FiyatKaynagi.yediGun(tahvil()), isFalse);
    });

    // Eurobond serisi `eurobond-seri`'ye Yahoo adlarıyla gider
    // (`PriceService.kriptoAraligi/kriptoDonemi`). Sunucu yalnız şu dönem
    // ve aralıkları kabul eder (`_shared/eurobond.ts` › DONEM_GUN,
    // `seriIstegiCoz`); tanımadığını 400 ile reddeder ve grafik boş kalır.
    // İstemcinin HER yolda istediği çift kabul edilmeli.
    test('her dönem/çözünürlük isteği sunucunun kabul ettiği biçimde', () {
      const donemler = {
        '1d', '5d', '1mo', '3mo', '6mo', 'ytd', '1y', '2y', '5y', 'max',
      };
      final aralik = RegExp(r'^(1m|2m|5m|15m|30m|60m|90m|1h|1d|1wk|1mo)$');
      final istekler = <(String, String)>{
        // Gün içi motoru: `seriCek(sym, '1d')` → varsayılan aralık.
        ('1d', _varsayilanAralik('1d')),
        // Sembol yolu ve eski motor: dönem merdiveni.
        for (final p in SummaryPeriod.values) ...{
          (
            HistoryService.rangeForPeriod(p.sembolGunu),
            HistoryService.tierForPeriod(p.sembolGunu).yahooInterval,
          ),
          (
            HistoryService.rangeForPeriod(p.sembolGunu),
            _varsayilanAralik(HistoryService.rangeForPeriod(p.sembolGunu)),
          ),
        },
        // Performans / varlık ekranı / yakınlaştırma: her katman.
        for (final t in ResolutionTier.values) (t.yahooRange, t.yahooInterval),
      };
      for (final (r, i) in istekler) {
        expect(donemler, contains(PriceService.kriptoDonemi(r)),
            reason: 'dönem $r');
        expect(aralik.hasMatch(PriceService.kriptoAraligi(i)), isTrue,
            reason: 'aralık $i');
      }
    });
  });
}

/// `PriceService._intervalFor` ile aynı eşleme (özel; burada aynası).
String _varsayilanAralik(String range) => switch (range) {
      '1d' => '5m',
      '5d' => '1h',
      '1mo' => '1d',
      '3mo' => '1d',
      '6mo' => '1d',
      '1y' => '1wk',
      _ => '1d',
    };

int _rangeGun(String range) => switch (range) {
      '1d' => 1,
      '5d' => 5,
      '1mo' => 31,
      '3mo' => 92,
      '6mo' => 183,
      '1y' => 366,
      '2y' => 731,
      _ => 1827,
    };
