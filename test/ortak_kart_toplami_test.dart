import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';

/// Ana ekrandaki iki kişi kartı AYNI şeyi ölçmeli.
///
/// ## Bug (2026-09-15)
/// "Ben" kartı `gosterilecekVarliklar` (= `positionedAssets`) üzerinden
/// net pozisyonu topluyordu; ortak kartı ham `isBuy` toplamı yapıyordu ve
/// **satışları düşmüyordu**. Ortak bir şey sattığında kartı şişik
/// görünüyor, iki kart farklı tanımla aynı görsel sınıfta yan yana
/// duruyordu.
///
/// Kart hesabı `home_screen`'in `build()`'i içinde inline olduğu için
/// doğrudan çağrılamıyor; burada hesabın DAYANDIĞI değişmez test edilir.
/// Kart kodu bu fonksiyondan saparsa yukarıdaki bug geri gelir.

Asset _lot({
  required String userId,
  required String ticker,
  required double qty,
  required double fiyat,
  AssetKind kind = AssetKind.buy,
  double? sellPrice,
}) =>
    Asset(
      id: '$userId-$ticker-${kind.name}-$qty',
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: fiyat,
      currentPrice: fiyat,
      currency: 'TRY',
      notes: '',
      kind: kind,
      sellPrice: sellPrice,
    );

double _kartToplami(Iterable<Asset> assets) =>
    gosterilecekVarliklar(assets).fold<double>(0, (s, a) => s + a.totalValue);

void main() {
  test('satış kart toplamından düşer — ham isBuy toplamı DEĞİL', () {
    final lotlar = [
      _lot(userId: 'ortak', ticker: 'THYAO', qty: 100, fiyat: 10),
      _lot(
        userId: 'ortak',
        ticker: 'THYAO',
        qty: 60,
        fiyat: 10,
        kind: AssetKind.sell,
        sellPrice: 12,
      ),
    ];

    // Ham isBuy toplamı 1000 verirdi (bug). Net 40 lot × 10 = 400.
    final hamIsBuyToplami = lotlar
        .where((a) => a.isBuy && a.isActive)
        .fold<double>(0, (s, a) => s + a.totalValue);
    expect(hamIsBuyToplami, 1000, reason: 'bug\'ın ürettiği şişik değer');

    expect(_kartToplami(lotlar), 400);
  });

  test('tamamen satılmış pozisyon karta 0 olarak girer', () {
    final lotlar = [
      _lot(userId: 'ortak', ticker: 'ASELS', qty: 50, fiyat: 20),
      _lot(
        userId: 'ortak',
        ticker: 'ASELS',
        qty: 50,
        fiyat: 20,
        kind: AssetKind.sell,
        sellPrice: 25,
      ),
    ];
    expect(_kartToplami(lotlar), 0);
  });

  test('yumuşak silinmiş lot karta girmez', () {
    final lotlar = [
      _lot(userId: 'ortak', ticker: 'GARAN', qty: 10, fiyat: 100),
      Asset(
        id: 'silinmis',
        userId: 'ortak',
        name: 'GARAN',
        ticker: 'GARAN',
        type: AssetType.hisse,
        quantity: 90,
        purchasePrice: 100,
        currentPrice: 100,
        currency: 'TRY',
        notes: '',
        deletedAt: DateTime(2026, 9, 1),
      ),
    ];
    expect(_kartToplami(lotlar), 1000);
  });

  /// Ortak-aggregation değişmezi: `positionKey` sahip taşımaz. İki ortağın
  /// lot'ları tek havuzda birleştirilirse aynı hisse tek pozisyona karışır
  /// ve BİRİNİN satışı DİĞERİNİN lot'unu düşer.
  test('ortaklar ayrı indirgenir — havuzlanınca satış çapraz bulaşır', () {
    // Sıla THYAO tutuyor ve HİÇ satmadı.
    final sila = [
      _lot(userId: 'sila', ticker: 'THYAO', qty: 100, fiyat: 10),
    ];
    // Kerem aynı hisseyi alıp TAMAMINI sattı — pozisyonu kapandı.
    final kerem = [
      _lot(userId: 'kerem', ticker: 'THYAO', qty: 40, fiyat: 10),
      _lot(
        userId: 'kerem',
        ticker: 'THYAO',
        qty: 40,
        fiyat: 10,
        kind: AssetKind.sell,
        sellPrice: 11,
      ),
    ];

    // Doğru: her ortak ayrı → Sıla 1000 + Kerem 0.
    expect(_kartToplami(sila), 1000);
    expect(_kartToplami(kerem), 0);
    final ayriToplam = _kartToplami(sila) + _kartToplami(kerem);
    expect(ayriToplam, 1000);

    // NOT: bu senaryoda havuzlama da 1000 verir — satılan miktar her iki
    // yolda bir kez düşüldüğü için TOPLAM korunur. Havuzlamanın zararı
    // toplamda değil, aşağıdaki iki yerde görünür.
    expect(_kartToplami([...sila, ...kerem]), 1000);
  });

  /// Havuzlamanın toplamı BOZDUĞU durum: bir ortağın satışı kendi
  /// lot'unu aşarsa, fazlası diğerinin lot'undan düşer.
  ///
  /// Sahada bu, düzeltme amaçlı girilen satış kaydıyla ya da lot'u
  /// silinip satışı kalan bir pozisyonla oluşur.
  test('satış kendi lot\'unu aşınca havuzlama diğer ortağı yer', () {
    final sila = [
      _lot(userId: 'sila', ticker: 'THYAO', qty: 100, fiyat: 10),
    ];
    // Kerem 40 aldı ama 90 satış kaydı var (kendi lot'unu aşıyor).
    final kerem = [
      _lot(userId: 'kerem', ticker: 'THYAO', qty: 40, fiyat: 10),
      _lot(
        userId: 'kerem',
        ticker: 'THYAO',
        qty: 90,
        fiyat: 10,
        kind: AssetKind.sell,
        sellPrice: 11,
      ),
    ];

    // Ayrı: Sıla'nın 1000'i Kerem'in fazla satışından etkilenmez.
    final ayriToplam = _kartToplami(sila) + _kartToplami(kerem);
    expect(ayriToplam, 1000);

    // Havuzlanmış: Kerem'in 50 fazla satışı Sıla'nın lot'undan düşer.
    final havuzToplam = _kartToplami([...sila, ...kerem]);
    expect(havuzToplam, lessThan(ayriToplam),
        reason: 'havuzlama çapraz bulaşma üretir — değişmezin nedeni budur');
  });
}
