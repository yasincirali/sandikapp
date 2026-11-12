import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/temettu_tahmini_provider.dart';
import 'package:portfoy_takip/screens/temettu_tahmini_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sandik_skeleton.dart';

/// Temettü tahmini ekranı fiyat turunda iskelete düşmemeli (Ar-Ge 12 Kas
/// #6). Fiyat turu her seferinde `assets` listesini yeni nesne olarak
/// yazar (`_fiyatTuru` → `map(...).toList()`); sağlayıcı listenin
/// KİMLİĞİNİ izlerken her turda yeniden koşuyor, ekran `when` ile
/// iskelete düşüyordu.
const _uid = 'u1';

Asset _lot({double miktar = 10, double fiyat = 110}) => Asset(
      id: 'a1',
      userId: _uid,
      name: 'Gram altın',
      ticker: 'GRAM',
      type: AssetType.altin,
      quantity: miktar,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      lastUpdated: DateTime(2026, 11, 12, 10),
      addedDate: DateTime(2026, 1, 5),
    );

class _Portfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: [_lot()], usdTry: 42, eurTry: 46, gbpTry: 54);

  void yaz(List<Asset> lotlar) =>
      state = AsyncData(state.requireValue.copyWith(assets: lotlar));
}

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

void main() {
  late int hesap;

  Future<ProviderContainer> ac(WidgetTester t) async {
    hesap = 0;
    final c = ProviderContainer(
      overrides: [
        portfolioProvider.overrideWith(_Portfoy.new),
        authProvider.overrideWith(_Auth.new),
        premiumKilitliProvider.overrideWithValue(false),
      ],
      observers: [_Sayac(() => hesap++)],
    );
    addTearDown(c.dispose);
    await c.read(portfolioProvider.future);
    await c.read(authProvider.future);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TemettuTahminiScreen(),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byType(SandikSkeletonList), findsNothing);
    return c;
  }

  _Portfoy not(ProviderContainer c) =>
      c.read(portfolioProvider.notifier) as _Portfoy;

  testWidgets('fiyat turu (yeni liste, aynı defter): iskelet yok, hesap yok',
      (t) async {
    final c = await ac(t);
    final once = hesap;
    not(c).yaz([_lot(fiyat: 111)]);
    await t.pump();
    expect(find.byType(SandikSkeletonList), findsNothing,
        reason: 'fiyat turu ekranı iskelete düşürmemeli');
    await t.pumpAndSettle();
    expect(hesap, once, reason: 'fiyat turu tahmini yeniden hesaplatmamalı');
  });

  testWidgets('miktar düzenlemesi: yeniden hesaplanır, iskelet yine yok',
      (t) async {
    final c = await ac(t);
    final once = hesap;
    not(c).yaz([_lot(miktar: 20)]);
    await t.pump();
    expect(find.byType(SandikSkeletonList), findsNothing,
        reason: 'yeniden yüklemede eski içerik kalır');
    await t.pumpAndSettle();
    expect(hesap, greaterThan(once),
        reason: 'içerik değişimi (miktar) kaçırılmamalı');
  });

  test('DefterImzasi: fiyat turu eşit, defter değişimi farklı', () {
    final once = DefterImzasi([_lot()]);
    expect(DefterImzasi([_lot(fiyat: 999)..lastUpdated = DateTime(2027)]),
        once);
    expect(DefterImzasi([_lot(miktar: 11)]), isNot(once));
    expect(DefterImzasi([_lot()..purchasePrice = 1]), isNot(once));
    expect(DefterImzasi([_lot().copyWithDeletedAt(DateTime(2026, 11))]),
        isNot(once));
    expect(DefterImzasi([_lot(), _lot()]), isNot(once));
    // Elle fiyatlı lotta fiyat defter girdisidir.
    expect(DefterImzasi([_lot()..isManualPrice = true]),
        isNot(DefterImzasi([_lot(fiyat: 5)..isManualPrice = true])));
  });
}

/// temettuTahminiProvider'ın kaç kez yeniden hesaplandığını sayar.
class _Sayac extends ProviderObserver {
  _Sayac(this.arttir);
  final VoidCallback arttir;

  @override
  void didUpdateProvider(ProviderBase<Object?> provider, Object? previousValue,
      Object? newValue, ProviderContainer container) {
    if (provider == temettuTahminiProvider &&
        newValue is AsyncValue &&
        newValue.isLoading) {
      arttir();
    }
  }
}
