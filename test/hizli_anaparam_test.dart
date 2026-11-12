// Hızlı Sat "Anaparam" çipi (Ar-Ge 2026-11-12 #1, Premium): kârdaki
// pozisyonda maliyetin kadarını geri alacak miktar = toplam maliyet ÷
// güncel fiyat, yukarı yuvarlı, eldekine ulaşmaz.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/quick_adjust_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BosPortfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => const PortfolioState();
}

Asset _varlik({
  AssetType tur = AssetType.hisse,
  double adet = 100,
  double maliyet = 10,
  double fiyat = 16,
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

Future<void> _ac(
  WidgetTester tester,
  Asset a, {
  QuickAdjustMode mod = QuickAdjustMode.remove,
  bool gorunur = true,
  bool kilitli = false,
  double yazi = 1,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      portfolioProvider.overrideWith(_BosPortfoy.new),
      premiumOzellikleriGorunurProvider.overrideWithValue(gorunur),
      premiumKilitliProvider.overrideWithValue(kilitli),
    ],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(yazi)),
        child: child!,
      ),
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

Finder _cip(String baslangic) => find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').startsWith(baslangic));

void main() {
  final tr = lookupAppLocalizations(const Locale('tr'));

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
  });

  group('anaparamAdedi (saf)', () {
    test('kârda: toplam maliyet ÷ fiyat, yukarı yuvarlı', () {
      // 100 × 10 = 1.000 maliyet; 1.000 / 16 = 62,5 → 63 lot.
      expect(
          anaparamAdedi(eldeki: 100, ortalama: 10, fiyat: 16, ondalik: 0), 63);
      // Tam bölünende fazladan lot yok: 1.000 / 20 = 50.
      expect(
          anaparamAdedi(eldeki: 100, ortalama: 10, fiyat: 20, ondalik: 0), 50);
    });

    test('kesirli birimde türün hassasiyetine yukarı', () {
      // 3 gr × 2.000 = 6.000; 6.000 / 2.600 = 2,3077 → 2,31 (2 hane).
      expect(
          anaparamAdedi(eldeki: 3, ortalama: 2000, fiyat: 2600, ondalik: 2),
          2.31);
      expect(
          anaparamAdedi(eldeki: 3, ortalama: 2000, fiyat: 2600, ondalik: 4),
          2.3077);
    });

    test('zararda ve başa başta yok', () {
      expect(
          anaparamAdedi(eldeki: 100, ortalama: 10, fiyat: 8, ondalik: 0),
          isNull);
      expect(
          anaparamAdedi(eldeki: 100, ortalama: 10, fiyat: 10, ondalik: 0),
          isNull);
    });

    test('fiyat ya da maliyet yoksa yok (uydurma sayı yasak)', () {
      expect(
          anaparamAdedi(eldeki: 100, ortalama: 10, fiyat: null, ondalik: 0),
          isNull);
      expect(anaparamAdedi(eldeki: 100, ortalama: 10, fiyat: 0, ondalik: 0),
          isNull);
      expect(
          anaparamAdedi(eldeki: 100, ortalama: null, fiyat: 16, ondalik: 0),
          isNull);
      expect(anaparamAdedi(eldeki: 100, ortalama: 0, fiyat: 16, ondalik: 0),
          isNull);
      expect(anaparamAdedi(eldeki: 0, ortalama: 10, fiyat: 16, ondalik: 0),
          isNull);
    });

    test('eldekini aşmaz: yuvarlama eldekine ulaşırsa yok ("Hepsi" çipi)',
        () {
      // 1 lot × 10 / 12 = 0,83 → 1 = eldeki: kalan kâr pozisyonu olmaz.
      expect(anaparamAdedi(eldeki: 1, ortalama: 10, fiyat: 12, ondalik: 0),
          isNull);
      // 3 lot: 30 / 11 = 2,73 → 3 = eldeki.
      expect(anaparamAdedi(eldeki: 3, ortalama: 10, fiyat: 11, ondalik: 0),
          isNull);
      for (final f in [10.01, 11.0, 15.0, 40.0, 1000.0]) {
        final n = anaparamAdedi(eldeki: 7, ortalama: 10, fiyat: f, ondalik: 0);
        if (n != null) expect(n, lessThan(7));
      }
    });
  });

  group('Hızlı Sat çipi', () {
    testWidgets('kârda çip "Hepsi"den önce; seçilince miktar + açıklama',
        (tester) async {
      await _ac(tester, _varlik());
      final cip = _cip('Anaparam · 63');
      expect(cip, findsOneWidget);
      expect(tester.getTopLeft(cip).dx,
          lessThan(tester.getTopLeft(_cip(tr.quickAllChip('100'))).dx));
      // 44 pt dokunma alanı.
      final dokunma = find.ancestor(of: cip, matching: find.byType(SandikTappable));
      expect(tester.getSize(dokunma.first).height,
          greaterThanOrEqualTo(SandikTouch.min));
      expect(find.byKey(const ValueKey('anaparam_aciklama')), findsNothing);

      await tester.tap(cip);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField).first)
          .controller!.text, '63');
      // Kâr satırı gerçekleşen kârı söyler: (16 − 10) × 63 = 378.
      expect(find.byKey(const ValueKey('satis_kar_onizleme')), findsOneWidget);
      final aciklama = tester
          .widget<Text>(find.byKey(const ValueKey('anaparam_aciklama')))
          .data!;
      expect(aciklama, tr.quickPrincipalNote('₺1.008'));

      // Başka miktar yazılınca açıklama kalkar.
      await tester.enterText(find.byType(TextField).first, '10');
      await tester.pump();
      expect(find.byKey(const ValueKey('anaparam_aciklama')), findsNothing);
    });

    testWidgets('zararda, başa başta ve alışta çip yok', (tester) async {
      await _ac(tester, _varlik(fiyat: 8));
      expect(_cip('Anaparam'), findsNothing);
    });

    testWidgets('başa başta yok', (tester) async {
      await _ac(tester, _varlik(fiyat: 10));
      expect(_cip('Anaparam'), findsNothing);
    });

    testWidgets('alışta yok', (tester) async {
      await _ac(tester, _varlik(), mod: QuickAdjustMode.add);
      expect(_cip('Anaparam'), findsNothing);
    });

    testWidgets('maliyeti bilinmeyen lotta yok', (tester) async {
      await _ac(tester, _varlik(maliyetBilinmiyor: true));
      expect(_cip('Anaparam'), findsNothing);
    });

    testWidgets('paywall kapalıyken (Premium görünmez) çip yok',
        (tester) async {
      await _ac(tester, _varlik(), gorunur: false);
      expect(_cip('Anaparam'), findsNothing);
      // Bugünkü çip satırı birebir: 1, 10, Hepsi.
      expect(find.text(tr.quickAllChip('100')), findsOneWidget);
    });

    testWidgets('ücretsizde kilitli: sayı yok, kilit ikonu, 44 pt',
        (tester) async {
      await _ac(tester, _varlik(), kilitli: true);
      expect(find.text(tr.quickPrincipalChipLocked), findsOneWidget);
      expect(_cip('Anaparam · '), findsNothing);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      final dokunma = find.ancestor(
          of: find.text(tr.quickPrincipalChipLocked),
          matching: find.byType(SandikTappable));
      expect(tester.getSize(dokunma.first).height,
          greaterThanOrEqualTo(SandikTouch.min));
      expect(
          find.bySemanticsLabel(tr.quickPrincipalChipLockedSemantics),
          findsOneWidget);
    });

    testWidgets('2× yazıda taşma yok', (tester) async {
      await _ac(tester, _varlik(), yazi: 2);
      await tester.tap(_cip('Anaparam · 63'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('anaparam_aciklama')), findsOneWidget);
    });
  });
}
