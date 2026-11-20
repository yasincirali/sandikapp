import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/services/portfoy_xray.dart';
import 'package:portfoy_takip/services/satin_alma_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart';
import 'package:portfoy_takip/widgets/premium_kilit_karti.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show IntroEligibilityStatus;
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Ar-Ge 20 Kas UI/UX turu 2: Premium kilit kartları ve kilit satırları.
/// #1 son bilinen hak, #2 fon dağılımı RPC'si (0187), #3 tek fon payı,
/// #4 kart kilit satırına `ozellik`, #6 kilit etiketi + düğme, deneme satırı.

class _Auth extends AuthNotifier {
  _Auth(this.kullanici);
  final AppUser? kullanici;
  @override
  Future<AppUser?> build() async => kullanici;
}

AppUser _kullanici(String id) => AppUser(
      id: id,
      email: '$id@example.com',
      displayName: id,
      createdAt: DateTime(2026, 1, 1),
    );

class _Onbellek implements PremiumHakOnbellegi {
  String? uid;
  List<Map<String, dynamic>>? satirlar;

  @override
  List<Map<String, dynamic>>? oku(String u) => u == uid ? satirlar : null;

  @override
  Future<void> yaz(String u, List<Map<String, dynamic>> s) async {
    uid = u;
    satirlar = s;
  }

  @override
  Future<void> sil() async {
    uid = null;
    satirlar = null;
  }
}

Map<String, dynamic> _abonelik({int gun = 30}) => {
      'kaynak': 'revenuecat',
      'urun': 'premium_yillik',
      'bitis': DateTime.now().add(Duration(days: gun)).toIso8601String(),
    };

ProviderContainer _kap({
  required AppUser? kullanici,
  required _Onbellek onbellek,
  required Future<List<Map<String, dynamic>>> Function() okuyucu,
}) {
  final c = ProviderContainer(overrides: [
    paywallVisibleProvider.overrideWithValue(true),
    authProvider.overrideWith(() => _Auth(kullanici)),
    premiumHakOnbellegiProvider.overrideWithValue(onbellek),
    premiumHakOkuyucuProvider.overrideWithValue(okuyucu),
  ]);
  addTearDown(c.dispose);
  return c;
}

Asset _lot(String ticker, AssetType tur) => Asset(
      id: ticker,
      userId: 'u1',
      name: ticker,
      ticker: ticker,
      type: tur,
      quantity: 1,
      purchasePrice: 1,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      addedDate: DateTime(2026, 1, 1),
    );

Future<void> _kur(WidgetTester t, Widget govde, List<Override> ek) async {
  await t.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: ek,
    child: MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      home: Scaffold(body: govde),
    ),
  ));
  await t.pumpAndSettle();
}

const _satir = KilitSatiri(metin: "Temettü tahmini Premium'da", kaynak: 'x');

void main() {
  group('#1 son bilinen hak', () {
    test('hak yüklenirken son bilinen hak kullanılır', () async {
      final o = _Onbellek()
        ..uid = 'u1'
        ..satirlar = [_abonelik()];
      final c = _kap(
          kullanici: _kullanici('u1'),
          onbellek: o,
          okuyucu: () => Completer<List<Map<String, dynamic>>>().future);
      await c.read(authProvider.future);
      expect(c.read(premiumHaklariProvider).isLoading, isTrue);
      expect(c.read(gecerliPremiumHakkiProvider), isNotNull);
    });

    test('hak okunamazsa son bilinen hak kullanılır', () async {
      final o = _Onbellek()
        ..uid = 'u1'
        ..satirlar = [_abonelik()];
      final c = _kap(
          kullanici: _kullanici('u1'),
          onbellek: o,
          okuyucu: () async => throw Exception('çevrimdışı'));
      await c.read(authProvider.future);
      await c.read(premiumHaklariProvider.future);
      expect(c.read(gecerliPremiumHakkiProvider), isNotNull);
    });

    test('başka kullanıcının önbelleği Premium yapmaz', () async {
      final o = _Onbellek()
        ..uid = 'u1'
        ..satirlar = [_abonelik()];
      final c = _kap(
          kullanici: _kullanici('u2'),
          onbellek: o,
          okuyucu: () async => throw Exception('çevrimdışı'));
      await c.read(authProvider.future);
      expect(c.read(gecerliPremiumHakkiProvider), isNull,
          reason: 'yüklenirken');
      await c.read(premiumHaklariProvider.future);
      expect(c.read(gecerliPremiumHakkiProvider), isNull, reason: 'hatada');
    });

    test('süresi geçmiş önbellek Premium yapmaz', () async {
      final o = _Onbellek()
        ..uid = 'u1'
        ..satirlar = [_abonelik(gun: -1)];
      final c = _kap(
          kullanici: _kullanici('u1'),
          onbellek: o,
          okuyucu: () async => throw Exception('çevrimdışı'));
      await c.read(authProvider.future);
      await c.read(premiumHaklariProvider.future);
      expect(c.read(gecerliPremiumHakkiProvider), isNull);
    });

    test('başarılı okuma önbelleğe yazılır; oturum kapanınca silinir',
        () async {
      final o = _Onbellek();
      final c = _kap(
          kullanici: _kullanici('u1'),
          onbellek: o,
          okuyucu: () async => [_abonelik()]);
      await c.read(authProvider.future);
      await c.read(premiumHaklariProvider.future);
      expect(o.uid, 'u1');
      expect(o.satirlar, hasLength(1));

      final cikis =
          _kap(kullanici: null, onbellek: o, okuyucu: () async => const []);
      await cikis.read(authProvider.future);
      await cikis.read(premiumHaklariProvider.future);
      expect(o.uid, isNull);
      expect(o.satirlar, isNull);
    });

    test('gerçek önbellek: sahibine göre okur, siler', () async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
      const o = PremiumHakOnbellegi();
      await o.yaz('u1', [_abonelik()]);
      expect(o.oku('u1'), hasLength(1));
      expect(o.oku('u2'), isNull);
      await o.sil();
      expect(o.oku('u1'), isNull);
    });
  });

  group('#3 tek fon payı (saf)', () {
    final poz = aggregatePositions([
      _lot('TEFAS:AAL', AssetType.fon),
      _lot('THYAO.IS', AssetType.hisse),
    ]);
    double? deger(Position p) =>
        {'TEFAS:AAL': 38.0, 'THYAO.IS': 62.0}[p.representative.ticker];

    test('tutulan fon: tam sayı pay', () {
      expect(tekFonPayi(pozisyonlar: poz, deger: deger, kod: 'AAL'), 38);
    });
    test('tutulmayan fon: null', () {
      expect(tekFonPayi(pozisyonlar: poz, deger: deger, kod: 'AFT'), isNull);
    });
  });

  group('deneme hakkı', () {
    test('yalnız "uygun" süre döndürür', () {
      expect(
          denemeHakki(
              7, IntroEligibilityStatus.introEligibilityStatusEligible),
          7);
      for (final d in [
        IntroEligibilityStatus.introEligibilityStatusIneligible,
        IntroEligibilityStatus.introEligibilityStatusUnknown,
        IntroEligibilityStatus.introEligibilityStatusNoIntroOfferExists,
        null,
      ]) {
        expect(denemeHakki(7, d), isNull, reason: '$d');
      }
      expect(
          denemeHakki(
              null, IntroEligibilityStatus.introEligibilityStatusEligible),
          isNull);
    });

    testWidgets('uygun: kilit satırında ikinci satır', (t) async {
      await _kur(t, _satir,
          [denemeHakkiGunuProvider.overrideWith((ref) async => 7)]);
      expect(find.text('7 gün ücretsiz dene'), findsOneWidget);
    });

    testWidgets('uygun değil / bilinmiyor: satır yok', (t) async {
      await _kur(t, _satir,
          [denemeHakkiGunuProvider.overrideWith((ref) async => null)]);
      expect(find.textContaining('ücretsiz dene'), findsNothing);
      expect(find.text("Temettü tahmini Premium'da"), findsOneWidget);
    });

    testWidgets('hata: satır yok', (t) async {
      await _kur(t, _satir, [
        denemeHakkiGunuProvider
            .overrideWith((ref) async => throw Exception('mağaza'))
      ]);
      expect(find.textContaining('ücretsiz dene'), findsNothing);
    });
  });

  group('#4 #6 kilit bileşenleri', () {
    testWidgets('kilit satırı düğme olarak, "Kilitli" etiketiyle okunur',
        (t) async {
      final h = t.ensureSemantics();
      await _kur(t, _satir,
          [denemeHakkiGunuProvider.overrideWith((ref) async => null)]);
      final dugum = t.getSemantics(find.byType(KilitSatiri));
      expect(dugum, isSemantics(isButton: true));
      expect(dugum.label, contains('Kilitli'));
      expect(dugum.label, contains("Temettü tahmini Premium'da"));
      h.dispose();
    });

    testWidgets('kart kilit satırına ozellik geçer; başlık w600', (t) async {
      await _kur(
          t,
          const PremiumKilitKarti(
            ikon: Icons.lock,
            baslik: 'Başlık',
            govde: 'Gövde',
            kilitMetni: "X Premium'da",
            kaynak: 'temettu_tahmini',
          ),
          [denemeHakkiGunuProvider.overrideWith((ref) async => null)]);
      final s = t.widget<KilitSatiri>(find.byType(KilitSatiri));
      expect(s.ozellik, 'temettu_tahmini');
      expect(t.widget<Text>(find.text('Başlık')).style?.fontWeight,
          FontWeight.w600);
    });

    test('karşılaştırma ekranı ortak KilitSatiri kullanır', () {
      final k = ekranKaynagiSync('lib/screens/comparison_screen.dart');
      expect(k, contains("ozellik: 'compare_series'"));
      final i = k.indexOf('Widget _kilitliOnizlemeSatiri(');
      final govde = k.substring(i, k.indexOf('Widget _cipSatiri(', i));
      expect(govde, contains('KilitSatiri('));
      expect(govde, isNot(contains('Icons.lock_outline_rounded')));
    });
  });

  group('#2 0187 fon_dagilimi_var_mi', () {
    final sql =
        ekranKaynagiSync('supabase/migrations/0187_fon_dagilimi_var_mi.sql');
    test('yalnız boolean, security definer + search_path', () {
      expect(sql, contains('returns boolean'));
      expect(sql, contains('security definer'));
      expect(sql, contains('set search_path = public, pg_temp'));
    });
    test('yalnız authenticated çalıştırır; doğrulama bloğu var', () {
      expect(
          sql,
          contains('revoke all on function public.fon_dagilimi_var_mi(text) '
              'from public, anon;'));
      expect(
          sql,
          contains('grant execute on function public.fon_dagilimi_var_mi(text) '
              'to authenticated;'));
      expect(sql, isNot(contains('to anon')));
      expect(sql, contains('do \$\$'));
      expect(sql, contains('raise exception'));
    });
    test('istemci aynı adı ve parametreyi çağırır', () {
      final k = ekranKaynagiSync('lib/services/supabase_service.dart');
      expect(k, contains("'fon_dagilimi_var_mi'"));
      expect(k, contains("'p_fon_kodu': kod"));
    });
  });
}
