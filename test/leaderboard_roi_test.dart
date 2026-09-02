import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/leaderboard_service.dart';

/// **Yarışta HERKES aynı formülle ölçülür: ortalama maliyet üzerinden
/// kâr/zarar.**
///
/// ## Neden bu test var
/// Önceki hesap İKİ farklı formül kullanıyordu ve hangisinin çalıştığı
/// kişiye göre değişiyordu:
///   · dönem başında portföyü OLAN → `(değer − dönemBaşı − nakitAkışı) / dönemBaşı`
///   · dönem başında portföyü OLMAYAN → maliyet bazlı fallback
///
/// Ölçüldü: aynı işlemi yapan iki kullanıcı (ikisi de 100'den alıp 120'ye
/// çıkmış = %20 kâr) **%380,67** ve **%20,00** olarak sıralanıyordu.
/// Aynı yarışta iki farklı metrik → sıralama anlamsız.
///
/// Tek formül bu sorunu YAPISAL olarak çözer: dallanma yoksa kişiye göre
/// değişen bir sonuç da olamaz.
///
/// ## Kabul edilen sınır
/// Bu bir zaman ağırlıklı getiri (TWR) değildir; dönem seçimi sonucu
/// etkilemez. 3 yılda %50 kazanan ile 3 ayda %50 kazanan aynı görünür.
/// TWR her lot için tarihsel nakit akışı isterdi; veri modeli taşımıyor.

const _uid = 'u1';

Asset _lot({
  required String ticker,
  double qty = 10,
  double buy = 100,
  double current = 120,
  double commission = 0,
  String currency = 'TRY',
  double fx = 1.0,
  AssetKind kind = AssetKind.buy,
  DateTime? added,
}) =>
    Asset(
      id: '$ticker-$qty-${kind.name}',
      userId: _uid,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: buy,
      currency: currency,
      notes: '',
      isManualPrice: true,
      purchaseFxRate: fx,
      commission: commission,
      currentPrice: current,
      addedDate: added ?? DateTime.now().subtract(const Duration(days: 30)),
      kind: kind,
    );

double _toTRY(double v, String c) => v;

double? _roi(List<Asset> assets) {
  final svc = LeaderboardService.instance;
  return svc.maliyetBazliKarZararPct(
    assets,
    svc.totalValueTRY(assets, _toTRY),
    _toTRY,
  );
}

void main() {
  group('tek formül — herkes aynı ölçülür', () {
    test('ALIM TARİHİ sonucu değiştirmez', () {
      // Bug'ın ta kendisi: aynı kâr, farklı tarih → farklı sıralama.
      final now = DateTime.now();
      final eski = [
        _lot(ticker: 'AAA', added: now.subtract(const Duration(days: 400)))
      ];
      final yeni = [
        _lot(ticker: 'BBB', added: now.subtract(const Duration(days: 2)))
      ];
      expect(_roi(eski), closeTo(20.0, 1e-9));
      expect(_roi(yeni), closeTo(20.0, 1e-9));
      expect(_roi(eski), _roi(yeni),
          reason: 'aynı işlemi yapan iki kişi aynı sırada olmalı');
    });

    test('formül: (değer − maliyet) / maliyet', () {
      // 10 adet, 100'den alındı, 150'ye çıktı → %50.
      final a = [_lot(ticker: 'X', qty: 10, buy: 100, current: 150)];
      expect(_roi(a), closeTo(50.0, 1e-9));
    });

    test('zarar NEGATİF döner', () {
      final a = [_lot(ticker: 'X', qty: 10, buy: 100, current: 80)];
      expect(_roi(a), closeTo(-20.0, 1e-9));
    });

    test('başabaş SIFIR', () {
      final a = [_lot(ticker: 'X', qty: 10, buy: 100, current: 100)];
      expect(_roi(a), closeTo(0.0, 1e-9));
    });
  });

  group('ortalama maliyet doğru hesaplanır', () {
    test('iki ayrı alım AĞIRLIKLI ortalamaya iner', () {
      // 10 adet 100'den + 10 adet 200'den = 20 adet, ort. maliyet 150.
      // Güncel 180 → (3600 − 3000) / 3000 = %20.
      final a = [
        _lot(ticker: 'X', qty: 10, buy: 100, current: 180),
        _lot(ticker: 'X', qty: 10, buy: 200, current: 180),
      ];
      expect(_roi(a), closeTo(20.0, 1e-9));
    });

    test('KOMİSYON maliyete girer', () {
      // Komisyon gerçekte cebinden çıkan paradır; maliyete dahil olmazsa
      // kullanıcı olduğundan kârlı görünür.
      final komisyonsuz = [_lot(ticker: 'X', qty: 10, buy: 100, current: 120)];
      final komisyonlu = [
        _lot(ticker: 'X', qty: 10, buy: 100, current: 120, commission: 100)
      ];
      expect(_roi(komisyonsuz)!, greaterThan(_roi(komisyonlu)!),
          reason: 'komisyon ödeyen daha az kârlıdır');
      // maliyet 1000 + 100 = 1100, değer 1200 → %9,09
      expect(_roi(komisyonlu), closeTo(9.0909, 0.001));
    });

    test('SATILAN miktar maliyetten düşer', () {
      // 20 aldı, 10 sattı → net 10 adet kalır.
      final a = [
        _lot(ticker: 'X', qty: 20, buy: 100, current: 120),
        _lot(
            ticker: 'X', qty: 10, buy: 100, current: 120, kind: AssetKind.sell),
      ];
      // Net 10 adet: maliyet 1000, değer 1200 → %20
      expect(_roi(a), closeTo(20.0, 1e-9));
    });

    test('SİLİNEN varlık hesaba girmez', () {
      final a = [
        _lot(ticker: 'X', qty: 10, buy: 100, current: 120),
        _lot(
            ticker: 'Y',
            qty: 10,
            buy: 100,
            current: 500,
            kind: AssetKind.deleteLog),
      ];
      // Yalnızca X sayılır → %20. Y sayılsaydı çok daha yüksek çıkardı.
      expect(_roi(a), closeTo(20.0, 1e-9));
    });
  });

  group('sınır durumları', () {
    test('maliyet 0 ise NULL — bölme tanımsız', () {
      // 0 döndürmek "başabaş" yanılgısı yaratırdı.
      final a = [_lot(ticker: 'X', qty: 10, buy: 0, current: 120)];
      expect(_roi(a), isNull);
    });

    test('boş portföy NULL', () {
      expect(_roi(const []), isNull);
    });

    test('computeROIDetailed boş listede null döner', () async {
      final r = await LeaderboardService.instance.computeROIDetailed(
        assets: const [],
        periodDays: 30,
        currentValueTRY: 0,
        toTRY: _toTRY,
      );
      expect(r.roi, isNull);
      expect(r.usedFallback, isFalse);
    });

    test('dönem uzunluğu sonucu DEĞİŞTİRMEZ', () async {
      // Metrik dönemden bağımsız; periodDays yalnızca önbellek anahtarı.
      final a = [_lot(ticker: 'X', qty: 10, buy: 100, current: 120)];
      final deger = LeaderboardService.instance.totalValueTRY(a, _toTRY);
      final sonuclar = <double?>[];
      for (final gun in [1, 7, 30, 365]) {
        final r = await LeaderboardService.instance.computeROIDetailed(
          assets: a,
          periodDays: gun,
          currentValueTRY: deger,
          toTRY: _toTRY,
        );
        sonuclar.add(r.roi);
      }
      expect(sonuclar.toSet().length, 1,
          reason: 'aynı portföy her dönemde aynı sonucu vermeli: $sonuclar');
    });
  });

  group('sıralama tutarlı', () {
    test('daha çok kazanan ÜSTTE', () {
      final az = [_lot(ticker: 'A', qty: 10, buy: 100, current: 110)]; // %10
      final cok = [_lot(ticker: 'B', qty: 10, buy: 100, current: 150)]; // %50
      expect(_roi(cok)!, greaterThan(_roi(az)!));
    });

    test('portföy BÜYÜKLÜĞÜ sıralamayı etkilemez', () {
      // Yüzde metriği: 1000 TL ile %20 kazanan, 1.000.000 TL ile %20
      // kazananla aynı sırada olmalı.
      final kucuk = [_lot(ticker: 'A', qty: 10, buy: 100, current: 120)];
      final buyuk = [_lot(ticker: 'B', qty: 10000, buy: 100, current: 120)];
      expect(_roi(kucuk), closeTo(_roi(buyuk)!, 1e-9));
    });
  });

  group('portföy ekranıyla AYNI sayı', () {
    test('leaderboard metriği gainLossPercentage ile örtüşür', () {
      // Kullanıcı yarışta gördüğü sayıyı kendi portföyünde de görmeli.
      // `PortfolioState.gainLossPercentage` = gainLoss / totalCost * 100.
      final a = [
        _lot(ticker: 'X', qty: 10, buy: 100, current: 130),
        _lot(ticker: 'Y', qty: 5, buy: 200, current: 190),
      ];
      final maliyet =
          LeaderboardService.instance.toplamMaliyetTRY(a, _toTRY); // 2000
      final deger =
          LeaderboardService.instance.totalValueTRY(a, _toTRY); // 2250
      final beklenen = ((deger - maliyet) / maliyet) * 100;
      expect(_roi(a), closeTo(beklenen, 1e-9));
    });
  });
}
