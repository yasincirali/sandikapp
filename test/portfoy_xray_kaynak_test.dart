import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/fon_xray_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/screens/portfoy_xray_screen.dart';
import 'package:portfoy_takip/services/fon_dagilimi.dart';
import 'package:portfoy_takip/services/portfoy_xray.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Portföy X-Ray kaynak sayfası: satır = gezinme (Ar-Ge 14 Kas #2, #5).
///
/// Kilitlenen: pozisyonu çözülen satır dokunulabilir, ≥44 pt, ok ve
/// "… Varlık sayfasını aç" etiketiyle; dokununca sayfa kapanır ve varlık
/// sayfası açılır. Çözülemeyen satır düz kalır. Başlık w600.
const _uid = 'ben';

Asset _lot(String ticker, AssetType tur, {double fiyat = 100}) => Asset(
      id: '$_uid-$ticker',
      userId: _uid,
      name: '$ticker adı',
      ticker: ticker,
      type: tur,
      quantity: 20,
      purchasePrice: fiyat,
      currentPrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      addedDate: DateTime(2026, 9, 1),
    );

class _Oturum extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
      id: _uid,
      email: 'ben@example.com',
      displayName: 'Ben',
      createdAt: DateTime(2026, 1, 1));
}

class _Portfoy extends PortfolioNotifier {
  _Portfoy(this.lotlar);
  final List<Asset> lotlar;
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: lotlar, usdTry: 40, ownerId: _uid);
}

class _Ortaklar extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _Gozcu extends NavigatorObserver {
  final adlar = <String?>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      adlar.add(route.settings.name);
}

void main() {
  setUp(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  final fon = _lot('TEFAS:AAL', AssetType.fon);
  final pozisyon = aggregatePositions([fon]).single;

  PortfoyXray xray() => PortfoyXray(
        toplam: 4000,
        kovalar: const {XrayKova.bistHisse: 3000, XrayKova.mevduat: 1000},
        xrayDisi: 0,
        xrayDisiFonlar: const [],
        fonTarihleri: null,
        ortusmeler: const [],
        kalemDonemi: null,
        gorunen: const {AssetType.fon: 2000, AssetType.hisse: 2000},
        kaynaklar: const {
          XrayKova.bistHisse: {'AAL': 1000, 'THYAO': 2000},
        },
        // THYAO çözülemiyor (aynı adı iki pozisyon veriyormuş gibi):
        // satırı düz kalmalı.
        kaynakPozisyonlari: {'AAL': pozisyon},
      );

  Future<_Gozcu> kur(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final gozcu = _Gozcu();
    await t.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_Oturum.new),
        portfolioProvider.overrideWith(() => _Portfoy([fon])),
        partnersProvider.overrideWith(_Ortaklar.new),
        premiumOzellikleriGorunurProvider.overrideWithValue(false),
        premiumKilitliProvider.overrideWithValue(false),
        xrayFonPayiProvider.overrideWithValue(null),
        portfoyXrayProvider.overrideWithValue(AsyncValue.data(xray())),
      ],
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        navigatorObservers: [gozcu],
        home: const PortfoyXrayScreen(),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('BIST hisse'));
    await t.pumpAndSettle();
    return gozcu;
  }

  Finder dokunulur(String ad) =>
      find.ancestor(of: find.text(ad), matching: find.byType(SandikTappable));

  testWidgets('çözülen satır: 44 pt, ok, etiket; çözülemeyen düz', (t) async {
    await kur(t);
    expect(find.text('Bu paranın nereden geldiği'), findsOneWidget);

    expect(dokunulur('AAL'), findsOneWidget);
    expect(t.getSize(dokunulur('AAL')).height,
        greaterThanOrEqualTo(SandikTouch.min));
    expect(find.bySemanticsLabel('AAL, ₺1.000. Varlık sayfasını aç.'),
        findsOneWidget);
    expect(
        find.descendant(
            of: dokunulur('AAL'),
            matching: find.byIcon(Icons.chevron_right_rounded)),
        findsOneWidget);

    // THYAO: dokunma yüzeyi ve ok yok.
    expect(dokunulur('THYAO'), findsNothing);

    // Başlık w600 (tavan; eskiden w700).
    final baslik = t.widget<Text>(find
        .descendant(
            of: find.byType(BottomSheet), matching: find.text('BIST hisse'))
        .first);
    expect(baslik.style?.fontWeight, FontWeight.w600);
    expect(t.takeException(), isNull);
  });

  testWidgets('dokununca sayfa kapanır, varlık sayfası açılır', (t) async {
    final gozcu = await kur(t);
    await t.tap(find.text('AAL'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(gozcu.adlar.last, 'asset_detail');
    expect(find.text('Bu paranın nereden geldiği'), findsNothing);
    final ekran = t.widget<AssetDetailScreen>(find.byType(AssetDetailScreen));
    expect(ekran.asset.ticker, 'TEFAS:AAL');
  });
}
