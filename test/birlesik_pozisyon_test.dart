import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';

/// Portföy › "Birlikte" listesinde aynı varlık TEK satır.
///
/// **Kullanıcı bildirimi (2026-10-01):** "Neden KCHOL 2 defa gösterilmiş,
/// bu büyük bir hata." Birlikte listesi `aggregatePositionsByOwner`
/// çıktısını olduğu gibi basıyordu: ben 1.001 lot + ortak 620 lot → sahip
/// etiketi olmayan iki "KCHOL" satırı. Ortağın satırında kaydırma paneli de
/// yoktu (düzenlenemez), kullanıcı "kaydırma çalışmıyor" gördü.
///
/// Birleşme GÖRÜNÜMDE kalmalı: değer/maliyet parçaların TOPLAMI, tek
/// temsilcinin fiyatı herkese uygulanmaz (`partner_pnl_consistency_test`).

Asset _lot(
  String userId,
  String ticker, {
  required double qty,
  required double alis,
  required double fiyat,
  AssetType type = AssetType.hisse,
  String? sub,
  DateTime? tarih,
}) =>
    Asset(
      id: '$userId-$ticker-$qty-$alis-$sub',
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: alis,
      currency: 'TRY',
      notes: '',
      subCategory: sub,
      currentPrice: fiyat,
      addedDate: tarih ?? DateTime(2026, 1, 1),
    );

void main() {
  group('sahiplerArasiBirlestir', () {
    final ben = [
      _lot('ben', 'KCHOL.IS', qty: 1001, alis: 193, fiyat: 208.4),
      _lot('ben', 'ALTIN_GRAM', qty: 100, alis: 6000, fiyat: 6010,
          type: AssetType.altin, sub: '22 Ayar Gram Altın'),
    ];
    final ortak = [
      _lot('ortak', 'KCHOL.IS', qty: 620, alis: 145, fiyat: 208.4,
          tarih: DateTime(2026, 2, 1)),
    ];

    test('aynı varlık iki sahipte → tek satır, miktar ve değer toplam', () {
      final satirlar = sahiplerArasiBirlestir(
          aggregatePositionsByOwner([ben, ortak]));
      final kchol =
          satirlar.where((p) => p.representative.ticker == 'KCHOL.IS');
      expect(kchol, hasLength(1));
      final p = kchol.single;
      expect(p, isA<BirlesikPozisyon>());
      expect(p.totalQuantity, 1621);
      expect(p.totalValue, closeTo(1621 * 208.4, 1e-6));
      expect(p.totalCostTRY, closeTo(1001 * 193 + 620 * 145, 1e-6));
      // Liste anahtarı (`ValueKey(key)`) artık tekil.
      expect(satirlar.map((p) => p.key).toSet(), hasLength(satirlar.length));
    });

    test('kâr/zarar sahip başına hesapların toplamına eşit', () {
      final parcalar = aggregatePositionsByOwner([ben, ortak]);
      final birlesik = sahiplerArasiBirlestir(parcalar);
      double kz(Iterable<Position> ps) =>
          ps.fold(0.0, (s, p) => s + p.totalValue - p.totalCostTRY);
      expect(kz(birlesik), closeTo(kz(parcalar), 1e-6));
    });

    test('fiyatı çekilememiş sahip diğerinin fiyatıyla şişmez', () {
      // Temsilci en yeni lot (ortak) ve fiyatı 0 — tek temsilcinin fiyatı
      // herkese uygulansaydı benim 1.001 lotum da ₺0 görünürdü.
      final p = BirlesikPozisyon.parcalardan(aggregatePositionsByOwner([
        [_lot('ben', 'KCHOL.IS', qty: 1001, alis: 193, fiyat: 208.4)],
        [
          _lot('ortak', 'KCHOL.IS', qty: 620, alis: 145, fiyat: 0,
              tarih: DateTime(2026, 2, 1))
        ],
      ]));
      expect(p.representative.userId, 'ortak');
      expect(p.totalValue, closeTo(1001 * 208.4, 1e-6));
      // Satırdaki tutar (`asDisplayAsset().totalValue`) aynı sayı.
      expect(p.asDisplayAsset().totalValue, closeTo(p.totalValue, 1e-6));
    });

    test('kaydırma aksiyonu yalnız kendi parçasıyla çalışır', () {
      final p = sahiplerArasiBirlestir(aggregatePositionsByOwner([ben, ortak]))
          .whereType<BirlesikPozisyon>()
          .single;
      final benim = p.parcasi('ben')!;
      expect(benim.totalQuantity, 1001);
      expect(benim.lots.every((l) => l.userId == 'ben'), isTrue);
      expect(p.parcasi('yabanci'), isNull);
    });

    test('tek sahipli pozisyon olduğu gibi döner', () {
      final tek = aggregatePositions(ben);
      final sonuc = sahiplerArasiBirlestir(tek);
      expect(sonuc, hasLength(tek.length));
      for (var i = 0; i < tek.length; i++) {
        expect(identical(sonuc[i], tek[i]), isTrue);
      }
    });
  });

  group('altın alt türü anahtarı', () {
    test('CSV enum adı ile form etiketi aynı pozisyona düşer', () {
      // CSV 2026-10-01'e kadar `ceyrek`, form `Çeyrek Altın` yazıyordu:
      // aynı çeyrek altın Portföy'de iki satırdı.
      final csv = _lot('ben', 'ALTIN_CEYREK', qty: 15, alis: 9000, fiyat: 10544,
          type: AssetType.altin, sub: 'ceyrek');
      final form = _lot('ben', 'ALTIN_CEYREK', qty: 10, alis: 9500,
          fiyat: 10544, type: AssetType.altin, sub: 'Çeyrek Altın');
      expect(positionKey(csv), positionKey(form));
      final ps = aggregatePositions([csv, form]);
      expect(ps, hasLength(1));
      expect(ps.single.totalQuantity, 25);
    });

    test('farklı türler ayrı kalır; tanınmayan değer küçük harfe iner', () {
      expect(altinAltAnahtari('ceyrek'), 'çeyrek altın');
      expect(altinAltAnahtari('Yarım Altın') == altinAltAnahtari('ceyrek'),
          isFalse);
      expect(altinAltAnahtari(' Bilezik '), 'bilezik');
      expect(altinAltAnahtari(null), '');
    });
  });
}
