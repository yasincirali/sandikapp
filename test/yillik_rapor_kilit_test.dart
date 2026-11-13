import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/yillik_rapor_screen.dart';
import 'package:portfoy_takip/services/yillik_rapor.dart';
import 'package:portfoy_takip/widgets/premium_kilit_karti.dart';

/// Kilitli yıllık rapor kullanıcının kendi defteriyle konuşur (yasin
/// 2026-11-13): en yeni yılın satış/temettü ADEDİ, tutar yok. Sıfır parça
/// yazılmaz; ikisi de yoksa bugünkü genel cümle.
Asset _lot(String id, AssetKind kind,
        {String userId = 'u1', DateTime? tarih, DateTime? silindi}) =>
    Asset(
      id: id,
      userId: userId,
      name: 'THYAO',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      kind: kind,
      sellPrice: kind == AssetKind.sell ? 130 : null,
      dividendAmount: kind == AssetKind.dividend ? 50 : 0,
      commission: 5,
      addedDate: tarih ?? DateTime(2026, 6, 1),
      deletedAt: silindi,
    );

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _Portfoy extends PortfolioNotifier {
  _Portfoy(this.lotlar);
  final List<Asset> lotlar;
  @override
  Future<PortfolioState> build() async => PortfolioState(assets: lotlar);
}

void main() {
  group('yillikKayitSayimi', () {
    test('en yeni yılın satış ve temettü adedi; başkası ve silinen düşer', () {
      final s = yillikKayitSayimi([
        _lot('s1', AssetKind.sell),
        _lot('s2', AssetKind.sell),
        _lot('d1', AssetKind.dividend),
        _lot('b1', AssetKind.buy),
        _lot('x', AssetKind.sell, userId: 'u2'),
        _lot('z', AssetKind.sell, silindi: DateTime(2026, 7, 1)),
        _lot('eski', AssetKind.sell, tarih: DateTime(2025, 3, 1)),
      ], 'u1');
      expect(s, (yil: 2026, satis: 2, temettu: 1));
    });

    test('yalnız alım (komisyonlu) varsa null', () {
      expect(yillikKayitSayimi([_lot('b', AssetKind.buy)], 'u1'), isNull);
      expect(yillikKayitSayimi(const [], 'u1'), isNull);
    });
  });

  group('yillikRaporKilitMetni', () {
    final tr = AppLocalizationsTr();
    test('iki parça', () {
      expect(yillikRaporKilitMetni(tr, (yil: 2026, satis: 4, temettu: 3)),
          "2026 yılında 4 satışın ve 3 temettün kayıtlı · raporun Premium'da hazır");
    });
    test('sıfır parça yazılmaz', () {
      expect(yillikRaporKilitMetni(tr, (yil: 2025, satis: 1, temettu: 0)),
          "2025 yılında 1 satışın kayıtlı · raporun Premium'da hazır");
      expect(yillikRaporKilitMetni(tr, (yil: 2025, satis: 0, temettu: 2)),
          "2025 yılında 2 temettün kayıtlı · raporun Premium'da hazır");
    });
    test('sayım yoksa ya da ikisi sıfırsa genel cümle', () {
      expect(yillikRaporKilitMetni(tr, null), tr.yrKilitSatir);
      expect(yillikRaporKilitMetni(tr, (yil: 2025, satis: 0, temettu: 0)),
          tr.yrKilitSatir);
    });
    test('İngilizce tekil/çoğul', () {
      final en = AppLocalizationsEn();
      expect(yillikRaporKilitMetni(en, (yil: 2026, satis: 1, temettu: 2)),
          '1 sale and 2 dividends recorded in 2026 · your report is ready in Premium');
    });
  });

  testWidgets('kilitli ekran kendi sayımını yazar, tutar yazmaz',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_Auth.new),
        portfolioProvider.overrideWith(() => _Portfoy([
              _lot('s1', AssetKind.sell),
              _lot('d1', AssetKind.dividend),
              _lot('d2', AssetKind.dividend),
            ])),
        premiumKilitliProvider.overrideWithValue(true),
      ],
      child: const MaterialApp(
        locale: Locale('tr', 'TR'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: YillikRaporScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PremiumKilitKarti), findsOneWidget);
    expect(
        find.text(
            "2026 yılında 1 satışın ve 2 temettün kayıtlı · raporun Premium'da hazır"),
        findsOneWidget);
    expect(find.textContaining('₺'), findsNothing);
  });
}
