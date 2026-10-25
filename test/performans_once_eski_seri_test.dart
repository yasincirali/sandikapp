import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/portfoy_seri_depo.dart';
import 'package:portfoy_takip/services/seri_disk_depo.dart';
import 'package:portfoy_takip/widgets/zoom_data_controller.dart';

import 'helpers/kaynak.dart';

/// **Performans sekmesi önce diskteki son seriyle** — yalnız lot defteri
/// aynıysa (Ar-Ge 2026-10-25 §4, yasin onayı; karar kaydı
/// `PortfoySeriDepo`).
///
/// Kilitlenenler:
///   · parmak izi alım/satım/silme/düzenlemede değişir, fiyat turunda değişmez;
///   · kayıt yalnız AYNI parmak izinde, tazelik sınırında okunur; bozuk kayıt
///     yok sayılır;
///   · eski seri taze sonuçtan önce SOLUK çizilir, taze gelince yerini alır;
///   · taze çekim düşerse eski seri NET kalır, "son güncelleme" anıyla;
///   · iz tutmazsa bugünkü davranış (veri yok → iskelet).
void main() {
  Asset lot({
    String id = 'a1',
    double quantity = 10,
    DateTime? tarih,
    double fiyat = 100,
    AssetKind kind = AssetKind.buy,
    double? sellPrice,
    String? ref,
    double currentPrice = 100,
    DateTime? silindi,
  }) =>
      Asset(
        id: id,
        userId: 'u1',
        name: 'Türk Hava Yolları',
        ticker: 'THYAO.IS',
        type: AssetType.hisse,
        quantity: quantity,
        purchasePrice: fiyat,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: currentPrice,
        addedDate: tarih ?? DateTime(2020, 1, 1),
        kind: kind,
        sellPrice: sellPrice,
        refAssetId: ref,
        deletedAt: silindi,
      );

  group('lot defteri parmak izi', () {
    final defter = [lot(), lot(id: 'a2', quantity: 5)];
    final iz = PortfoySeriDepo.imza(defter, defter);

    test('aynı defter → aynı iz; fiyat turu izi değiştirmez', () {
      final ayni = [lot(), lot(id: 'a2', quantity: 5)];
      expect(PortfoySeriDepo.imza(ayni, ayni), iz);
      final fiyatDegisti = [
        lot(currentPrice: 140),
        lot(id: 'a2', quantity: 5, currentPrice: 140),
      ];
      expect(PortfoySeriDepo.imza(fiyatDegisti, fiyatDegisti), iz,
          reason: 'canlı fiyat her turda değişir; iz hiç tutmazdı');
    });

    test('lot eklenince değişir', () {
      final yeni = [...defter, lot(id: 'a3', quantity: 1)];
      expect(PortfoySeriDepo.imza(yeni, yeni), isNot(iz));
    });

    test('satış (kapanmış pozisyon dahil) değiştirir', () {
      final satis = [
        ...defter,
        lot(
            id: 's1',
            kind: AssetKind.sell,
            quantity: 15,
            sellPrice: 120,
            ref: 'a1',
            tarih: DateTime(2026, 10, 1)),
      ];
      expect(PortfoySeriDepo.imza(satis, satis), isNot(iz));
    });

    test('silme değiştirir — yumuşak silme de, satırın düşmesi de', () {
      final yumusak = [lot(), lot(id: 'a2', quantity: 5, silindi: DateTime(2026))];
      expect(PortfoySeriDepo.imza(yumusak, yumusak), isNot(iz));
      final dustu = [lot()];
      expect(PortfoySeriDepo.imza(dustu, dustu), isNot(iz));
    });

    test('düzenleme (miktar, tarih, fiyat) değiştirir', () {
      for (final d in [
        [lot(quantity: 11), lot(id: 'a2', quantity: 5)],
        [lot(tarih: DateTime(2021, 1, 1)), lot(id: 'a2', quantity: 5)],
        [lot(fiyat: 101), lot(id: 'a2', quantity: 5)],
      ]) {
        expect(PortfoySeriDepo.imza(d, d), isNot(iz));
      }
    });

    test('ham defter aynı, motora giden liste farklı (süzgeç) → değişir', () {
      expect(PortfoySeriDepo.imza(defter, [defter.first]), isNot(iz));
    });

    test('sözleşmeli lot (mevduat/BES) yola girmez', () {
      final mevduat = Asset(
        id: 'm1',
        userId: 'u1',
        name: 'Mevduat',
        ticker: 'MEVDUAT:1',
        type: AssetType.mevduat,
        quantity: 1,
        purchasePrice: 1000,
        currency: 'TRY',
        notes: '',
        sozlesmeId: 's1',
      );
      expect(PortfoySeriDepo.uygunMu(defter), isTrue);
      expect(PortfoySeriDepo.uygunMu([...defter, mevduat]), isFalse,
          reason: 'faiz/vade koşulu lot satırında değil; iz göremez');
    });
  });

  late Directory gecici;
  setUp(() {
    gecici = Directory.systemTemp.createTempSync('performans_once_eski');
    PortfoySeriDepo.kaliciDepo = SeriDiskDepo(
        kokDizin: () async => gecici,
        klasor: PortfoySeriDepo.klasor,
        azamiDosya: PortfoySeriDepo.azamiDosya);
  });
  tearDown(() {
    PortfoySeriDepo.kaliciDepo = null;
    if (gecici.existsSync()) gecici.deleteSync(recursive: true);
  });

  final simdi = DateTime.now();
  final from = simdi.subtract(const Duration(days: 90));
  Map<int, double> seri(double kaydir) => {
        for (var g = 89; g >= 0; g--)
          DateTime(simdi.year, simdi.month, simdi.day - g)
              .millisecondsSinceEpoch: 1000 + g + kaydir,
      };

  group('disk deposu', () {
    Future<({Map<int, double> seri, DateTime zaman})?> oku(String imza,
            {ResolutionTier tier = ResolutionTier.daily, DateTime? an}) =>
        PortfoySeriDepo.oku(
            anahtar: 'perf|u1|all|*|ucAy|false',
            imza: imza,
            tier: tier,
            from: from,
            to: simdi,
            simdi: an);

    test('yalnız AYNI parmak izinde okunur', () async {
      await PortfoySeriDepo.yaz(
          anahtar: 'perf|u1|all|*|ucAy|false', imza: 'iz1', seri: seri(0));
      final ayni = await oku('iz1');
      expect(ayni, isNotNull);
      expect(ayni!.seri, seri(0));
      expect(await oku('iz2'), isNull,
          reason: 'lot değişti: eski seri yeni defterin serisi değildir');
    });

    test('tazelik: günlük ≤ 7 gün, saatlik ≤ 1 gün', () async {
      await PortfoySeriDepo.yaz(
          anahtar: 'perf|u1|all|*|ucAy|false', imza: 'iz1', seri: seri(0));
      final an = DateTime.now();
      expect(await oku('iz1', an: an.add(const Duration(days: 6))), isNotNull);
      expect(await oku('iz1', an: an.add(const Duration(days: 8))), isNull);
      expect(
          await oku('iz1',
              tier: ResolutionTier.hourly,
              an: an.add(const Duration(hours: 20))),
          isNotNull);
      expect(
          await oku('iz1',
              tier: ResolutionTier.hourly,
              an: an.add(const Duration(days: 2))),
          isNull);
    });

    test('bozuk kayıt yok sayılır', () async {
      const k = 'perf|u1|all|*|ucAy|false';
      await PortfoySeriDepo.yaz(anahtar: k, imza: 'iz1', seri: seri(0));
      final f = File('${gecici.path}/${PortfoySeriDepo.klasor}/'
          '${SeriDiskDepo.dosyaAdi(k)}');
      expect(f.existsSync(), isTrue);
      f.writeAsStringSync('{bozuk');
      expect(await oku('iz1'), isNull);
    });

    test('sıfır değerli seri yazılmaz (depo sıfırı atar, çizgi değişirdi)',
        () async {
      final s = seri(0);
      s[s.keys.first] = 0;
      await PortfoySeriDepo.yaz(
          anahtar: 'perf|u1|all|*|ucAy|false', imza: 'iz1', seri: s);
      expect(await oku('iz1'), isNull);
    });

    test('çıkışta temizlenir', () async {
      await PortfoySeriDepo.yaz(
          anahtar: 'perf|u1|all|*|ucAy|false', imza: 'iz1', seri: seri(0));
      await PortfoySeriDepo.temizle();
      expect(await oku('iz1'), isNull);
    });
  });

  group('ZoomDataController: önce eski seri', () {
    late Completer<void> ag;
    var agHatali = false;
    List<(int, double)> gunluk() => [
          for (var g = 120; g >= 0; g--)
            (
              DateTime(simdi.year, simdi.month, simdi.day - g, 7)
                  .millisecondsSinceEpoch,
              200.0 + g,
            ),
        ];

    setUp(() {
      HistoryService.clearCache();
      HistoryService.instance.clearTierCache();
      ag = Completer<void>();
      agHatali = false;
      HistoryService.seriCekici = (s, r, i) async {
        await ag.future;
        if (agHatali) throw const SocketException('çevrimdışı');
        return gunluk();
      };
    });
    tearDown(() {
      HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
      HistoryService.clearCache();
      HistoryService.instance.clearTierCache();
    });

    final eskiZaman = DateTime.now().subtract(const Duration(hours: 5));

    ZoomDataController kur(
            {required ({Map<int, double> seri, DateTime zaman})? disk,
            List<Map<int, double>>? kayitlar}) =>
        ZoomDataController(
          assets: [lot()],
          initialFrom: from,
          initialTo: simdi,
          eldekiSeri: () async => disk,
          tazeKaydet: kayitlar?.add,
        );

    Future<void> bekle(ZoomDataController c) async {
      for (var i = 0; i < 20 && !c.settled; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('iz tutuyor: eski seri SOLUK, taze gelince yerini alır ve yazılır',
        () async {
      final kayitlar = <Map<int, double>>[];
      final c = kur(disk: (seri: seri(0), zaman: eskiZaman), kayitlar: kayitlar);
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(c.data, seri(0), reason: 'ağ beklenmeden eski seri çizilir');
      expect(c.stale, isTrue, reason: 'soluk');
      expect(c.sonGuncelleme, isNull);

      ag.complete();
      await bekle(c);
      expect(c.stale, isFalse);
      expect(c.data, isNot(seri(0)), reason: 'sayılar taze seriden');
      expect(c.data.values.last, closeTo(10 * 200, 1e-6));
      expect(c.sonGuncelleme, isNull);
      expect(kayitlar, hasLength(1), reason: 'taze ve tam ölçüm diske yazılır');
      expect(kayitlar.single, c.data);
    });

    test('iz tutmuyor (kayıt yok): bugünkü davranış — veri yok, iskelet',
        () async {
      final c = kur(disk: null);
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(c.data, isEmpty);
      expect(c.stale, isFalse);
      ag.complete();
      await bekle(c);
      expect(c.data, isNotEmpty);
    });

    test('taze çekim düşerse eski seri NET kalır, son güncelleme anıyla',
        () async {
      final kayitlar = <Map<int, double>>[];
      final c = kur(disk: (seri: seri(0), zaman: eskiZaman), kayitlar: kayitlar);
      addTearDown(c.dispose);
      await Future<void>.delayed(Duration.zero);
      agHatali = true;
      ag.complete();
      await bekle(c);
      expect(c.data, seri(0),
          reason: 'motor bileşeni düz tohumla çizerdi; ölçülmüş seri kalır');
      expect(c.stale, isFalse, reason: 'sonsuza dek soluk kalmaz');
      expect(c.sonGuncelleme, eskiZaman);
      expect(kayitlar, isEmpty, reason: 'eksik ölçüm diske yazılmaz');
    });

    test('taze sonuç önce geldiyse eski kopya yok sayılır', () async {
      ag.complete();
      final disk = Completer<({Map<int, double> seri, DateTime zaman})?>();
      final c = ZoomDataController(
        assets: [lot()],
        initialFrom: from,
        initialTo: simdi,
        eldekiSeri: () => disk.future,
      );
      addTearDown(c.dispose);
      await bekle(c);
      final taze = Map.of(c.data);
      disk.complete((seri: seri(0), zaman: eskiZaman));
      await Future<void>.delayed(Duration.zero);
      expect(c.data, taze);
      expect(c.stale, isFalse);
    });
  });

  test('ekran: zoom yolu ham defteri verir, gün içi diske gitmez', () {
    final k = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
    expect(k, contains('hamDefter: [for (final l in ownerLots) ...l]'),
        reason: 'parmak izi HAM defterden (kapanmış pozisyon kuralı)');
    expect(k, contains('PortfoySeriDepo.imza(hamDefter, chartAssets)'));
    expect(k, contains('if (donem.intraday) return null;'));
    expect(k, contains('SeriSonGuncelleme(zaman: sonGuncelleme)'));
  });
}
