import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/all_transactions_screen.dart';
import 'package:portfoy_takip/widgets/transaction_row.dart';

/// Silinenler hareket akışından ayrılır (kullanıcı kararı 2026-09-29).
///
/// Ana sayfanın "Portföy hareketleri" yalnızca süren kayıtları gösterir;
/// "Tümünü gör" ekranında silinenler kendi alanında, alım ve silinme
/// tarihleriyle durur. İki yüzey de aynı fonksiyondan (`hareketleriAyir`)
/// beslenir.
Asset _kayit(
  String id, {
  AssetKind kind = AssetKind.buy,
  DateTime? eklendi,
  DateTime? silindi,
  String? ref,
  int deletedCount = 0,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 300,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      addedDate: eklendi ?? DateTime(2026, 3, 12),
      kind: kind,
      refAssetId: ref,
      deletedCount: deletedCount,
      deletedAt: silindi,
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('hareketleriAyir', () {
    test('damgalı lot silinenlere, damgasız aktiflere gider', () {
      final a = hareketleriAyir([
        _kayit('a', eklendi: DateTime(2026, 5, 1)),
        _kayit('s', silindi: DateTime(2026, 9, 3)),
      ]);
      expect(a.aktif.map((e) => e.id), ['a']);
      expect(a.silinen.map((e) => e.id), ['s']);
    });

    test('pozisyon silmesinin mezar taşı ikinci satır olmaz', () {
      // Yumuşak silme: lot'lar damgalı durur, taş onları anlatır.
      final a = hareketleriAyir([
        _kayit('l1', silindi: DateTime(2026, 9, 3)),
        _kayit('l2', silindi: DateTime(2026, 9, 3)),
        _kayit('t',
            kind: AssetKind.deleteLog,
            eklendi: DateTime(2026, 9, 3),
            deletedCount: 2),
      ]);
      expect(a.aktif, isEmpty);
      expect(a.silinen.map((e) => e.id), containsAll(['l1', 'l2']));
      expect(a.silinen.any((e) => e.isDeleteLog), isFalse);
    });

    test('fiziksel silmeden kalan taş (lot defterde yok) silinenlerde kalır',
        () {
      final a = hareketleriAyir([
        _kayit('t',
            kind: AssetKind.deleteLog,
            eklendi: DateTime(2026, 8, 1),
            ref: 'gitmis-lot'),
      ]);
      expect(a.silinen.map((e) => e.id), ['t']);
    });

    test('taşın andığı lot defterdeyse taş gizlenir', () {
      final a = hareketleriAyir([
        _kayit('l', silindi: DateTime(2026, 8, 1)),
        _kayit('t',
            kind: AssetKind.deleteLog, eklendi: DateTime(2026, 8, 1), ref: 'l'),
      ]);
      expect(a.silinen.map((e) => e.id), ['l']);
    });

    test('aktif yeni→eski eklenme, silinen yeni→eski silinme anına göre', () {
      final a = hareketleriAyir([
        _kayit('a1', eklendi: DateTime(2026, 1, 1)),
        _kayit('a2', eklendi: DateTime(2026, 6, 1)),
        // Eski alım ama YENİ silinmiş: silinenlerin başında.
        _kayit('s1',
            eklendi: DateTime(2025, 1, 1), silindi: DateTime(2026, 9, 20)),
        _kayit('s2',
            eklendi: DateTime(2026, 7, 1), silindi: DateTime(2026, 8, 1)),
      ]);
      expect(a.aktif.map((e) => e.id), ['a2', 'a1']);
      expect(a.silinen.map((e) => e.id), ['s1', 's2']);
    });
  });

  test('silinenler filtresi kapları SİLİNME ayına göre böler', () {
    // Mart'ta alınıp Eylül'de silinen kayıt Eylül kabındadır: liste silinme
    // anına göre sıralı, kap başka tarihe göre kesilirse aynı ay ikiye
    // bölünürdü.
    final silinen = hareketleriAyir([
      _kayit('s1',
          eklendi: DateTime(2026, 3, 12), silindi: DateTime(2026, 9, 3)),
      _kayit('s2',
          eklendi: DateTime(2026, 8, 20), silindi: DateTime(2026, 9, 1)),
      _kayit('s3',
          eklendi: DateTime(2026, 1, 5), silindi: DateTime(2026, 7, 10)),
    ]).silinen;
    final g = hareketleriAylaGrupla(silinen, tarih: silinmeAni);
    expect(g.map((e) => e.ay), [DateTime(2026, 9), DateTime(2026, 7)]);
    expect(g.first.kayitlar.map((e) => e.id), ['s1', 's2']);
  });

  group('TransactionRow — silinenler görünümü', () {
    Future<void> pump(WidgetTester tester, Asset asset) => tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: TransactionRow(
                asset: asset,
                portfolioState: const PortfolioState(),
                silinenGorunumu: true,
              ),
            ),
          ),
        );

    testWidgets('alım ve silinme tarihi birlikte yazılır', (tester) async {
      await pump(
          tester,
          _kayit('s',
              eklendi: DateTime(2026, 3, 12), silindi: DateTime(2026, 9, 3)));
      expect(find.textContaining('Alım: 12 Mar 2026'), findsOneWidget);
      expect(find.textContaining('Silinme: 3 Eyl 2026'), findsOneWidget);
      // Alanın başlığı zaten "Silinenler": "· silindi" eki ve soluklaştırma
      // tekrar olurdu.
      expect(find.textContaining('· silindi'), findsNothing);
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('mezar taşı yalnız silinme tarihini yazar', (tester) async {
      await pump(
          tester,
          _kayit('t',
              kind: AssetKind.deleteLog, eklendi: DateTime(2026, 8, 1)));
      expect(find.textContaining('Silinme: 1 Ağu 2026'), findsOneWidget);
      expect(find.textContaining('Alım:'), findsNothing);
    });
  });
}
