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
    {bool yilGoster = true,
    bool silinenGorunumu = false,
    bool hideBalance = false,
    ({double once, double sonra})? portfoy,
    ({double once, double sonra})? bakiye}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: TransactionRow(
          asset: asset,
          portfolioState: const PortfolioState(),
          yilGoster: yilGoster,
          silinenGorunumu: silinenGorunumu,
          hideBalance: hideBalance,
          bakiye: bakiye,
          portfoyDegeri: portfoy,
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

  // Önceki → sonraki bakiye (kullanıcı isteği 2026-10-29): tarihin altında
  // ikinci satır, birim sonda; ekran okuyucuya tam cümle. Silme/temettü/
  // silinenler/mevduat satırında yazılmaz.
  group('hareket satırı — bakiye', () {
    const b = (once: 12.0, sonra: 17.5);

    testWidgets('alım: "12 → 17,5 lot" + erişilebilir cümle',
        (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, _asset(qty: 5.5), bakiye: b);
      expect(find.text('12 → 17,5 lot'), findsOneWidget);
      expect(find.bySemanticsLabel('Bakiye 12 lot iken 17,5 lot oldu'),
          findsOneWidget);
      h.dispose();
    });

    // Portföy önce → sonra (yasin 2026-10-29): miktarın yanında, "Portföy"
    // önekiyle, kompakt; ekran okuyucu tam tutarı tek cümlede okur.
    const p = (once: 1240000.0, sonra: 1210000.0);

    testWidgets('portföy değeri: kompakt görünür, tam okunur',
        (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, _asset(kind: AssetKind.sell, qty: 100),
          bakiye: (once: 400, sonra: 300), portfoy: p);
      expect(find.text('400 → 300 lot'), findsOneWidget);
      expect(find.text('· Portföy ₺1,24M → ₺1,21M'), findsOneWidget);
      expect(
          find.bySemanticsLabel('Bakiye 400 lot iken 300 lot oldu. '
              'Portföy ₺1.240.000 iken ₺1.210.000 oldu'),
          findsOneWidget);
      h.dispose();
    });

    testWidgets('bakiye gizliyken portföy değeri yazılmaz', (tester) async {
      await _pump(tester, _asset(),
          bakiye: (once: 400, sonra: 300), portfoy: p, hideBalance: true);
      expect(find.text('400 → 300 lot'), findsOneWidget);
      expect(find.textContaining('Portföy'), findsNothing);
    });

    testWidgets('portföy değeri yoksa yalnız miktar', (tester) async {
      await _pump(tester, _asset(), bakiye: (once: 400, sonra: 300));
      expect(find.textContaining('Portföy'), findsNothing);
    });

    testWidgets('bakiye verilmezse satır yok', (tester) async {
      await _pump(tester, _asset());
      expect(find.textContaining('→'), findsNothing);
    });

    testWidgets('döviz: sembol iki sayıda da önde', (tester) async {
      await _pump(
        tester,
        Asset(
          id: 'usd',
          userId: 'u1',
          name: 'Dolar',
          ticker: 'USDTRY=X',
          type: AssetType.doviz,
          quantity: 50,
          purchasePrice: 40,
          currency: 'TRY',
          notes: '',
          addedDate: DateTime(2026, 7, 24),
        ),
        bakiye: (once: 100, sonra: 150),
      );
      expect(find.text('\$100 → \$150'), findsOneWidget);
    });

    testWidgets('temettü, silme kaydı, silinmiş lot: yazılmaz',
        (tester) async {
      for (final a in [
        _asset(kind: AssetKind.dividend, qty: 0, dividend: 10),
        _asset(kind: AssetKind.deleteLog, qty: 0),
        _asset(deletedAt: DateTime(2026, 8, 1)),
      ]) {
        await _pump(tester, a, bakiye: b);
        expect(find.textContaining('→'), findsNothing, reason: a.kind.name);
      }
    });

    testWidgets('silinenler görünümünde yazılmaz', (tester) async {
      await _pump(tester, _asset(), silinenGorunumu: true, bakiye: b);
      expect(find.textContaining('→'), findsNothing);
    });

    testWidgets('mevduat: yazılmaz', (tester) async {
      await _pump(
        tester,
        Asset(
          id: 'mv',
          userId: 'u1',
          name: 'Mevduat',
          ticker: 'MEVDUAT:1',
          type: AssetType.mevduat,
          quantity: 100000,
          purchasePrice: 1,
          currency: 'TRY',
          notes: '',
          addedDate: DateTime(2026, 7, 24),
        ),
        bakiye: b,
      );
      expect(find.textContaining('→'), findsNothing);
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
