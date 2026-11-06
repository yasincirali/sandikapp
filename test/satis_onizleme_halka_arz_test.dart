// Hızlı Sat kâr/zarar önizlemesi + Halka arz girişinin bayatlık kuralı
// (Ar-Ge 6 Kas 20:04). Saf fonksiyonlar testte saatten ve ağdan bağımsız.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/halka_arz_service.dart';
import 'package:portfoy_takip/widgets/quick_adjust_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BosPortfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => const PortfolioState();
}

Asset _hisse({double maliyet = 100, double fiyat = 108.4}) => Asset(
      id: 'h1',
      userId: 'u',
      name: 'Deneme',
      ticker: 'DENEM',
      type: AssetType.hisse,
      quantity: 500,
      purchasePrice: maliyet,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 1, 1),
    );

Future<void> _ac(WidgetTester tester, Asset a, QuickAdjustMode mod) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [portfolioProvider.overrideWith(_BosPortfoy.new)],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () =>
                showQuickAdjustDialog(context, ref, asset: a, mode: mod),
            child: const Text('ac'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ac'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  group('satisKarOnizleme', () {
    test('kâr: (satış − ortalama maliyet) × miktar', () {
      final k = satisKarOnizleme(
          miktar: 100, satisFiyati: 108.4, ortalamaMaliyet: 100)!;
      expect(k.tutar, closeTo(840, 1e-9));
      expect(k.yuzde, closeTo(8.4, 1e-9));
      expect(k.zarar, isFalse);
    });

    test('zarar: negatif tutar ve yüzde', () {
      final k = satisKarOnizleme(
          miktar: 10, satisFiyati: 90, ortalamaMaliyet: 100)!;
      expect(k.tutar, closeTo(-100, 1e-9));
      expect(k.yuzde, closeTo(-10, 1e-9));
      expect(k.zarar, isTrue);
    });

    test('miktar boş ya da 0 → satır yok', () {
      expect(
          satisKarOnizleme(
              miktar: 0, satisFiyati: 110, ortalamaMaliyet: 100),
          isNull);
      expect(
          satisKarOnizleme(
              miktar: null, satisFiyati: 110, ortalamaMaliyet: 100),
          isNull);
    });

    test('maliyet ya da fiyat bilinmiyor → null (uydurma sayı yok)', () {
      expect(
          satisKarOnizleme(miktar: 5, satisFiyati: 110, ortalamaMaliyet: 0),
          isNull);
      expect(
          satisKarOnizleme(
              miktar: 5, satisFiyati: 110, ortalamaMaliyet: null),
          isNull);
      expect(
          satisKarOnizleme(miktar: 5, satisFiyati: 0, ortalamaMaliyet: 100),
          isNull);
    });
  });

  group('Hızlı Sat sayfası', () {
    testWidgets('satışta miktar yazılınca kâr satırı görünür', (tester) async {
      await _ac(tester, _hisse(), QuickAdjustMode.remove);
      final satir = find.byKey(const ValueKey('satis_kar_onizleme'));
      expect(satir, findsNothing);
      await tester.enterText(find.byType(TextField).first, '100');
      await tester.pump();
      expect(satir, findsOneWidget);
      expect(tester.widget<Text>(satir).data,
          'Bu satıştan kâr +₺840 · +%8,4');
    });

    testWidgets('zararda "zarar" ve eksi işareti', (tester) async {
      await _ac(tester, _hisse(fiyat: 90), QuickAdjustMode.remove);
      await tester.enterText(find.byType(TextField).first, '10');
      await tester.pump();
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('satis_kar_onizleme')))
              .data,
          'Bu satıştan zarar −₺100 · −%10,0');
    });

    testWidgets('alışta satır yok', (tester) async {
      // Fiyat alanı boşaltılır: test fontu (Ahem) geniş, var olan "Toplam
      // maliyet" satırı uzun tutarla dar diyalogda taşıyor (bu testin
      // konusu değil).
      await _ac(tester, _hisse(), QuickAdjustMode.add);
      await tester.enterText(find.byType(TextField).at(1), '');
      await tester.enterText(find.byType(TextField).first, '1');
      await tester.pump();
      expect(find.byKey(const ValueKey('satis_kar_onizleme')), findsNothing);
    });
  });

  group('halkaArzBayatMi', () {
    final simdi = DateTime(2026, 11, 6);
    test('20 gün taze', () {
      expect(halkaArzBayatMi(DateTime(2026, 10, 17), simdi), isFalse);
    });
    test('21 gün hâlâ taze', () {
      expect(halkaArzBayatMi(DateTime(2026, 10, 16), simdi), isFalse);
    });
    test('22 gün bayat', () {
      expect(halkaArzBayatMi(DateTime(2026, 10, 15), simdi), isTrue);
    });
    test('tarih bilinmiyorsa bayat', () {
      expect(halkaArzBayatMi(null, simdi), isTrue);
    });
  });
}
