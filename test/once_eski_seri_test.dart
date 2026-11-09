import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/seri_disk_depo.dart';

/// **Önce eski seri, sonra taze** (stale-while-revalidate, Ar-Ge raporu
/// 2026-10-24 §1 YAP; karar kaydı `HistoryService.eldekiSeriyle`).
///
/// Soğuk açılışta bellek boş; varlık sayfası ve varlık grafiği ağ yanıtına
/// kadar iskelet gösteriyordu, diskteki son iyi seri yalnız çekim düşerse
/// okunuyordu. Rapor şartları:
///   · eski seri yalnız yeterince tazeyse (günlük/haftalık ≤ 7 gün, gün içi
///     yalnız bugünün),
///   · ağ düşerse eski seri kalır, "son güncelleme" ile (`bayatZaman`),
///   · eldeki kip ağa çıkmaz ve taze yolu zehirlemez.
void main() {
  late Directory gecici;
  var ag = 0;

  setUp(() {
    HistoryService.clearCache();
    HistoryService.instance.clearTierCache();
    gecici = Directory.systemTemp.createTempSync('once_eski_seri');
    HistoryService.kaliciDepo = SeriDiskDepo(kokDizin: () async => gecici);
    ag = 0;
  });

  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    HistoryService.gunIciSaat = DateTime.now;
    HistoryService.kaliciDepo = null;
    HistoryService.clearCache();
    HistoryService.instance.clearTierCache();
    if (gecici.existsSync()) gecici.deleteSync(recursive: true);
  });

  /// Son 120 günün günlük seri (bugüne kadar), değer gün indeksinden.
  List<(int, double)> gunluk({double kaydir = 0}) {
    final bugun = DateTime.now();
    return [
      for (var g = 120; g >= 0; g--)
        (
          DateTime(bugun.year, bugun.month, bugun.day - g, 7)
              .millisecondsSinceEpoch,
          100 + g * 0.5 + kaydir,
        ),
    ];
  }

  void agdan(List<(int, double)> Function(String sym) cevap) {
    HistoryService.seriCekici = (s, r, i) async {
      ag++;
      return cevap(s);
    };
  }

  void agYok() {
    HistoryService.seriCekici = (s, r, i) async {
      ag++;
      throw const SocketException('çevrimdışı');
    };
  }

  /// "Uygulama yeniden açıldı": bellek boş, disk dolu.
  Future<void> yenidenAc() async {
    // Diske yazım arka planda; bitmesini bekle.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    HistoryService.clearCache();
    HistoryService.instance.clearTierCache();
  }

  test('soğuk açılış: diskteki seri AĞA ÇIKMADAN döner, ölçüldüğü anla',
      () async {
    agdan((_) => gunluk());
    final taze = await HistoryService.instance
        .getSymbolHistory('THYAO.IS', periodDays: 90);
    await yenidenAc();

    agYok();
    ag = 0;
    final once = DateTime.now();
    final eldeki = await HistoryService.instance
        .getSymbolHistoryEldeki('THYAO.IS', periodDays: 90);
    expect(ag, 0, reason: 'eski seri yolu ağa çıkmamalı');
    expect(eldeki, isNotNull);
    expect(eldeki!.seri, taze,
        reason: 'aynı motor, aynı kırpma: eski seri ölçülmüş seridir');
    expect(once.difference(eldeki.zaman).inMinutes, lessThan(1));
  });

  test('bileşen eksikse (kur yok) eski seri GÖSTERİLMEZ', () async {
    // AAPL diske yazıldı, USDTRY yazılmadı: eksik bileşenle hesap başka bir
    // sayı üretirdi — iskelet daha dürüst.
    agdan((s) => s == FiyatKaynagi.usdTry ? const [] : gunluk());
    await HistoryService.instance.getSymbolHistory('AAPL', periodDays: 90);
    await yenidenAc();
    agYok();
    expect(
        await HistoryService.instance
            .getSymbolHistoryEldeki('AAPL', periodDays: 90),
        isNull);
  });

  test('taze çekim: başarılıysa bayatZaman yok, ağ düşerse ölçüldüğü an',
      () async {
    agdan((_) => gunluk());
    final ilk = await HistoryService.instance
        .getSymbolHistoryTazelikli('THYAO.IS', periodDays: 90);
    expect(ilk.seri, isNotEmpty);
    expect(ilk.bayatZaman, isNull);

    await yenidenAc();
    agYok();
    final dustu = await HistoryService.instance
        .getSymbolHistoryTazelikli('THYAO.IS', periodDays: 90);
    expect(dustu.seri, ilk.seri, reason: 'ağ düştü, eski seri kalır');
    expect(dustu.bayatZaman, isNotNull,
        reason: 'ekran "son güncelleme" yazabilmeli');
  });

  test('eldeki kip taze yolu zehirlemez: sonraki çekim yine ağa gider',
      () async {
    agdan((_) => gunluk());
    await HistoryService.instance.getSymbolHistory('THYAO.IS', periodDays: 90);
    await yenidenAc();

    await HistoryService.instance
        .getSymbolHistoryEldeki('THYAO.IS', periodDays: 90);
    ag = 0;
    agdan((_) => gunluk(kaydir: 5));
    final taze = await HistoryService.instance
        .getSymbolHistory('THYAO.IS', periodDays: 90);
    expect(ag, greaterThan(0),
        reason: 'eski kopya süreli önbelleğe TAZE gibi yazılmamalı');
    expect(taze.values.last, closeTo(105, 1e-9),
        reason: 'yeni seri gelince sayılar yeni seriden');
  });

  test(
      'varlık detayı motoru eldeki kipte: aynı birim seri, tier önbelleği '
      'temiz kalır', () async {
    final lot = Asset(
      id: 'a1',
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 100,
      addedDate: DateTime(2020, 1, 1),
      kind: AssetKind.buy,
    );
    final birim = FiyatKaynagi.birimVarlik(lot);
    final simdi = DateTime.now();
    Future<PortfolioHistoryBreakdown> motor() =>
        HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
          assets: [birim],
          from: simdi.subtract(const Duration(days: 90)),
          to: simdi,
          tier: ResolutionTier.daily,
        );

    agdan((_) => gunluk());
    final taze = await motor();
    expect(taze.total, isNotEmpty);
    await yenidenAc();

    agYok();
    ag = 0;
    final eldeki = await HistoryService.eldekiSeriyle(motor);
    expect(ag, 0);
    expect(eldeki, isNotNull);
    expect(eldeki!.sonuc.total, taze.total);

    agdan((_) => gunluk(kaydir: 5));
    await motor();
    expect(ag, greaterThan(0),
        reason: 'eldeki kip tier önbelleğine yazmış: taze hesap ağa '
            'çıkmadan eski seriyi okurdu');
  });

  test('gün içi: dünün serisi eski seri olarak da kullanılmaz', () async {
    // Gerçek bugün: "ölçüldüğü an" duvar saatinden yazılır.
    final b = DateTime.now();
    final bugun = DateTime(b.year, b.month, b.day, 0, 1);
    HistoryService.gunIciSaat = () => DateTime(b.year, b.month, b.day, 23, 50);
    agdan((_) => [
          (bugun.millisecondsSinceEpoch, 10.0),
          (bugun.add(const Duration(minutes: 5)).millisecondsSinceEpoch, 11.0),
        ]);
    await HistoryService.instance.seriCek('KRIPTO:BTC', '1d', interval: '5m');
    HistoryService.onbellegiEskit();
    Future<Object?> eldeki() => HistoryService.eldekiSeriyle(() =>
        HistoryService.instance.seriCek('KRIPTO:BTC', '1d', interval: '5m'));
    expect(await eldeki(), isNotNull, reason: 'aynı gün: kullanılır');

    HistoryService.onbellegiEskit();
    HistoryService.gunIciSaat = () => DateTime(b.year, b.month, b.day + 1, 10);
    expect(await eldeki(), isNull, reason: 'ertesi gün: kullanılmaz');
  });

  group('tazelik sınırı', () {
    final simdi = DateTime(2026, 10, 24, 12);
    bool k(String range, String? interval, Duration yas) =>
        HistoryService.bayatKullanilirMi(
            range: range,
            interval: interval,
            olculdu: simdi.subtract(yas),
            simdi: simdi);

    test('günlük/haftalık en fazla 7 gün', () {
      expect(k('3mo', '1d', const Duration(days: 6)), isTrue);
      expect(k('5y', '1wk', const Duration(days: 7)), isTrue);
      expect(k('3mo', '1d', const Duration(days: 8)), isFalse,
          reason: 'haftalar önceki seri soluk da olsa yanıltır');
      expect(k('5y', '1wk', const Duration(days: 30)), isFalse);
    });

    test('saatlik en fazla 1 gün; gün içi yalnız bugünün', () {
      expect(k('1mo', '1h', const Duration(hours: 20)), isTrue);
      expect(k('1mo', '1h', const Duration(days: 2)), isFalse);
      expect(k('1d', '5m', const Duration(hours: 3)), isTrue);
      expect(k('1d', '5m', const Duration(hours: 13)), isFalse,
          reason: 'dün ölçülen gün içi seri bugünün grafiği değildir');
    });
  });
}
