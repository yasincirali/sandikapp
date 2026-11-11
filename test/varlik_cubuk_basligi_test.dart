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

/// Varlık sayfası üst çubuk başlığı (Ar-Ge 11 Kas 19:04 #1): gövde başlığı
/// çubuğun altına girince çubukta "THYAO · <canlı fiyat>" belirir; başlık
/// görünürken çubuk boştur (iki kez yazılmaz). Hareketi azalt açıkken
/// soluklaşma süresi sıfırdır.

const _uid = 'user-1';

Asset _asset() => Asset(
      id: 'THYAO-1',
      userId: _uid,
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 100,
      purchasePrice: 250.75,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
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
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [_asset()],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

Future<void> _ac(WidgetTester tester, {bool hareketiAzalt = false}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: hareketiAzalt),
        child: child!,
      ),
      home: AssetDetailScreen(asset: _asset(), showBackButton: true),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

final _cubuk = find.byKey(const ValueKey('varlikCubukBasligi'));

AnimatedOpacity _saydamlik(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(_cubuk);

bool _semantiktenCikmis(WidgetTester tester) => tester
    .widget<ExcludeSemantics>(find
        .ancestor(of: _cubuk, matching: find.byType(ExcludeSemantics))
        .first)
    .excluding;

/// Çubuk başlığının metni — AppBar içinde aranır ki gövdedeki aynı
/// etiketle karışmasın.
Finder _cubukMetni() => find.descendant(
    of: find.byType(AppBar), matching: find.textContaining('THYAO · '));

Future<void> _asagiKaydir(WidgetTester tester) async {
  await tester.drag(find.text('Güncel fiyat'), const Offset(0, -500));
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  testWidgets('üstte: çubuk başlığı saydam ve semantikten çıkmış',
      (tester) async {
    await _ac(tester);
    expect(_saydamlik(tester).opacity, 0);
    // Gizliyken VoiceOver çubuktaki "THYAO · …"yu okumaz.
    expect(_semantiktenCikmis(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aşağı kaydırınca: kısa etiket + canlı fiyat belirir, '
      'yukarı dönünce kaybolur', (tester) async {
    await _ac(tester);
    // Fiyat gövdedeki büyük fiyatla AYNI dizge (tek kaynak).
    expect(_cubukMetni(), findsOneWidget);
    final metin = (tester.widget<Text>(_cubukMetni())).data!;
    expect(metin, startsWith('THYAO · '));
    expect(metin, contains('312,40'));

    await _asagiKaydir(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_saydamlik(tester).opacity, 1);
    expect(_saydamlik(tester).duration, greaterThan(Duration.zero));
    expect(_semantiktenCikmis(tester), isFalse);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_saydamlik(tester).opacity, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hareketi azalt: soluklaşma süresi sıfır', (tester) async {
    await _ac(tester, hareketiAzalt: true);
    await _asagiKaydir(tester);
    expect(_saydamlik(tester).opacity, 1);
    expect(_saydamlik(tester).duration, Duration.zero);
    expect(tester.takeException(), isNull);
  });
}
