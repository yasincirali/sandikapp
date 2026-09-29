import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/widgets/transaction_row.dart';

/// Hareket satırının içeriği — seçenek A "gruplu liste" (2026-09-28).
///
/// Tasarım kararı: satırda rozet YOK; işlem türü ve miktar sağ altta tek
/// metin ("Alım · 5 gr"), silinmiş lot aynı metnin sonuna "· silindi"
/// alır, temettüde miktar yazılmaz, silme kaydı sayı taşıyorsa "Silindi ·
/// n kayıt" yoksa düz "Silindi". Bu test o sözleşmeyi metin düzeyinde
/// sabitler; taşma ayrı testte (`transaction_row_overflow_test`).
Asset _asset({
  AssetKind kind = AssetKind.buy,
  double qty = 100,
  double dividend = 0,
  int deletedCount = 0,
  DateTime? deletedAt,
  DateTime? addedDate,
}) =>
    Asset(
      id: 'tx-${kind.name}-$qty-$deletedCount',
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: 300,
      sellPrice: 320,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 310,
      addedDate: addedDate ?? DateTime(2026, 7, 24, 14, 29),
      kind: kind,
      dividendAmount: dividend,
      deletedCount: deletedCount,
      deletedAt: deletedAt,
    );

Future<void> _pump(WidgetTester tester, Asset asset,
    {bool yilGoster = true}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: TransactionRow(
          asset: asset,
          portfolioState: const PortfolioState(),
          yilGoster: yilGoster,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('hareket satırı — sağ alt etiket', () {
    testWidgets('alım: tür + miktar tek metin', (tester) async {
      await _pump(tester, _asset());
      expect(find.textContaining('Alım · 100'), findsOneWidget);
      expect(find.textContaining('+₺'), findsOneWidget);
    });

    testWidgets('satım: "Satım · miktar", tutar eksi', (tester) async {
      await _pump(tester, _asset(kind: AssetKind.sell, qty: 10));
      expect(find.textContaining('Satım · 10'), findsOneWidget);
      expect(find.textContaining('−₺'), findsOneWidget);
    });

    testWidgets('temettü: miktar yazılmaz', (tester) async {
      await _pump(tester,
          _asset(kind: AssetKind.dividend, qty: 0, dividend: 1250));
      expect(find.text('Temettü'), findsOneWidget);
      expect(find.textContaining('0 adet'), findsNothing);
    });

    testWidgets('silme kaydı: sayı varsa "Silindi · n kayıt"',
        (tester) async {
      await _pump(tester, _asset(kind: AssetKind.deleteLog, deletedCount: 3));
      expect(find.text('Silindi · 3 kayıt'), findsOneWidget);
    });

    testWidgets('silme kaydı: tek kayıt ya da bilinmiyorsa düz "Silindi"',
        (tester) async {
      await _pump(tester, _asset(kind: AssetKind.deleteLog, deletedCount: 1));
      expect(find.text('Silindi'), findsOneWidget);
    });

    testWidgets('silinmiş lot: etiket sonuna "· silindi", satır soluk',
        (tester) async {
      await _pump(tester, _asset(deletedAt: DateTime(2026, 8, 1)));
      expect(find.textContaining('Alım · 100'), findsOneWidget);
      expect(find.textContaining('· silindi'), findsOneWidget);
      final op = tester.widget<Opacity>(find.byType(Opacity));
      expect(op.opacity, lessThan(1));
    });

    testWidgets('aktif satırda Opacity sarmalı yok', (tester) async {
      await _pump(tester, _asset());
      expect(find.byType(Opacity), findsNothing);
    });
  });

  group('hareket satırı — tarih', () {
    testWidgets('ana sayfa: yıl ve saat yazılır', (tester) async {
      await _pump(tester, _asset());
      expect(find.text('24 Tem 2026 · 14:29'), findsOneWidget);
    });

    testWidgets('ay kabında: yıl yazılmaz', (tester) async {
      await _pump(tester, _asset(), yilGoster: false);
      expect(find.text('24 Tem · 14:29'), findsOneWidget);
      expect(find.textContaining('2026'), findsNothing);
    });

    testWidgets('saat bilinmiyorsa yalnızca gün', (tester) async {
      await _pump(tester, _asset(addedDate: DateTime(2026, 7, 24)),
          yilGoster: false);
      expect(find.text('24 Tem'), findsOneWidget);
    });
  });

  testWidgets('ayraç girintisi avatar hizasından başlar', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Column(children: [HareketAyraci()]))));
    // Divider'ın kendi iç Padding'i de eşleşir; ayracın kendi sarmalı ilk.
    final pad = tester.widget<Padding>(find
        .descendant(of: find.byType(HareketAyraci), matching: find.byType(Padding))
        .first);
    expect(
      pad.padding,
      const EdgeInsets.only(
          left: TransactionRow.yatayBosluk +
              TransactionRow.avatarCap +
              TransactionRow.avatarAraligi),
    );
  });
}
