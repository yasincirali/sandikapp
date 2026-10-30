// **Bugün dört yüzeyde aynı** (yasin 2026-10-30: "Bugün sayfası, canlı
// aktivite, Performans bugün ve varlık detay bugün tutarlı olmalı; altınım
// da varsa o da tutarlı gözükmeli, grafikle tepedeki kâr/zarar akla
// yatmalı").
//
// Hisse + gram altın + dolar, bugün açılıştan sonra alım (akış), dört an:
// borsa açılmadan, seans içi, seans sonrası, hafta sonu. Kilitlenen:
//   · Performans/Live Activity (`seansGunu` verilir) ile Bugün kartı
//     (verilmez) aynı tutar ve yüzde;
//   · varlık sayfalarının GÜNLÜK tutarları (birim seri +
//     `birimPiyasaEtkisi`) toplamı = portföyün günlük tutarı;
//   · seans içinde her varlığın sayfa yüzdesi kotasyonun günlük yüzdesi —
//     hissede açılış sıçraması dahil (`yahooSeriCoz` önceki kapanışı
//     ekler; önceden ilk bar gün başıydı: kotasyon +%2,0, sayfa +%1,35).
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/price_service.dart';

/// Yahoo `v8/finance/chart` gün içi yanıtı — gerçek ayrıştırıcıdan geçer.
List<(int, double)> yahooHisse(List<(int, double)> barlar, double onceki) =>
    yahooSeriCoz({
      'chart': {
        'result': [
          {
            'meta': {'instrumentType': 'EQUITY', 'chartPreviousClose': onceki},
            'timestamp': [for (final b in barlar) b.$1 ~/ 1000],
            'indicators': {
              'quote': [
                {'close': [for (final b in barlar) b.$2]}
              ]
            },
          }
        ]
      }
    }, gunIci: true);

List<(int, double)> seri(DateTime bas, DateTime son, double ilk, double sonD) {
  final out = <(int, double)>[];
  if (son.isBefore(bas)) return out;
  final n = son.difference(bas).inMinutes ~/ 5;
  var t = bas;
  var i = 0;
  while (!t.isAfter(son)) {
    out.add((t.millisecondsSinceEpoch, n == 0 ? sonD : ilk + (sonD - ilk) * i / n));
    t = t.add(const Duration(minutes: 5));
    i++;
  }
  return out;
}

DateTime sonIsGunu(DateTime t) {
  var d = DateTime(t.year, t.month, t.day);
  while (d.weekday > 5) {
    d = d.subtract(const Duration(days: 1));
  }
  return d;
}

Asset lot(String id, String ticker, AssetType tur, double q, double alis,
        double canli, DateTime eklendi) =>
    Asset(
      id: id, userId: 'u1', name: ticker, ticker: ticker, type: tur,
      quantity: q, purchasePrice: alis, currency: 'TRY', notes: '',
      isManualPrice: false, currentPrice: canli, addedDate: eklendi,
    );

Future<Map<String, double>> senaryo(DateTime simdi) async {
  HistoryService.clearCache();
  PriceService.instance.sonBilinenFiyatlariTemizle();
  HistoryService.gunIciSaat = () => simdi;
  HistoryService.yurtIciSekilAcik = () => false;
  final gunBasi = DateTime(simdi.year, simdi.month, simdi.day);
  final isGunu = sonIsGunu(simdi);
  final hisseAcik = simdi.weekday <= 5 && simdi.hour >= 10;
  // Hisse seansı: bugün açıldıysa bugün, değilse son iş günü (bugün değilse dün).
  var hisseGun = hisseAcik ? gunBasi : sonIsGunu(gunBasi.subtract(const Duration(days: 1)));
  if (simdi.weekday > 5) hisseGun = isGunu;
  final hisseSon = hisseAcik
      ? (simdi.hour >= 18 ? hisseGun.add(const Duration(hours: 18)) : simdi)
      : hisseGun.add(const Duration(hours: 18));
  HistoryService.yurtIciKaynagi = (s, bas) async =>
      s == 'ALTIN_GRAM' && simdi.weekday <= 5
          ? seri(gunBasi, simdi, 5940, 6000)
          : const [];
  HistoryService.seriCekici = (sym, range, interval) async {
    if (sym == 'THYAO.IS') {
      // Önceki kapanış 294,12; açılış 296'dan (sıçrama), canlı 300.
      return yahooHisse(
          seri(hisseGun.add(const Duration(hours: 10)), hisseSon, 296, 300),
          294.12);
    }
    final yBas = isGunu.add(const Duration(hours: 3));
    final ySon = simdi.weekday > 5 ? isGunu.add(const Duration(hours: 23)) : simdi;
    if (sym == FiyatKaynagi.usdTry) return seri(yBas, ySon, 41.85, 42);
    if (sym == FiyatKaynagi.xauTry) return seri(yBas, ySon, 200000, 199000);
    return const [];
  };
  PriceService.instance.testIcinKotasyonYaz('THYAO.IS', 300, gunlukPct: 2.0);
  PriceService.instance.testIcinKotasyonYaz('USDTRY=X', 42, gunlukPct: 0.5);
  PriceService.instance.testIcinKotasyonYaz('ALTIN_GRAM', 6000, gunlukPct: 1.0);

  final eski = DateTime(2024);
  final assets = [
    lot('t1', 'THYAO.IS', AssetType.hisse, 10, 200, 300, eski),
    lot('t2', 'THYAO.IS', AssetType.hisse, 5, 298, 300,
        gunBasi.add(const Duration(hours: 7, minutes: 30))),
    lot('g1', 'ALTIN_GRAM', AssetType.altin, 10, 3000, 6000, eski),
    lot('u1', 'USDTRY=X', AssetType.doviz, 1000, 30, 42, eski),
  ];
  final state = PortfolioState(
      assets: assets, usdTry: 42, eurTry: 46, gbpTry: 54, ownerId: 'u1');
  final b = await HistoryService.instance
      .getPortfolioHistoryHourlyBreakdown(assets, 24);
  final perf = DailySummary.from(
      state: state, series: b.total, now: simdi, seansGunu: b.seansGunu);
  final kart = DailySummary.from(state: state, series: b.total, now: simdi);
  expect(perf.changeTRY, isNotNull);
  expect(kart.changeTRY, closeTo(perf.changeTRY!, 0.005),
      reason: 'Bugün kartı ile Performans/Live Activity aynı tutar');
  expect(kart.changePct, closeTo(perf.changePct!, 1e-9));

  var toplam = 0.0;
  final yuzdeler = <String, double>{};
  for (final grup in [
    ['t1', 't2'],
    ['g1'],
    ['u1']
  ]) {
    final lotlar = assets.where((a) => grup.contains(a.id)).toList();
    HistoryService.clearCache();
    // Varlık sayfası GÜNLÜK: birim seri (`_loadHistory`) + tutar
    // (`_donemDegisimi`).
    final bb = await HistoryService.instance.getPortfolioHistoryHourlyBreakdown(
        [FiyatKaynagi.birimVarlik(lotlar.first)], 24);
    final start = bb.seansGunu ?? gunBasi;
    final u = PeriodSummaryService.uclar(bb.total,
        fromMs: start.millisecondsSinceEpoch,
        toMs: simdi.millisecondsSinceEpoch)!;
    final canli = lotlar.first.currentPrice;
    toplam += PeriodSummaryService.birimPiyasaEtkisi(
            birimSeri: bb.total,
            lotlar: lotlar,
            start: start,
            end: simdi,
            canliBirim: canli)!
        .piyasa;
    yuzdeler[lotlar.first.ticker] = (canli / u.first - 1) * 100;
  }
  expect(toplam, closeTo(perf.changeTRY!, 0.01),
      reason: 'varlık sayfalarının GÜNLÜK tutarları toplamı = portföyün '
          'günlük tutarı');
  return yuzdeler;
}

void main() {
  tearDown(() {
    HistoryService.gunIciSaat = DateTime.now;
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    HistoryService.yurtIciKaynagi = (_, __) async => const [];
    HistoryService.clearCache();
    PriceService.instance.sonBilinenFiyatlariTemizle();
  });
  test('borsa açılmadan: hisse bugün oynamadı, döviz ve altın oynadı',
      () async {
    final y = await senaryo(DateTime(2026, 10, 29, 8, 30));
    expect(y['THYAO.IS'], closeTo(0, 1e-9));
    expect(y['USDTRY=X'], closeTo(0.5, 1e-6));
  });

  for (final t in [DateTime(2026, 10, 29, 15), DateTime(2026, 10, 29, 21)]) {
    test('seans $t: her varlığın sayfa yüzdesi kotasyonun günlük yüzdesi',
        () async {
      final y = await senaryo(t);
      expect(y['THYAO.IS'], closeTo(2.0, 0.01),
          reason: 'açılış sıçraması dahil (ilk bar 296 değil, kapanış 294,12)');
      expect(y['USDTRY=X'], closeTo(0.5, 1e-6));
      // Altın: gün başı yurt içi kaydın ilk noktası (2026-10-19 kararı).
      expect(y['ALTIN_GRAM'], closeTo((6000 / 5940 - 1) * 100, 1e-6));
    });
  }

  test('hafta sonu: yalnız bugünkü alımın fiyat farkı', () async {
    final y = await senaryo(DateTime(2026, 10, 31, 12));
    expect(y.values, everyElement(closeTo(0, 1e-9)));
  });
}
