import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';

/// Performans ekranındaki "TÜRE GÖRE DEĞİŞİM" kartının aritmetiği.
///
/// Kullanıcı isteği (2026-08-31): üstteki kart portföyün TOPLAMINI veriyor;
/// bu kart onu türlere ayırsın — "kazanç altından mı geldi, hisseden mi?".
/// Gerçek sekmesinde dönem içi alım/satım da belirtilsin.
///
/// **Düzeltme (2026-09-01):** ilk sürüm `totalValue − totalCostTRY` ile
/// ÖMÜRLÜK kâr gösteriyordu; periyot değiştirilse bile rakam hiç
/// değişmiyordu (kullanıcı yakaladı). Artık üstteki birikim kartıyla aynı
/// formül kullanılıyor — `(dönem sonu − dönem başı) / dönem başı` — sadece
/// tür tür ayrılmış hâli.
///
/// Kart widget'ı private olduğu için hesabın kendisi burada yeniden üretilir
/// (ekrandaki `_TypeBreakdownCardState` ile birebir aynı formüller).

Asset _lot({
  required String userId,
  required AssetType type,
  required double qty,
  required double buyPrice,
  required double currentPrice,
  required DateTime addedDate,
  AssetKind kind = AssetKind.buy,
  double? sellPrice,
  String ticker = 'X',
}) =>
    Asset(
      id: '$userId-${type.name}-$ticker-${kind.name}-$qty-$buyPrice',
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: buyPrice,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1.0,
      currentPrice: currentPrice,
      addedDate: addedDate,
      kind: kind,
      sellPrice: sellPrice,
    );

/// Kartın satır formülü: dönem başı/sonu değerinden değişim.
///
/// Ekranda `first`/`last` `HistoryService.getPortfolioHistory`'nin döndürdüğü
/// serinin ilk ve son noktasıdır. Burada ağ yok, o yüzden değerler doğrudan
/// veriliyor — kilitlenen şey serinin nasıl çekildiği değil, ondan sonraki
/// aritmetik.
({double change, double? pct}) _satir(
    {required double first, required double last}) {
  final change = last - first;
  return (change: change, pct: first > 0 ? (change / first) * 100 : null);
}

/// Dönem içi akış — ekrandaki `build` ile birebir aynı.
({Map<AssetType, double> flow}) _breakdown(
  List<List<Asset>> ownerLots, {
  required DateTime start,
  required DateTime end,
  required bool simulate,
}) {
  final flow = <AssetType, double>{};

  if (!simulate) {
    final startMs =
        DateTime(start.year, start.month, start.day).millisecondsSinceEpoch;
    final endMs = DateTime(end.year, end.month, end.day, 23, 59, 59)
        .millisecondsSinceEpoch;
    for (final lots in ownerLots) {
      for (final a in lots) {
        if (!a.isActive) continue;
        final ms = a.addedDate.millisecondsSinceEpoch;
        if (ms < startMs || ms > endMs) continue;
        final f = a.isBuy
            ? a.totalCostTRY
            : a.isSell
                ? -a.sellProceedsTRY
                : 0.0;
        if (f != 0) flow[a.type] = (flow[a.type] ?? 0) + f;
      }
    }
  }
  return (flow: flow);
}

void main() {
  setUpAll(() async => initializeDateFormatting('tr_TR'));

  final donemBasi = DateTime(2026, 6, 1);
  final donemSonu = DateTime(2026, 6, 30);

  group('satır formülü — DÖNEM değişimi', () {
    test('(son − ilk) / ilk', () {
      final r = _satir(first: 40000, last: 50000);
      expect(r.change, closeTo(10000, 0.01));
      expect(r.pct, closeTo(25, 0.001));
    });

    test('düşen türde NEGATİF', () {
      final r = _satir(first: 5000, last: 4000);
      expect(r.change, closeTo(-1000, 0.01));
      expect(r.pct, closeTo(-20, 0.001));
    });

    test('türler birbirinden bağımsız — biri kârda biri zararda olabilir', () {
      final altin = _satir(first: 40000, last: 50000);
      final hisse = _satir(first: 5000, last: 4000);
      expect(altin.change > 0 && hisse.change < 0, isTrue,
          reason: 'kart her türü ayrı ayrı göstermeli');
    });

    test('ÖMÜRLÜK kâr DEĞİL — asıl düzeltme', () {
      // Varlık 4000'den alınmış ve bugün 5000. Ömürlük kâr +%25.
      // Ama seçili dönem 4800 → 5000 ise dönem değişimi +%4,17'dir.
      // İlk sürüm periyottan bağımsız olarak hep %25 gösteriyordu.
      const omurlukMaliyet = 40000.0;
      final donem = _satir(first: 48000, last: 50000);
      final omurluk = _satir(first: omurlukMaliyet, last: 50000);

      expect(donem.pct, closeTo(4.167, 0.01));
      expect(omurluk.pct, closeTo(25, 0.01));
      expect(donem.pct == omurluk.pct, isFalse,
          reason: 'dönem rakamı ömürlük kârdan farklı olmalı');
    });

    test('periyot değişince rakam DEĞİŞİR', () {
      // Aynı varlık, iki farklı pencere → iki farklı sonuç.
      final haftalik = _satir(first: 49000, last: 50000);
      final yillik = _satir(first: 30000, last: 50000);
      expect(haftalik.pct, closeTo(2.04, 0.01));
      expect(yillik.pct, closeTo(66.67, 0.01));
      expect(haftalik.pct == yillik.pct, isFalse,
          reason: 'kartın periyoda duyarlı olmasının tanımı budur');
    });

    test('dönem başı sıfırsa yüzde hesaplanmaz', () {
      final r = _satir(first: 0, last: 500);
      expect(r.pct, isNull, reason: 'sıfıra bölme yok');
    });
  });

  group('dönem içi alım/satım satırı', () {
    test('GERÇEK modda dönem içi alım raporlanır', () {
      final lots = [
        [
          _lot(
              userId: 'me',
              type: AssetType.altin,
              qty: 10,
              buyPrice: 4000,
              currentPrice: 5000,
              addedDate: DateTime(2026, 6, 15)), // dönem İÇİ
        ],
      ];
      final b = _breakdown(lots,
          start: donemBasi, end: donemSonu, simulate: false);
      expect(b.flow[AssetType.altin], closeTo(40000, 0.01));
    });

    test('SİMÜLASYONDA akış satırı hiç hesaplanmaz', () {
      final lots = [
        [
          _lot(
              userId: 'me',
              type: AssetType.altin,
              qty: 10,
              buyPrice: 4000,
              currentPrice: 5000,
              addedDate: DateTime(2026, 6, 15)),
        ],
      ];
      final b = _breakdown(lots,
          start: donemBasi, end: donemSonu, simulate: true);
      expect(b.flow, isEmpty,
          reason: 'simülasyonda miktar sabit — "dönem içi alım" kavramı yok');
    });

    test('dönem DIŞI alım akışa girmez', () {
      final lots = [
        [
          _lot(
              userId: 'me',
              type: AssetType.altin,
              qty: 10,
              buyPrice: 4000,
              currentPrice: 5000,
              addedDate: DateTime(2026, 1, 10)), // dönem ÖNCESİ
        ],
      ];
      final b = _breakdown(lots,
          start: donemBasi, end: donemSonu, simulate: false);
      expect(b.flow[AssetType.altin] ?? 0, 0);
    });

    test('satış akışı NEGATİF', () {
      final lots = [
        [
          _lot(
              userId: 'me',
              type: AssetType.altin,
              qty: 10,
              buyPrice: 4000,
              currentPrice: 5000,
              addedDate: DateTime(2026, 1, 10)),
          _lot(
              userId: 'me',
              type: AssetType.altin,
              qty: 4,
              buyPrice: 4000,
              currentPrice: 5000,
              addedDate: DateTime(2026, 6, 20),
              kind: AssetKind.sell,
              sellPrice: 5000),
        ],
      ];
      final b = _breakdown(lots,
          start: donemBasi, end: donemSonu, simulate: false);
      expect(b.flow[AssetType.altin]!, lessThan(0),
          reason: 'satış cepten çıkış değil, cebe giriştir → negatif akış');
    });

    test('silinmiş lot akışa da toplama da girmez', () {
      final silinmis = _lot(
              userId: 'me',
              type: AssetType.altin,
              qty: 10,
              buyPrice: 4000,
              currentPrice: 5000,
              addedDate: DateTime(2026, 6, 15))
          .copyWithDeletedAt(DateTime(2026, 6, 20));
      final b = _breakdown([
        [silinmis]
      ], start: donemBasi, end: donemSonu, simulate: false);
      expect(b.flow[AssetType.altin] ?? 0, 0,
          reason: 'silinen lot "hiç olmamış" sayılır');
    });
  });

  group('tarih aralığı etiketi', () {
    // Ekran görüntüsünde 1Y periyodu "31 Ağu → 31 Ağu" görünüyordu: aralık
    // doğru (2025 → 2026) ama `d MMM` yılı gizlediği için aynı güne
    // bakılıyormuş gibi duruyordu.
    String etiket(DateTime s, DateTime e) {
      final f = DateFormat(s.year == e.year ? 'd MMM' : 'd MMM y', 'tr_TR');
      return '${f.format(s)} → ${f.format(e)}';
    }

    test('farklı yıllarda YIL yazılır', () {
      final s = DateTime(2025, 8, 31);
      final e = DateTime(2026, 8, 31);
      expect(etiket(s, e), contains('2025'));
      expect(etiket(s, e), contains('2026'));
      expect(etiket(s, e) == '31 Ağu → 31 Ağu', isFalse,
          reason: 'yıl gizlenirse aralık aynı güne bakıyormuş gibi görünür');
    });

    test('aynı yılda yıl YAZILMAZ — gereksiz gürültü', () {
      final s = DateTime(2026, 6, 1);
      final e = DateTime(2026, 6, 30);
      expect(etiket(s, e), '1 Haz → 30 Haz');
    });
  });
}
