import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/screens/comparison_screen.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';

/// Sadeleştirme 2, madde 8 — tek kıyas yüzeyi (`tek_kiyas_yuzeyi`).
///
/// Bayrak açıkken varlık ekranının "Karşılaştır" düğmesi kendi grafik içi
/// seçicisini (alt sayfa) açmaz; Karşılaştır ekranını BU varlık ve ekranın
/// seçili dönemi hazır açar. Bayrak kapalıyken birebir eski: alt sayfa.
/// Karşılaştır'da satır olamayan varlık (mevduat, BES, elle fiyat) bayrak
/// açıkken de eski seçicide kalır.

const _uid = 'user-1';

Asset _varlik({
  AssetType type = AssetType.hisse,
  String ticker = 'THYAO.IS',
  String name = 'Türk Hava Yolları',
  bool manuel = false,
}) =>
    Asset(
      id: 'V-1',
      userId: _uid,
      name: name,
      ticker: ticker,
      type: type,
      quantity: 100,
      purchasePrice: 250.75,
      currency: 'TRY',
      notes: '',
      isManualPrice: manuel,
      currentPrice: 312.40,
      addedDate: DateTime(2026, 3, 14),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test Kullanıcı',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this.varliklar);
  final List<Asset> varliklar;

  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: varliklar,
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

List<Override> _overrides(List<Asset> defter) => [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(() => _FakePortfolio(defter)),
    ];

void _yuzey(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> _varlikEkrani(WidgetTester tester, Asset v) async {
  _yuzey(tester);
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides([v]),
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: AssetDetailScreen(asset: v, showBackButton: true),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Varlık ekranının grafik altındaki "Karşılaştır" düğmesi.
Future<void> _karsilastiraBas(WidgetTester tester) async {
  final dugme = find.widgetWithText(InkWell, 'Karşılaştır');
  expect(dugme, findsOneWidget);
  await tester.ensureVisible(dugme);
  await tester.tap(dugme);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  group('varlık ekranı → kıyas', () {
    testWidgets('Karşılaştır ekranı bu varlık ve seçili dönemle açılır',
        (tester) async {
      await _varlikEkrani(tester, _varlik());
      // Varlık ekranında 1 ay seçilir; kıyas aynı pencereyle açılmalı.
      await tester.tap(find.text('1 ay').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _karsilastiraBas(tester);

      expect(find.byType(BottomSheet), findsNothing);
      final ekran = find.byType(ComparisonScreen);
      expect(ekran, findsOneWidget);
      final w = tester.widget<ComparisonScreen>(ekran);
      expect(w.baslangicVarligi?.ticker, 'THYAO.IS');
      expect(w.baslangicDonemi, SummaryPeriod.birAy);
      // Satır ilk karede seçili: boş hâl ("varlık ekle") hiç görünmez.
      expect(
          find.descendant(of: ekran, matching: find.text('THYAO.IS')),
          findsOneWidget);
      expect(find.text('Karşılaştırmak için varlık ekle'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('mevduat: grafik içi seçici kalır', (tester) async {
      final mevduat = _varlik(
          type: AssetType.mevduat,
          ticker: 'MEVDUAT:abc',
          name: 'Vadeli mevduat');
      expect(ComparisonScreen.varligiAcabilir(mevduat), isFalse);
      await _varlikEkrani(tester, mevduat);
      await _karsilastiraBas(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(ComparisonScreen), findsNothing);
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('varligiAcabilir', () {
    test('piyasa varlığı evet; sözleşmeli, elle fiyat ve diğer hayır', () {
      expect(ComparisonScreen.varligiAcabilir(_varlik()), isTrue);
      expect(
          ComparisonScreen.varligiAcabilir(
              _varlik(type: AssetType.fon, ticker: 'TEFAS:AFT')),
          isTrue);
      expect(
          ComparisonScreen.varligiAcabilir(
              _varlik(type: AssetType.bes, ticker: 'BES:x')),
          isFalse);
      expect(ComparisonScreen.varligiAcabilir(_varlik(manuel: true)), isFalse);
      expect(
          ComparisonScreen.varligiAcabilir(
              _varlik(type: AssetType.diger, ticker: 'EV')),
          isFalse);
    });
  });

  testWidgets('Karşılaştır ekranı parametresiz: eski açılış (3A, boş)',
      (tester) async {
    _yuzey(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(const []),
      child: const MaterialApp(home: ComparisonScreen()),
    ));
    await tester.pump();
    expect(find.text('Karşılaştırmak için varlık ekle'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });
}
