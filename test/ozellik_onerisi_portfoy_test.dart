import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/ozellik_onerisi_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/ozellik_onerisi.dart';
import 'package:portfoy_takip/widgets/ozellik_onerisi_karti.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Özellik önerisi Portföy sekmesinde de (yasin 2026-10-20 "oralara
/// koyalım"): aynı kart listenin üstünde, kapatınca kalkar.
const _uid = 'user-1';

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _Portfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(assets: [
        Asset(
          id: 'a',
          userId: _uid,
          name: 'THYAO',
          ticker: 'THYAO',
          type: AssetType.hisse,
          quantity: 10,
          purchasePrice: 300,
          currency: 'TRY',
          notes: '',
          isManualPrice: true,
          currentPrice: 300,
          addedDate: DateTime(2026, 3, 14),
        ),
      ], usdTry: 42, eurTry: 46, gbpTry: 54);
}

class _Ortaklar extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

Future<void> _ac(WidgetTester t, OzellikOnerisi? oneri) async {
  t.view.physicalSize = const Size(390 * 3, 1400 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_Auth.new),
      portfolioProvider.overrideWith(_Portfoy.new),
      partnersProvider.overrideWith(_Ortaklar.new),
      ozellikOnerisiProvider.overrideWithValue(oneri),
    ],
    child: MaterialApp(theme: ThemeData.dark(), home: const PortfolioScreen()),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  testWidgets('öneri varsa Portföy listesinin üstünde çıkar', (t) async {
    await _ac(t, OzellikOnerisi.alarm);
    expect(find.text('Fiyat alarmı kur'), findsOneWidget);
    // Varlık listesinin üstünde.
    final kart = t.getTopLeft(find.byType(OzellikOnerisiKarti)).dy;
    final satir = t.getTopLeft(find.textContaining('THYAO').first).dy;
    expect(kart, lessThan(satir));
  });

  testWidgets('öneri yoksa Portföy yerleşimi değişmez', (t) async {
    await _ac(t, null);
    expect(find.text('Fiyat alarmı kur'), findsNothing);
    expect(find.textContaining('THYAO'), findsWidgets);
    // Sıfır boylu satırı liste "görünmez" sayar; offstage dahil ara.
    final kart = find.byType(OzellikOnerisiKarti, skipOffstage: false);
    expect(kart, findsOneWidget);
    expect(t.getSize(kart).height, 0);
  });
}
