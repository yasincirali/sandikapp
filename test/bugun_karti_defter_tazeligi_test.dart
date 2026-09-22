import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';

/// Kullanıcı bildirimi (2026-09-22): *"yeni bir alım yaptım, var olan
/// altınlara 10 çeyrek altın ekledim. Ana sayfada günlük kartında +311
/// oldu, günlük özette +378 oldu, günlük grafik +411 gösteriyor."*
///
/// ## Kök neden
/// `BugunKarti` gün içi serisini OTURUMDA BİR KEZ çekiyordu (`_istendi`
/// bayrağı). Bu, reel getiri ve haftalık satırı için doğru bir disiplin —
/// onlar defterden bağımsız. Ama gün içi seri DEFTERE bağlıdır: alımdan
/// sonra kart YENİ toplamı ESKİ gün başıyla kıyaslıyor ve aradaki farkı
/// "bugünün hareketi" diye yazıyordu.
///
/// `PortfolioNotifier` mutasyonda `IntradaySeriesCache`'i düşürüyor
/// (bkz. `denetim_2026_09_22_test` BUG1) ama kart önbelleğe bir daha
/// sormuyordu. Performans ekranı 30 sn'lik tick'iyle kendini toparladığı
/// için iki yüzey ayrışıyordu.
///
/// Bu test imzanın DAVRANIŞINI kilitler: miktar değişince tazeleme
/// tetiklenmeli, fiyat değişince TETİKLENMEMELİ (aksi halde 30 saniyede
/// bir boşuna ağ isteği atılır).
Asset _lot({
  required String id,
  String ticker = 'ALTIN_CEYREK',
  double qty = 10,
  double cur = 8000,
  AssetKind kind = AssetKind.buy,
  DateTime? deletedAt,
}) =>
    Asset(
      id: id,
      userId: 'ben',
      name: ticker,
      ticker: ticker,
      type: AssetType.altin,
      subCategory: ticker,
      quantity: qty,
      purchasePrice: 7500,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1,
      currentPrice: cur,
      addedDate: DateTime(2026, 1, 1),
      kind: kind,
      deletedAt: deletedAt,
    );

/// `_BugunKartiState._defterImzasi` ile AYNI kural.
///
/// Private olduğu için burada bire bir yeniden yazıldı. İkisi ayrışırsa bu
/// testler yanlış şeyi doğrular — imza kuralı değişirse BURASI da değişmeli.
String _imza(PortfolioState s) {
  final parcalar = [
    for (final a in s.assets)
      if (a.isActive) '${a.id}:${a.quantity}:${a.kind.name}',
  ]..sort();
  return parcalar.join('|');
}

void main() {
  group('defter imzası — TAZELEME tetiklenmeli', () {
    test('YENİ alım imzayı değiştirir (kullanıcının senaryosu)', () {
      // Elinde çeyrek altın varken 10 çeyrek daha ekledi.
      final once = PortfolioState(assets: [_lot(id: 'a1', qty: 10)]);
      final sonra = PortfolioState(assets: [
        _lot(id: 'a1', qty: 10),
        _lot(id: 'a2', qty: 10),
      ]);
      expect(_imza(once), isNot(_imza(sonra)),
          reason: 'alımdan sonra seri yeniden çekilmeli — '
              'yoksa yeni toplam ESKİ gün başıyla kıyaslanır');
    });

    test('satış imzayı değiştirir', () {
      final once = PortfolioState(assets: [_lot(id: 'a1', qty: 10)]);
      final sonra = PortfolioState(assets: [
        _lot(id: 'a1', qty: 10),
        _lot(id: 's1', qty: 4, kind: AssetKind.sell),
      ]);
      expect(_imza(once), isNot(_imza(sonra)));
    });

    test('miktar düzenlemesi imzayı değiştirir', () {
      // Aynı lot, `updateAsset` ile miktarı değişti.
      final once = PortfolioState(assets: [_lot(id: 'a1', qty: 10)]);
      final sonra = PortfolioState(assets: [_lot(id: 'a1', qty: 15)]);
      expect(_imza(once), isNot(_imza(sonra)));
    });

    test('silme imzayı değiştirir', () {
      final once = PortfolioState(assets: [
        _lot(id: 'a1', qty: 10),
        _lot(id: 'a2', qty: 5),
      ]);
      final sonra = PortfolioState(assets: [
        _lot(id: 'a1', qty: 10),
        _lot(id: 'a2', qty: 5, deletedAt: DateTime(2026, 9, 22)),
      ]);
      expect(_imza(once), isNot(_imza(sonra)),
          reason: 'silinen lot `isActive` değil — imzadan düşmeli');
    });

    test('temettü imzayı değiştirir (nakit akışı penceresine girer)', () {
      final once = PortfolioState(assets: [_lot(id: 'a1', qty: 10)]);
      final sonra = PortfolioState(assets: [
        _lot(id: 'a1', qty: 10),
        _lot(id: 'd1', qty: 0, kind: AssetKind.dividend),
      ]);
      expect(_imza(once), isNot(_imza(sonra)));
    });
  });

  group('defter imzası — TAZELEME tetiklenmemeli', () {
    test('FİYAT değişimi imzayı DEĞİŞTİRMEZ', () {
      // Bu kritik: `refreshPrices` defteri 30 saniyede bir yeniden
      // yayınlıyor. Fiyat imzaya girseydi her tick'te ağ isteği atılırdı.
      final ucuz = PortfolioState(assets: [_lot(id: 'a1', qty: 10, cur: 8000)]);
      final pahali =
          PortfolioState(assets: [_lot(id: 'a1', qty: 10, cur: 8250)]);
      expect(_imza(ucuz), _imza(pahali),
          reason: 'fiyat oynaması seriyi bayatlatmaz — boşuna istek atma');
    });

    test('lot SIRASI imzayı değiştirmez', () {
      // DB `added_date DESC` döner ama yerel mutasyon yeni lotu BAŞA
      // ekliyor. Sıra imzayı değiştirseydi her yeniden sıralama sahte
      // tazeleme tetiklerdi.
      final a = PortfolioState(assets: [
        _lot(id: 'a1', qty: 10),
        _lot(id: 'a2', qty: 5),
      ]);
      final b = PortfolioState(assets: [
        _lot(id: 'a2', qty: 5),
        _lot(id: 'a1', qty: 10),
      ]);
      expect(_imza(a), _imza(b), reason: 'imza sıralı — sıra önemsiz');
    });

    test('aynı defter iki kez: imza SABİT', () {
      final s = PortfolioState(assets: [
        _lot(id: 'a1', qty: 10),
        _lot(id: 'a2', qty: 5),
      ]);
      expect(_imza(s), _imza(s));
    });
  });
}
