import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/config/pref_keys.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/widgets/premium_hediye_sayfasi.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Premium bitişi kaynaktan bağımsız (Ar-Ge 14 Kas #1, #8): hediye, ücretsiz
/// deneme ve yenilenmeyen mağaza aboneliği aynı tek seferlik sayfayı açar.
/// Paywall kapalıyken, hiç Premium'u olmamışta ve geçerli hak varken yok.
/// Hediyenin eski "söylendi" anahtarı okunur: hediyesi biten ikinci kez
/// görmez.
void main() {
  final simdi = DateTime.utc(2026, 11, 14, 12);
  final dun = simdi.subtract(const Duration(days: 1));
  final gecenAy = simdi.subtract(const Duration(days: 30));
  final yarin = simdi.add(const Duration(days: 1));

  PremiumHakki hak(String kaynak, DateTime? bitis) =>
      PremiumHakki(kaynak: kaynak, bitis: bitis);

  group('premiumBitisiBul', () {
    test('hiç hakkı olmamış kullanıcı: yok', () {
      expect(premiumBitisiBul(const [], simdi), isNull);
    });

    test('hediye bitti: hediye kaynağı ve bitişi (eski davranış)', () {
      final b = premiumBitisiBul([hak('erken_kullanici', dun)], simdi)!;
      expect(b.hediye, isTrue);
      expect(b.bitis, dun);
      expect(b.anahtar, dun.toUtc().toIso8601String());
    });

    test('deneme/abonelik bitti: mağaza kaynağı', () {
      final b = premiumBitisiBul([hak('revenuecat', dun)], simdi)!;
      expect(b.hediye, isFalse);
      expect(b.kaynak, 'revenuecat');
    });

    test('geçerli bir hak varken yok', () {
      expect(
          premiumBitisiBul(
              [hak('erken_kullanici', dun), hak('revenuecat', yarin)], simdi),
          isNull);
      expect(premiumBitisiBul([hak('manuel', null)], simdi), isNull);
    });

    test('birden çok bitmiş hak: en son biten anlatılır', () {
      final b = premiumBitisiBul(
          [hak('erken_kullanici', gecenAy), hak('revenuecat', dun)], simdi)!;
      expect(b.kaynak, 'revenuecat');
      expect(b.bitis, dun);
    });
  });

  group('premiumBitmisProvider', () {
    ProviderContainer kap({
      bool paywall = true,
      bool premium = false,
      List<PremiumHakki> haklar = const [],
    }) {
      final c = ProviderContainer(overrides: [
        paywallVisibleProvider.overrideWithValue(paywall),
        effectivePremiumProvider.overrideWithValue(premium),
        premiumHaklariProvider.overrideWith((_) async => haklar),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    final bitmis = [hak('revenuecat', DateTime.now().subtract(const Duration(days: 1)))];

    test('bitmiş mağaza aboneliği: sinyal var', () async {
      final c = kap(haklar: bitmis);
      await c.read(premiumHaklariProvider.future);
      expect(c.read(premiumBitmisProvider)?.kaynak, 'revenuecat');
    });

    test('paywall kapalıyken yok', () async {
      final c = kap(paywall: false, haklar: bitmis);
      await c.read(premiumHaklariProvider.future);
      expect(c.read(premiumBitmisProvider), isNull);
    });

    test('geçerli hak varken (ör. webhook öncesi mağaza hakkı) yok', () async {
      final c = kap(premium: true, haklar: bitmis);
      await c.read(premiumHaklariProvider.future);
      expect(c.read(premiumBitmisProvider), isNull);
    });
  });

  group('söylendi anahtarı', () {
    setUp(() => setPreferencesUser('u1'));
    tearDown(() => setPreferencesUser(null));

    test('hediyenin eski anahtarı yeni sağlayıcıdan okunur', () async {
      SharedPreferences.setMockInitialValues({
        '${PrefKeys.premiumHediyeBittiSoylenen}_u1': '2026-11-01T00:00:00.000Z',
      });
      await initPreferencesCache();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(premiumBittiSoylenenProvider), '2026-11-01T00:00:00.000Z');
    });

    test('yeni değer yeni anahtara yazılır ve eskisinden önce gelir', () async {
      SharedPreferences.setMockInitialValues({
        '${PrefKeys.premiumHediyeBittiSoylenen}_u1': 'eski',
      });
      await initPreferencesCache();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(premiumBittiSoylenenProvider.notifier).set('yeni');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('${PrefKeys.premiumBittiSoylenen}_u1'), 'yeni');
      c.invalidate(premiumBittiSoylenenProvider);
      expect(c.read(premiumBittiSoylenenProvider), 'yeni');
    });
  });

  group('sayfa metni kaynağa göre', () {
    setUpAll(() => initializeDateFormatting('tr_TR'));

    Future<void> ac(WidgetTester tester, PremiumBitisi b,
        {double olcek = 1}) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: TextScaler.linear(olcek)),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(child: PremiumBittiSayfasi(bitis: b))),
      ));
      await tester.pump();
    }

    testWidgets('deneme/abonelik: tarih ve iki düğme, geri sayım yok',
        (tester) async {
      await ac(tester,
          PremiumBitisi(bitis: DateTime(2026, 11, 13, 12), kaynak: 'revenuecat'));
      expect(find.text('Premium süren doldu'), findsOneWidget);
      expect(
          find.text("Premium'un 13 Kasım 2026 tarihinde bitti. Verilerinden "
              'hiçbiri silinmedi; temel özellikler ücretsiz kalır.'),
          findsOneWidget);
      expect(find.text("Premium'u gör"), findsOneWidget);
      expect(find.text('Şimdi değil'), findsOneWidget);
    });

    testWidgets('hediye: 2026-10-20 metni', (tester) async {
      await ac(tester,
          PremiumBitisi(bitis: DateTime(2026, 11, 13), kaynak: 'erken_kullanici'));
      expect(find.text('Hediye süren doldu'), findsOneWidget);
      expect(find.textContaining('Verilerinden hiçbiri silinmedi;'),
          findsOneWidget);
    });

    testWidgets('Dynamic Type 2× taşma yok', (tester) async {
      await ac(tester,
          PremiumBitisi(bitis: DateTime(2026, 11, 13), kaynak: 'revenuecat'),
          olcek: 2);
      expect(tester.takeException(), isNull);
    });
  });
}
