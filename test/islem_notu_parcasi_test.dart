import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/all_transactions_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/islem_notu.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Aramada yalnız notu yüzünden çıkan satırın not parçası (2026-11-11).
const _uid = 'user-1';

Asset _lot(String id, String name, String ticker, String notes, int gun) =>
    Asset(
      id: id,
      userId: _uid,
      name: name,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: notes,
      isManualPrice: false,
      currentPrice: 110,
      addedDate: DateTime(2026, 3, gun, 12),
    );

final _defter = [
  _lot('a', 'Türk Hava Yolları', 'THYAO.IS',
      'Ay sonu kenara koyduğum para, maaştan ayırdım ve bekletiyorum', 10),
  _lot('b', 'Maaş Fonu', 'MAAS', 'uzun vade', 9),
  _lot('c', 'Aselsan', 'ASELS.IS', '', 8),
];

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
  @override
  Future<PortfolioState> build() async => PortfolioState(assets: _defter);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

Future<void> _kur(WidgetTester tester, {double yazi = 1}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      partnersProvider.overrideWith(_FakePartners.new),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(yazi)),
        child: child!,
      ),
      home: const AllTransactionsScreen(
        allPartnerAssets: {},
        partners: [],
        initialView: '',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Ekrandaki not parçası metinleri (Text.rich düz metni).
Iterable<String> _parcalar(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.textSpan?.toPlainText() ?? '')
    .where((s) => s.contains('maaş') || s.contains('vade'));

void main() {
  group('islemNotuParcasi', () {
    test('baştaki eşleşme: önü boş, arkası kelime sınırında kesik', () {
      final p = islemNotuParcasi(
          'Maaştan ayırdım, kenarda dursun diye bir kenara koydum ve bekliyorum',
          'maaş')!;
      expect(p.once, '');
      expect(p.eslesen, 'Maaş');
      expect(p.basKesik, isFalse);
      expect(p.sonKesik, isTrue);
      expect(p.sonra, startsWith('tan ayırdım'));
      expect(p.sonra.endsWith(' '), isFalse);
    });

    test('ortadaki eşleşme: iki uç kesik, kelime ortasından başlamaz', () {
      final p = islemNotuParcasi(
          'Ay sonu kenara koyduğum para, maaştan ayırdım ve bekletiyorum '
          'çünkü yaz tatili için birikim yapıyorum bu sene',
          'maaş',
          sonBaglam: 12)!;
      expect(p.basKesik, isTrue);
      expect(p.sonKesik, isTrue);
      expect(p.eslesen, 'maaş');
      expect(p.once, 'koyduğum para, ');
      expect(p.sonra, 'tan ayırdım');
    });

    test('sondaki eşleşme: arkası boş, kesik değil', () {
      final p = islemNotuParcasi('Vade için, maaş', 'MAAŞ')!;
      expect(p.eslesen, 'maaş');
      expect(p.sonra, '');
      expect(p.sonKesik, isFalse);
      expect(p.basKesik, isFalse);
      expect(p.once, 'Vade için, ');
    });

    test('Türkçe İ/ı: "ışık" IŞIK\'ı, "iş" İŞ\'i bulur', () {
      expect(islemNotuParcasi('IŞIK hisse', 'ışık')!.eslesen, 'IŞIK');
      expect(islemNotuParcasi('İŞ BANKASI temettü', 'iş')!.eslesen, 'İŞ');
      expect(islemNotuParcasi('info notu', 'INFO')!.eslesen, 'info');
    });

    test('satır sonu tek boşluğa iner; boş ya da olmayan sorgu null', () {
      expect(islemNotuParcasi('bir\nmaaş', 'maaş')!.once, 'bir ');
      expect(islemNotuParcasi('maaş', '  '), isNull);
      expect(islemNotuParcasi('maaş', 'prim'), isNull);
    });

    test('islemNotuEslesir aynı kuralı kullanır', () {
      final a = _lot('x', 'X', 'X', 'IŞIK alımı', 1);
      expect(islemNotuEslesir(a, [a], 'ışık'), isTrue);
    });
  });

  group('Hareketler satırı', () {
    setUpAll(() async {
      await initializeDateFormatting('tr_TR');
      await initializeDateFormatting('en');
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
      DbLogger.silentInTests = true;
    });
    tearDownAll(() => DbLogger.silentInTests = false);

    testWidgets('boş aramada parça yok', (tester) async {
      await _kur(tester);
      expect(_parcalar(tester), isEmpty);
    });

    testWidgets('notta eşleşince parça görünür, adda eşleşince yok',
        (tester) async {
      await _kur(tester);
      await tester.enterText(find.byType(TextField), 'maaş');
      await tester.pumpAndSettle();
      // THYAO notu yüzünden, "Maaş Fonu" adıyla çıktı.
      expect(find.text('THYAO'), findsOneWidget);
      final p = _parcalar(tester).toList();
      expect(p, hasLength(1));
      expect(p.single, startsWith('… '));
      expect(p.single, contains('maaştan ayırdım'));
      expect(p.single, isNot(contains('uzun vade')));

      // Ekran okuyucu notun tamamını okur.
      expect(
          find.bySemanticsLabel(RegExp('maaştan ayırdım ve bekletiyorum')),
          findsOneWidget);
    });

    testWidgets('Dynamic Type 2×: taşma yok', (tester) async {
      await _kur(tester, yazi: 2);
      expect(tester.takeException(), isNull, reason: 'aramasız');
      await tester.enterText(find.byType(TextField), 'maaş');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_parcalar(tester), hasLength(1));
    });
  });
}
