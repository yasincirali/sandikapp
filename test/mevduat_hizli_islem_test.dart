import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/mevduat_hesabi.dart';
import 'package:portfoy_takip/widgets/quick_adjust_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Vadeli mevduatta Hızlı Al/Sat TL tutarıyla çalışır (kullanıcı bildirimi,
/// 2026-10-08): *"Lot değil TL değeri alıyor olmalı; satış değeri direkt ne
/// yazıldıysa o."* Eskiden pay sorulup birim değerle çarpılıyordu —
/// ₺10.000 çekim ₺10.500 satış diye kaydediliyordu.

/// Birim değeri 1,05 olan (bir dönem faizi eklenmiş) ₺20.000 anaparalı
/// mevduat: 20.000 pay, bakiye ₺21.000.
Asset _mevduat() => Asset(
      id: 'm1',
      userId: 'u',
      name: 'Vadeli',
      ticker: 'MEVDUAT:abc',
      type: AssetType.mevduat,
      quantity: 20000,
      purchasePrice: 1.0,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 1.05,
      addedDate: DateTime(2026, 1, 1),
      sozlesmeId: 'abc',
    );

class _Kayit {
  double? alisPay, alisFiyat, satisPay, satisFiyat;
}

class _KaydedenPortfoy extends PortfolioNotifier {
  _KaydedenPortfoy(this.k);
  final _Kayit k;

  @override
  Future<PortfolioState> build() async => const PortfolioState();

  @override
  Future<void> addAsset({
    required String name,
    required String ticker,
    required AssetType type,
    required double quantity,
    required double purchasePrice,
    required String currency,
    required String notes,
    required bool isManualPrice,
    String? subCategory,
    String unitType = 'piece',
    DateTime? addedDate,
    double? initialCurrentPrice,
    double commission = 0,
    String? sozlesmeId,
  }) async {
    k
      ..alisPay = quantity
      ..alisFiyat = purchasePrice;
  }

  @override
  Future<void> addSellTransaction({
    required Asset asset,
    required double quantity,
    double? sellPrice,
    DateTime? addedDate,
  }) async {
    k
      ..satisPay = quantity
      ..satisFiyat = sellPrice;
  }
}

Future<_Kayit> _ac(WidgetTester tester, QuickAdjustMode mod) async {
  final k = _Kayit();
  await tester.pumpWidget(ProviderScope(
    overrides: [portfolioProvider.overrideWith(() => _KaydedenPortfoy(k))],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showQuickAdjustDialog(context, ref,
                asset: _mevduat(), mode: mod),
            child: const Text('ac'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ac'));
  await tester.pumpAndSettle();
  return k;
}

Future<void> _onayla(WidgetTester tester, String etiket) async {
  await tester.tap(find.widgetWithText(FilledButton, etiket));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
  });

  group('mevduatTutarIslemi', () {
    test('satış: yazılan tutar = satış değeri, pay = tutar / birim', () {
      final i = mevduatTutarIslemi(
          tutar: 10000, birim: 1.05, eldekiPay: 20000, satis: true)!;
      expect(i.pay * i.birim, closeTo(10000, 1e-9));
      expect(i.birim, 1.05);
    });

    test('alış: maliyet = yazılan tutar, anında kâr yok', () {
      final i = mevduatTutarIslemi(
          tutar: 5000, birim: 1.05, eldekiPay: 20000, satis: false)!;
      expect(i.pay * i.birim, closeTo(5000, 1e-9));
    });

    test('"Hepsi": kuruşa yuvarlı bakiye eldeki payın TAMAMINI satar', () {
      final i = mevduatTutarIslemi(
          tutar: 21000.12, birim: 1.0500061, eldekiPay: 20000, satis: true)!;
      expect(i.pay, 20000);
    });

    test('bakiyeyi aşan satış ve geçersiz giriş reddedilir', () {
      expect(
          mevduatTutarIslemi(
              tutar: 21500, birim: 1.05, eldekiPay: 20000, satis: true),
          isNull);
      expect(
          mevduatTutarIslemi(
              tutar: 0, birim: 1.05, eldekiPay: 20000, satis: false),
          isNull);
      expect(
          mevduatTutarIslemi(
              tutar: 100, birim: 0, eldekiPay: 20000, satis: false),
          isNull);
    });
  });

  group('Hızlı Al/Sat diyaloğu, mevduat', () {
    testWidgets('Sat: ₺10.000 yazınca satış değeri ₺10.000 kaydedilir',
        (tester) async {
      final k = await _ac(tester, QuickAdjustMode.remove);
      // Alan "Tutar" (₺), "Mevcut" satırı bakiye; pay/ort. fiyat yok.
      expect(find.text('Tutar'), findsOneWidget);
      expect(find.text('Miktar'), findsNothing);
      expect(find.textContaining('21.000,00'), findsWidgets);
      expect(find.textContaining('ort.'), findsNothing);

      await tester.enterText(find.byType(TextField), '10.000');
      await tester.pump();
      await _onayla(tester, 'Sat');
      expect(k.satisPay! * k.satisFiyat!, closeTo(10000, 1e-6),
          reason: 'eski hâl: 10.000 pay × 1,05 = ₺10.500');
    });

    testWidgets('Sat "Hepsi": eldeki payın tamamı satılır', (tester) async {
      final k = await _ac(tester, QuickAdjustMode.remove);
      await tester.tap(find.textContaining('Hepsi'));
      await tester.pump();
      await _onayla(tester, 'Sat');
      expect(k.satisPay, 20000);
    });

    testWidgets('Sat: bakiyeyi aşan tutar kaydedilmez', (tester) async {
      final k = await _ac(tester, QuickAdjustMode.remove);
      await tester.enterText(find.byType(TextField), '25.000');
      await tester.pump();
      await _onayla(tester, 'Sat');
      expect(k.satisPay, isNull);
      expect(find.textContaining('bakiyeyi'), findsOneWidget);
    });

    testWidgets('Al: birim fiyat alanı yok, maliyet = yazılan tutar',
        (tester) async {
      final k = await _ac(tester, QuickAdjustMode.add);
      expect(find.byType(TextField), findsOneWidget,
          reason: 'mevduatta birim fiyat sorulmaz');
      await tester.enterText(find.byType(TextField), '5.000');
      await tester.pump();
      await _onayla(tester, 'Al');
      expect(k.alisPay! * k.alisFiyat!, closeTo(5000, 1e-6));
      expect(k.alisFiyat, 1.05);
    });
  });
}
