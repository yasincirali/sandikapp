// Hızlı Al ters hesabı: "Ortalamayı ₺X seviyesine indirmek için ~N"
// (Ar-Ge 2026-11-07 #3).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/quick_adjust_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BosPortfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => const PortfolioState();
}

Asset _varlik({
  AssetType tur = AssetType.hisse,
  double adet = 500,
  double maliyet = 100,
  double fiyat = 108.4,
  bool? maliyetBilinmiyor,
}) =>
    Asset(
      id: 'h1',
      userId: 'u',
      name: 'Deneme',
      ticker: 'DENEM',
      type: tur,
      quantity: adet,
      purchasePrice: maliyet,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 1, 1),
      maliyetBilinmiyor: maliyetBilinmiyor,
    );

Future<void> _ac(WidgetTester tester, Asset a, QuickAdjustMode mod) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
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

const _ac_ = ValueKey('hedef_ortalama_ac');
const _alan = ValueKey('hedef_ortalama_alani');
const _sonuc = ValueKey('hedef_ortalama_sonuc');

void main() {
  final tr = lookupAppLocalizations(const Locale('tr'));

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  group('hedefOrtalamaIcinAdet', () {
    double? f({
      double q = 10,
      double? a = 100,
      double? p = 80,
      double? t = 95,
      int ondalik = 0,
    }) =>
        hedefOrtalamaIcinAdet(
            eldeki: q, ortalama: a, fiyat: p, hedef: t, ondalik: ondalik);

    test('tam bölünen sonuç olduğu gibi', () {
      // 100 × (50 − 45) / (45 − 40) = 100.
      expect(f(q: 100, a: 50, p: 40, t: 45), 100);
    });

    test('lotta yukarı yuvarlanır; ortalama hedefin üstünde kalmaz', () {
      // 10 × 5 / 15 = 3,33 → 4 lot.
      final n = f()!;
      expect(n, 4);
      final yeni = yeniOrtalamaMaliyet(
          eskiAdet: 10, eskiMaliyet: 100, yeniAdet: n, fiyat: 80)!;
      expect(yeni, lessThanOrEqualTo(95));
      // Bir lot eksiği hedefe ulaşmaz.
      expect(
          yeniOrtalamaMaliyet(
              eskiAdet: 10, eskiMaliyet: 100, yeniAdet: n - 1, fiyat: 80)!,
          greaterThan(95));
    });

    test('kesirli birimde alanın hassasiyetine yukarı', () {
      expect(f(ondalik: 4), 3.3334);
      expect(f(ondalik: 2), 3.34);
    });

    test('yalnız p < t < a: aksi hâlde inilemez (null)', () {
      expect(f(t: 100), isNull, reason: 'hedef = ortalama');
      expect(f(t: 110), isNull, reason: 'hedef ortalamanın üstünde');
      expect(f(t: 80), isNull, reason: 'hedef = alış fiyatı');
      expect(f(t: 70), isNull, reason: 'hedef alış fiyatının altında');
      expect(f(p: 120, t: 95), isNull, reason: 'fiyat ortalamanın üstünde');
    });

    test('maliyet, eldeki, fiyat ya da hedef yoksa null', () {
      expect(f(a: null), isNull);
      expect(f(a: 0), isNull);
      expect(f(q: 0), isNull);
      expect(f(p: null), isNull);
      expect(f(p: 0), isNull);
      expect(f(t: null), isNull);
      expect(f(t: 0), isNull);
    });

    test('hassasiyet: BIST lotu tam, kesirli birimde azami ondalık', () {
      expect(hedefOrtalamaOndaligi(_varlik()), 0);
      expect(hedefOrtalamaOndaligi(_varlik(tur: AssetType.fon)),
          _varlik(tur: AssetType.fon).azamiOndalik);
    });
  });

  group('Hızlı Al sayfası', () {
    testWidgets('bağlantı 44 pt; açılınca alan, sonuç dokununca miktara',
        (tester) async {
      // Küçük sayılar: Ahem fontunda uzun "Toplam maliyet" tutarı taşmasın.
      await _ac(tester, _varlik(adet: 5, maliyet: 10, fiyat: 10.84),
          QuickAdjustMode.add);
      expect(find.byKey(_alan), findsNothing);
      expect(tester.getSize(find.byKey(_ac_)).height,
          greaterThanOrEqualTo(SandikTouch.min));
      await tester.ensureVisible(find.byKey(_ac_));
      await tester.tap(find.byKey(_ac_));
      await tester.pumpAndSettle();
      // Alış fiyatı 8: 5 × (10 − 9,5) / (9,5 − 8) = 1,67 → 2 lot.
      await tester.enterText(find.byType(TextField).at(1), '8');
      await tester.enterText(find.byKey(_alan), '9,5');
      await tester.pump();
      final metin = tester.widget<Text>(find.byKey(_sonuc)).data!;
      expect(metin, startsWith('Ortalamayı ₺9,50 seviyesine'));
      expect(metin, contains('~2 '));
      await tester.ensureVisible(find.byKey(_sonuc));
      await tester.tap(find.byKey(_sonuc));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField).first)
          .controller!.text, '2');
    });

    testWidgets('fiyat alanı bugünkü fiyatla dolu: hedefe inilemez',
        (tester) async {
      await _ac(tester, _varlik(), QuickAdjustMode.add);
      await tester.ensureVisible(find.byKey(_ac_));
      await tester.tap(find.byKey(_ac_));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_alan), '95');
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(_sonuc)).data,
          tr.quickTargetAvgUnreachable);
    });

    testWidgets('maliyeti bilinmeyen varlıkta yok', (tester) async {
      await _ac(tester, _varlik(maliyetBilinmiyor: true), QuickAdjustMode.add);
      expect(find.byKey(_ac_), findsNothing);
    });

    testWidgets('satışta yok', (tester) async {
      await _ac(tester, _varlik(), QuickAdjustMode.remove);
      expect(find.byKey(_ac_), findsNothing);
    });

    testWidgets('yeni pozisyonda (elde yok) yok', (tester) async {
      await _ac(tester, _varlik(adet: 0), QuickAdjustMode.add);
      expect(find.byKey(_ac_), findsNothing);
    });
  });
}
