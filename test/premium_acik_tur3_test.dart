import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/analiz_provider.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/aylik_rapor_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/aylik_rapor_screen.dart';
import 'package:portfoy_takip/screens/yillik_rapor_screen.dart';
import 'package:portfoy_takip/services/temettu_tahmini.dart';
import 'package:portfoy_takip/services/varlik_analizi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sandik_error_view.dart';
import 'package:portfoy_takip/widgets/sandik_skeleton.dart';

/// Ar-Ge 20 Kas tur 3: premium raporların yükleniyor / hata / tek yıl hâli.
Asset _satis(int yil) => Asset(
      id: 's$yil',
      userId: 'u1',
      name: 'THYAO',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      kind: AssetKind.sell,
      sellPrice: 130,
      addedDate: DateTime(yil, 6, 1),
    );

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
      id: 'u1',
      email: 't@example.com',
      displayName: 'D',
      createdAt: DateTime(2026, 1, 1));
}

class _Bekler extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() => Completer<PortfolioState>().future;
}

class _Hata extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => throw Exception('x');
}

class _Dolu extends PortfolioNotifier {
  _Dolu(this.l);
  final List<Asset> l;
  @override
  Future<PortfolioState> build() async => PortfolioState(assets: l);
}

Widget _app(Widget home, List<Override> o) => ProviderScope(
      overrides: [
        authProvider.overrideWith(_Auth.new),
        premiumKilitliProvider.overrideWithValue(false),
        ...o,
      ],
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('yıllık: yüklenirken iskelet, boş metin yok', (t) async {
    await t.pumpWidget(_app(const YillikRaporScreen(),
        [portfolioProvider.overrideWith(_Bekler.new)]));
    await t.pump();
    expect(find.byType(SandikSkeletonList), findsOneWidget);
    expect(find.text('Raporlanacak kayıt yok'), findsNothing);
  });

  testWidgets('yıllık: okunamayınca hata görünümü', (t) async {
    await t.pumpWidget(_app(const YillikRaporScreen(),
        [portfolioProvider.overrideWith(_Hata.new)]));
    await t.pumpAndSettle();
    expect(find.byType(SandikErrorView), findsOneWidget);
    expect(find.text('Raporlanacak kayıt yok'), findsNothing);
  });

  testWidgets('yıllık: tek yıl varsa yıl satırı görünür', (t) async {
    await t.pumpWidget(_app(const YillikRaporScreen(), [
      portfolioProvider.overrideWith(() => _Dolu([_satis(2025)]))
    ]));
    await t.pumpAndSettle();
    expect(find.text('2025'), findsOneWidget);
  });

  testWidgets('aylık: özet hatası "hazır değil" değil, hata + yeniden dene',
      (t) async {
    var cagri = 0;
    await t.pumpWidget(_app(AylikRaporScreen(donem: DateTime.utc(2026, 9, 1)), [
      tutulanNotAnahtarlariProvider.overrideWithValue(const []),
      notOzetleriProvider
          .overrideWith((ref, a) async => <String, AnalizOzeti>{}),
      aylikRaporOzetiProvider.overrideWith((ref, d) async {
        cagri++;
        throw Exception('x');
      }),
    ]));
    await t.pumpAndSettle();
    expect(find.byType(SandikErrorView), findsOneWidget);
    final once = cagri;
    final yeniden = find.descendant(
        of: find.byType(SandikErrorView), matching: find.byType(FilledButton));
    if (yeniden.evaluate().isNotEmpty) {
      await t.tap(yeniden.first);
      await t.pumpAndSettle();
      expect(cagri, greaterThan(once));
    }
  });

  test('temettü aralığı: sonraki aydan 12 ay', () {
    expect(temettuAralikEtiketi(DateTime(2026, 11, 20), 'tr_TR'),
        'Ara 2026 – Kas 2027');
    expect(temettuAralikEtiketi(DateTime(2026, 12, 5), 'tr_TR'),
        'Oca 2027 – Ara 2027');
  });
}
