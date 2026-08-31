import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// Gün içi ("GÜNLÜK" sekmesi) alım sıçraması — gerçek vs simülasyon.
///
/// Kullanıcı beklentisi (2026-08-31):
///   · **Gerçek** sekmesinde sabit değerli bir fon gün içinde alınırsa
///     grafik o anda YUKARI SIÇRAMALI (portföyde artık daha çok var).
///   · **Simülasyon** sekmesinde AYNI durumda sıçrama OLMAMALI, çünkü o
///     mod bugünkü net pozisyonu tüm gün boyunca sabit sayar.
///
/// Bu iki davranışın kaynağı `getPortfolioHistoryHourly` içindeki
/// `signedQtyOnSlot`: alım damgasından ÖNCEKİ slotlarda miktar 0, sonraki
/// slotlarda tam miktar. Fon (TEFAS) intraday NAV yayınlamadığı için birim
/// fiyat gün boyu sabittir — dolayısıyla değerdeki tek değişim MİKTARDAN
/// gelir ve sıçrama net görünür.
///
/// Ağ çağrısı yapmamak için burada o slot mantığının kendisi doğrulanır.

Asset _fon({
  required String id,
  required double qty,
  required double price,
  required DateTime addedDate,
  AssetKind kind = AssetKind.buy,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Sabit Fon',
      ticker: 'TEFAS:ABC',
      type: AssetType.fon,
      quantity: qty,
      purchasePrice: price,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1.0,
      currentPrice: price,
      addedDate: addedDate,
      kind: kind,
    );

const _slotMinutes = 5;

int _normalizeSlot(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final snapped = (d.minute ~/ _slotMinutes) * _slotMinutes;
  return DateTime(d.year, d.month, d.day, d.hour, snapped)
      .millisecondsSinceEpoch;
}

/// `history_service.dart` içindeki `signedQtyOnSlot` ile aynı kural.
double _signedQtyOnSlot(Asset a, int slotTs) {
  if (a.isQuantityNeutral) return 0.0;
  if (a.isDeleted) return 0.0;
  final addedTs = _normalizeSlot(a.addedDate.millisecondsSinceEpoch);
  if (addedTs > slotTs) return 0.0;
  return a.isSell ? -a.quantity : a.quantity;
}

/// GERÇEK mod: slot bazlı miktar × sabit fon fiyatı.
double _gercekDeger(List<Asset> lots, int slotTs) {
  double t = 0;
  for (final a in lots) {
    final q = _signedQtyOnSlot(a, slotTs);
    if (q == 0) continue;
    t += a.currentPrice * q;
  }
  return t;
}

/// SİMÜLASYON modu: bugünkü net pozisyon tüm gün sabit.
/// Ekran bunu `aggregatePositionsByOwner(...).asDisplayAsset()` ile kurar.
double _simulasyonDeger(List<Asset> lots, int _) {
  double t = 0;
  for (final p in aggregatePositions(lots)) {
    t += p.totalQuantity * p.representative.currentPrice;
  }
  return t;
}

void main() {
  final gun = DateTime(2026, 8, 31);
  int slot(int hour, [int minute = 0]) =>
      _normalizeSlot(DateTime(2026, 8, 31, hour, minute).millisecondsSinceEpoch);

  group('gün içi alım — GERÇEK sekmesi sıçramalı', () {
    test('sabit fiyatlı fonda alım anında değer sıçrar', () {
      // 10:00'da 100 adet var; 14:00'te 100 adet daha alınıyor.
      final lots = [
        _fon(
            id: 'l1',
            qty: 100,
            price: 10,
            addedDate: gun.add(const Duration(hours: 10))),
        _fon(
            id: 'l2',
            qty: 100,
            price: 10,
            addedDate: gun.add(const Duration(hours: 14))),
      ];

      expect(_gercekDeger(lots, slot(9)), 0, reason: 'ilk alımdan önce boş');
      expect(_gercekDeger(lots, slot(12)), 1000, reason: 'tek lot: 100×10');
      expect(_gercekDeger(lots, slot(15)), 2000,
          reason: 'ikinci alım sonrası iki katına çıkmalı — SIÇRAMA');
    });

    test('sıçrama tam alım slotunda başlar (sınır dahil)', () {
      final lots = [
        _fon(
            id: 'l1',
            qty: 100,
            price: 10,
            addedDate: gun.add(const Duration(hours: 14))),
      ];
      // 13:55 → henüz yok, 14:00 → var.
      expect(_gercekDeger(lots, slot(13, 55)), 0);
      expect(_gercekDeger(lots, slot(14)), 1000);
    });

    test('fiyat sabitken değişimin TEK kaynağı miktardır', () {
      // Fon NAV'ı gün içi sabit olduğu için sıçrama fiyat hareketiyle
      // karışmaz — bu, senaryonun sabit fonla verilmesinin sebebi.
      final lots = [
        _fon(
            id: 'l1',
            qty: 50,
            price: 20,
            addedDate: gun.add(const Duration(hours: 11))),
        _fon(
            id: 'l2',
            qty: 50,
            price: 20,
            addedDate: gun.add(const Duration(hours: 16))),
      ];
      final once = _gercekDeger(lots, slot(12));
      final sonra = _gercekDeger(lots, slot(17));
      expect(sonra - once, closeTo(1000, 0.001),
          reason: 'artış tamamen yeni lot\'tan gelmeli');
    });
  });

  group('gün içi alım — SİMÜLASYON sekmesi düz', () {
    test('aynı girdide simülasyon HİÇ sıçramaz', () {
      final lots = [
        _fon(
            id: 'l1',
            qty: 100,
            price: 10,
            addedDate: gun.add(const Duration(hours: 10))),
        _fon(
            id: 'l2',
            qty: 100,
            price: 10,
            addedDate: gun.add(const Duration(hours: 14))),
      ];

      // Bugünkü net pozisyon (200 adet) tüm gün boyunca sabit sayılır.
      final sabah = _simulasyonDeger(lots, slot(9));
      final ogle = _simulasyonDeger(lots, slot(12));
      final aksam = _simulasyonDeger(lots, slot(17));

      expect(sabah, 2000);
      expect(ogle, 2000);
      expect(aksam, 2000);
      expect(sabah, equals(aksam), reason: 'simülasyonda miktar sabit — düz');
    });

    test('iki mod aynı girdide FARKLI sonuç verir', () {
      // Bu ayrım kasıtlıdır; biri "ne oldu", diğeri "ne olurdu" sorusudur.
      final lots = [
        _fon(
            id: 'l1',
            qty: 100,
            price: 10,
            addedDate: gun.add(const Duration(hours: 14))),
      ];
      // Alımdan ÖNCEKİ bir slotta: gerçek 0, simülasyon tam pozisyon.
      expect(_gercekDeger(lots, slot(9)), 0);
      expect(_simulasyonDeger(lots, slot(9)), 1000);
    });

    test('gün sonunda iki mod aynı değere yakınsar', () {
      // Tüm alımlar geçtikten sonra gerçek de net pozisyona ulaşır.
      final lots = [
        _fon(
            id: 'l1',
            qty: 100,
            price: 10,
            addedDate: gun.add(const Duration(hours: 10))),
        _fon(
            id: 'l2',
            qty: 100,
            price: 10,
            addedDate: gun.add(const Duration(hours: 14))),
      ];
      expect(_gercekDeger(lots, slot(18)),
          closeTo(_simulasyonDeger(lots, slot(18)), 0.001));
    });

    test('smoothSpikes GERÇEK alım sıçramasını DÜZLEMEZ', () {
      // Risk: gün içi seride artefakt temizleyici (`smoothSpikes`) çalışıyor.
      // Alım sıçraması yanlışlıkla "veri artefaktı" sanılıp düzlenirse
      // kullanıcı beklediği sıçramayı göremez.
      //
      // Koruma: temizleyici yalnızca İKİ komşusundan da sapan AMA komşuları
      // birbiriyle uyuşan tek noktalık "V"yi düzler. Alım sıçraması bir
      // BASAMAKTIR (sonraki nokta da yüksek kalır), dolayısıyla
      // `prevNextGap` büyük olur ve koşul sağlanmaz.
      final seri = <int, double>{
        slot(13, 50): 1000,
        slot(13, 55): 1000,
        slot(14, 0): 2000, // alım — basamak başlıyor
        slot(14, 5): 2000,
        slot(14, 10): 2000,
      };
      smoothSpikes(seri, deviation: 0.003, neighborGap: 0.002);

      expect(seri[slot(14, 0)], 2000,
          reason: 'alım basamağı korunmalı — düzlenirse sıçrama kaybolur');
      expect(seri[slot(14, 10)], 2000);
    });

    test('smoothSpikes tek noktalık V artefaktını YİNE düzler', () {
      // Karşı taraf: koruma, artefakt temizliğini bozmamalı.
      final seri = <int, double>{
        slot(10, 0): 1000,
        slot(10, 5): 900, // veri eksikliği — komşular 1000'de uyuşuyor
        slot(10, 10): 1000,
      };
      smoothSpikes(seri, deviation: 0.003, neighborGap: 0.002);
      expect(seri[slot(10, 5)], 1000, reason: 'V artefaktı düzlenmeli');
    });

    test('satış simülasyonda net pozisyondan düşer', () {
      final lots = [
        _fon(
            id: 'l1',
            qty: 100,
            price: 10,
            addedDate: gun.add(const Duration(hours: 10))),
        _fon(
            id: 'l2',
            qty: 40,
            price: 10,
            addedDate: gun.add(const Duration(hours: 14)),
            kind: AssetKind.sell),
      ];
      // Net 60 adet → 600 TL, gün boyu sabit.
      expect(_simulasyonDeger(lots, slot(9)), 600);
      expect(_simulasyonDeger(lots, slot(17)), 600);
      // Gerçekte ise satıştan önce 1000, sonra 600.
      expect(_gercekDeger(lots, slot(12)), 1000);
      expect(_gercekDeger(lots, slot(15)), 600);
    });
  });
}
