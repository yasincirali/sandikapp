import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/widgets/quick_adjust_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Portföy kartı ve Hızlı Al/Sat — 2026-09-29 emülatör testi bulguları
/// #6, #8, #9, #22.
const _uid = 'user-1';

Asset _lot({
  required String id,
  required String ticker,
  required double adet,
  required double maliyet,
  required double fiyat,
  AssetType tur = AssetType.hisse,
  String birim = 'piece',
}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ticker,
      ticker: ticker,
      type: tur,
      quantity: adet,
      purchasePrice: maliyet,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 3, 14),
      unitType: birim,
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this._assets);
  final List<Asset> _assets;

  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _assets, usdTry: 42, eurTry: 46, gbpTry: 54);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

Future<void> _pumpPortfoy(WidgetTester tester, List<Asset> varliklar) async {
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(() => _FakePortfolio(varliklar)),
      partnersProvider.overrideWith(_FakePartners.new),
    ],
    child: MaterialApp(theme: ThemeData.dark(), home: const PortfolioScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Hızlı Al/Sat diyaloğunu gerçek giriş noktasından açar.
Future<void> _pumpDiyalog(
    WidgetTester tester, Asset varlik, QuickAdjustMode mod) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () =>
                showQuickAdjustDialog(context, ref, asset: varlik, mode: mod),
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
  });

  // ── #6: kartın kâr/zarar satırı yönü METİNDE yazar ──────────────────────
  group('#6 kart kâr/zarar satırı işaretli', () {
    testWidgets('zararda "−₺5 · −%2,23", kârda "+₺500 · +%20,00"',
        (tester) async {
      await _pumpPortfoy(tester, [
        _lot(id: 'a', ticker: 'ATATP.IS', adet: 1, maliyet: 224.5, fiyat: 219.5),
        _lot(id: 'b', ticker: 'THYAO.IS', adet: 10, maliyet: 250, fiyat: 300),
      ]);
      // Eski hâl: "₺5 · %2,23" — zarar yalnız renkten okunuyordu.
      expect(find.text('−₺5 · −%2,23'), findsOneWidget);
      expect(find.text('+₺500 · +%20,00'), findsOneWidget);
      expect(find.text('₺5 · %2,23'), findsNothing);
    });
  });

  // ── #8: açılır panel Türkçe büyük harf + l10n ───────────────────────────
  group('#8 açılır panel etiketleri', () {
    testWidgets('"MİKTAR", "ORT. MALİYET" — noktasız I yok', (tester) async {
      await _pumpPortfoy(tester, [
        _lot(id: 'b', ticker: 'THYAO.IS', adet: 10, maliyet: 250, fiyat: 300),
      ]);
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded).first);
      await tester.pumpAndSettle();
      for (final e in [
        'MİKTAR',
        'ORT. MALİYET',
        'TOPLAM MALİYET',
        'İLK ALIŞ',
        'GÜNCEL TUTAR',
      ]) {
        expect(find.text(e), findsOneWidget, reason: e);
      }
      for (final yanlis in ['MIKTAR', 'ORT. MALIYET', 'TOPLAM MALIYET']) {
        expect(find.text(yanlis), findsNothing, reason: yanlis);
      }
      // Tarih dile bağlı biçimden (sabit 'tr_TR' değil) — Türkçe'de aynı.
      expect(find.text('14 Mar 2026'), findsOneWidget);
    });
  });

  // ── #9: Hızlı Al/Sat miktar çipleri ─────────────────────────────────────
  group('#9 hızlı miktar önerileri', () {
    test('satış: eldekini aşan/eşit öneri yok', () {
      expect(
          hizliMiktarOnerileri(
              tur: AssetType.hisse, birimTuru: 'piece', eldeki: 1, satis: true),
          isEmpty,
          reason: '1 lotta 1 zaten "Hepsi"; 10/100/1000 satılamaz');
      expect(
          hizliMiktarOnerileri(
              tur: AssetType.hisse,
              birimTuru: 'piece',
              eldeki: 150,
              satis: true),
          [1, 10, 100]);
      expect(
          hizliMiktarOnerileri(
              tur: AssetType.altin, birimTuru: 'ounce', eldeki: 0.5, satis: true),
          [0.1]);
    });

    test('alış: türün makul adımları; kripto kesirli', () {
      expect(
          hizliMiktarOnerileri(
              tur: AssetType.fon, birimTuru: 'piece', eldeki: 1, satis: false),
          [1, 10, 100, 1000]);
      final kripto = hizliMiktarOnerileri(
          tur: AssetType.kripto, birimTuru: 'piece', eldeki: 0.01, satis: false);
      expect(kripto.every((v) => v <= 1), isTrue,
          reason: '100 BTC öneri olmaz: $kripto');
    });

    testWidgets('1 lotluk satışta TEK "Hepsi (1)", aşan çip yok',
        (tester) async {
      await _pumpDiyalog(
        tester,
        _lot(id: 'a', ticker: 'ATATP.IS', adet: 1, maliyet: 224.5, fiyat: 219.5),
        QuickAdjustMode.remove,
      );
      // Eski hâl: "Hepsi (1) | 10 | 100 | 1000 | Hepsi (1)".
      expect(find.text('Hepsi (1)'), findsOneWidget);
      for (final c in ['10', '100', '1000']) {
        expect(find.text(c), findsNothing, reason: c);
      }
      await tester.tap(find.text('Hepsi (1)'));
      await tester.pump();
      expect(find.widgetWithText(TextField, '1'), findsOneWidget);
    });

    testWidgets('ons çipi Türkçe ondalıkla yazar ("0,1", "0.1" değil)',
        (tester) async {
      await _pumpDiyalog(
        tester,
        _lot(
            id: 'o',
            ticker: 'XAUUSD',
            adet: 3,
            maliyet: 100,
            fiyat: 110,
            tur: AssetType.emtia,
            birim: 'ounce'),
        QuickAdjustMode.add,
      );
      expect(find.text('0,1'), findsOneWidget);
      expect(find.text('0.1'), findsNothing);
      expect(find.textContaining('Hepsi'), findsNothing,
          reason: 'alışta "Hepsi" anlamsız');
    });
  });

  // ── #22: Varlık Ekle formu kanonik birimi yazar ─────────────────────────
  group('#22 form birimi = kayıtlı varlık birimi', () {
    final durumlar = <({AssetType tur, String birim})>[
      (tur: AssetType.hisse, birim: 'piece'),
      (tur: AssetType.fon, birim: 'piece'),
      (tur: AssetType.altin, birim: 'gram'),
      (tur: AssetType.altin, birim: 'piece'),
      (tur: AssetType.emtia, birim: 'ounce'),
      (tur: AssetType.diger, birim: 'piece'),
    ];
    for (final d in durumlar) {
      test('${d.tur.name} + ${d.birim}', () {
        final form = AddAssetFormState.initial(prefillType: d.tur)
            .copyWith(unitType: d.birim);
        final kayitli = _lot(
                id: 'x',
                ticker: 'X',
                adet: 1,
                maliyet: 1,
                fiyat: 1,
                tur: d.tur,
                birim: d.birim)
            .unitLabel;
        // Eski hâl: hisse/fon formda "Adet", portföyde "lot".
        expect(form.quantitySuffix, kayitli);
      });
    }
  });
}
