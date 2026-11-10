import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/daily_summary.dart';

import 'helpers/kaynak.dart';

/// Performans › Bugün › "Türe göre · fiyat etkisi" › Altın (kullanıcı
/// bildirimi 2026-11-10): aynı anda Yarım −%0,31, Ata −%1,34, Çeyrek
/// −%0,75, 22 ayar −%2,70 görünüyordu; truncgil hepsine yaklaşık aynı
/// günlük değişimi diyordu. Satırın başı serinin taban slotundan (bir ayar
/// kayıttan, öbürü tohumdan), sonu `lot.currentPrice`'tan geliyordu.
///
/// Kilit: GÜNLÜK altın satırının başı ve sonu aynı kotasyondan
/// (`gunlukReferansFiyat` / `sonBilinenFiyat`); aynı günlük yüzdeyi taşıyan
/// ayarlar, lot zamanlaması ve fiyat düzeyi ne olursa olsun aynı yüzdeyi
/// gösterir.
void main() {
  Asset lot(
    String id,
    String ticker,
    double qty,
    double fiyat,
    DateTime t, {
    AssetKind kind = AssetKind.buy,
    AssetType type = AssetType.altin,
    double? bayatFiyat,
  }) =>
      Asset(
        id: id,
        userId: 'u',
        name: id,
        ticker: ticker,
        type: type,
        quantity: qty,
        purchasePrice: fiyat,
        sellPrice: kind == AssetKind.sell ? fiyat : null,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        // Defterdeki fiyat ayar başına farklı bayatlıkta olabilir — hesap
        // bunu OKUMAMALI.
        currentPrice: bayatFiyat ?? fiyat,
        addedDate: t,
        kind: kind,
      );

  final bugun = DateTime(2026, 11, 10);
  final acilis = DateTime(2026, 11, 10).millisecondsSinceEpoch;
  final simdi = DateTime(2026, 11, 10, 14);

  // Dört ayar, truncgil'de aynı günlük değişim: −%0,75.
  const pct = -0.75;
  const fiyatlar = <String, double>{
    'ALTIN_YARIM': 21000,
    'ALTIN_ATA': 43000,
    'ALTIN_CEYREK': 10500,
    'ALTIN_GRAM': 5300,
  };
  final referanslar = {
    for (final e in fiyatlar.entries) e.key: e.value / (1 + pct / 100),
  };
  double? ref(String t) => referanslar[t];
  double? canli(String t) => fiyatlar[t];

  // Kartın gösterdiği yüzde — `_TypeBreakdownCard._metricRow` ile aynı.
  double kartYuzdesi(({double first, double last}) uc, double akis) {
    final pnl = uc.last - uc.first - akis;
    final taban = uc.first + (akis > 0 ? akis : 0);
    return pnl / taban * 100;
  }

  ({double first, double last})? uclar(List<Asset> lotlar,
          {DateTime? seans}) =>
      DailySummary.gunIciAltinUclari(lotlar,
          acilisMs: acilis,
          seansGunu: seans ?? bugun,
          now: simdi,
          referans: ref,
          fiyat: canli);

  double akis(List<Asset> lotlar) => DailySummary.gunIciKatki(lotlar,
      acilisMs: acilis, seansGunu: bugun, now: simdi);

  test('aynı günlük yüzdeli dört ayar aynı yüzdeyi gösterir', () {
    final pozisyonlar = <String, List<Asset>>{
      // Eski alım, defter fiyatı bayat.
      'ALTIN_YARIM': [
        lot('y', 'ALTIN_YARIM', 3, 18000, DateTime(2026, 3, 1),
            bayatFiyat: 20500),
      ],
      // Kısmi satış dahil.
      'ALTIN_ATA': [
        lot('a1', 'ALTIN_ATA', 4, 30000, DateTime(2025, 6, 1)),
        lot('a2', 'ALTIN_ATA', 1, 40000, DateTime(2026, 10, 1),
            kind: AssetKind.sell),
      ],
      'ALTIN_CEYREK': [
        lot('c', 'ALTIN_CEYREK', 20, 9000, DateTime(2026, 1, 1),
            bayatFiyat: 10900),
      ],
      'ALTIN_GRAM': [
        lot('g', 'ALTIN_GRAM', 50, 4000, DateTime(2025, 1, 1)),
      ],
    };
    for (final e in pozisyonlar.entries) {
      final uc = uclar(e.value);
      expect(uc, isNotNull, reason: e.key);
      expect(kartYuzdesi(uc!, akis(e.value)), closeTo(pct, 1e-9),
          reason: e.key);
    }

    // Tür başlığı = ürün satırlarının toplamı (açılan tür başlığı tutar).
    final hepsi = [for (final l in pozisyonlar.values) ...l];
    final tur = uclar(hepsi)!;
    final cocuklar = [for (final l in pozisyonlar.values) uclar(l)!];
    expect(tur.first,
        closeTo(cocuklar.fold<double>(0, (s, u) => s + u.first), 1e-6));
    expect(tur.last,
        closeTo(cocuklar.fold<double>(0, (s, u) => s + u.last), 1e-6));
    expect(kartYuzdesi(tur, akis(hepsi)), closeTo(pct, 1e-9));
  });

  test('bugün alınan lot başta değil, katkıda', () {
    final lotlar = [
      lot('eski', 'ALTIN_CEYREK', 10, 9000, DateTime(2026, 1, 1)),
      lot('bugun', 'ALTIN_CEYREK', 10, 10500, DateTime(2026, 11, 10, 11)),
    ];
    final uc = uclar(lotlar)!;
    expect(uc.first, closeTo(10 * referanslar['ALTIN_CEYREK']!, 1e-6));
    expect(uc.last, closeTo(20 * 10500, 1e-6));
    // Alım bugünkü fiyattan: piyasa etkisi yalnız eski 10 adedin günlük
    // değişimi.
    final a = akis(lotlar);
    expect(a, closeTo(10 * 10500, 1e-6));
    expect(uc.last - uc.first - a,
        closeTo(10 * (10500 - referanslar['ALTIN_CEYREK']!), 1e-6));
  });

  test('ya hep ya hiç: tek ayarın referansı yoksa küme eski yola düşer', () {
    final lotlar = [
      lot('c', 'ALTIN_CEYREK', 10, 9000, DateTime(2026, 1, 1)),
      lot('r', 'ALTIN_RESAT', 1, 40000, DateTime(2026, 1, 1)),
    ];
    // Reşat'ın referansı ve fiyatı yok — sayı uydurulmaz.
    expect(uclar(lotlar), isNull);
  });

  test('altın dışı küme, geçmiş seans ve boş küme null', () {
    expect(
        uclar([
          lot('h', 'THYAO.IS', 10, 300, DateTime(2026, 1, 1),
              type: AssetType.hisse),
        ]),
        isNull);
    expect(
        uclar([lot('c', 'ALTIN_CEYREK', 10, 9000, DateTime(2026, 1, 1))],
            seans: DateTime(2026, 11, 7)),
        isNull);
    expect(uclar(const []), isNull);
  });

  test('kart tür ve ürün satırında aynı uçları kullanır', () {
    final kaynak = ekranKaynagiSync(
        'lib/screens/portfolio_performance_screen.dart');
    expect(kaynak, contains('widget.gunIciUclar?.call(turLot)'));
    expect(kaynak, contains('widget.gunIciUclar!(pozLot)'));
    expect(kaynak, contains('DailySummary.gunIciAltinUclari('));
  });
}
