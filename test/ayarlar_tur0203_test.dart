import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/settings_screen.dart';
import 'package:portfoy_takip/services/abonelik_yonetimi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sik_sorulanlar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Ar-Ge 26 Kas 02:03 (UI/UX turu 19): Ayarlar, Premium yolları ve
/// sayfaların düzeni (madde 1-7). Kilitli "Çok"un davranışı
/// `bildirim_on_ayar_test`'te.
final _tr = AppLocalizationsTr();
final _en = AppLocalizationsEn();

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  Widget host({required bool abone}) => ProviderScope(
        overrides: [magazaPremiumProvider.overrideWith((_) => abone)],
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: const SettingsScreen(bolum: SettingsBolum.hesap),
        ),
      );

  Future<void> hesapSilOnayi(WidgetTester tester, {required bool abone}) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(abone: abone));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_tr.deleteMyAccount));
    await tester.pumpAndSettle();
    expect(find.text(_tr.deleteAccountTitle), findsOneWidget);
  }

  group('#1 aboneliğin yolu', () {
    testWidgets('hesap silme: aboneye "Aboneliği yönet", silme yolu aynen',
        (tester) async {
      final eski = AbonelikYonetimi.webAc;
      addTearDown(() => AbonelikYonetimi.webAc = eski);
      var acilan = 0;
      AbonelikYonetimi.webAc = (_) async {
        acilan++;
        return false;
      };
      await hesapSilOnayi(tester, abone: true);
      final dugme = find.byKey(const ValueKey('hesapSilAboneligiYonet'));
      expect(dugme, findsOneWidget);
      expect(tester.getSize(dugme).height, greaterThanOrEqualTo(44));
      // Silme yolu: aynı "Devam" düğmesi, ek adım yok.
      expect(find.text(_tr.continueAction), findsOneWidget);

      await tester.tap(dugme);
      await tester.pumpAndSettle();
      expect(acilan, 1);
      // Mağaza sayfası açılamadı: yol söyleyen snack, diyalog açık kalır.
      expect(find.text(_tr.prmYonetAcilamadiAndroid), findsOneWidget);
      expect(find.text(_tr.deleteAccountTitle), findsOneWidget);
    });

    testWidgets('hesap silme: abone olmayana düğme yok', (tester) async {
      await hesapSilOnayi(tester, abone: false);
      expect(
          find.byKey(const ValueKey('hesapSilAboneligiYonet')), findsNothing);
      expect(find.text(_tr.continueAction), findsOneWidget);
    });

    testWidgets('SSS: Premium cevabında "Bize yaz"ın yanında, ötekilerde yok',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: Scaffold(
          body: SingleChildScrollView(child: SikSorulanlar(onBizeYaz: () {})),
        ),
      ));
      await tester.tap(find.text(_tr.sssFonSoru));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sssAboneligiYonet')), findsNothing);

      await tester.tap(find.text(_tr.sssPremiumSoru));
      await tester.pumpAndSettle();
      final dugme = find.byKey(const ValueKey('sssAboneligiYonet'));
      expect(dugme, findsOneWidget);
      expect(find.text(_tr.aboneligiYonet), findsOneWidget);
      expect(tester.getSize(dugme).height, greaterThanOrEqualTo(44));
    });

    test('tek yol: üç yer aynı yardımcıyı çağırır', () {
      final satir =
          ekranKaynagiSync('lib/widgets/premium_abonelik_satiri.dart');
      expect(
          satir.contains('Future<void> aboneligiYonet(BuildContext context)'),
          isTrue);
      expect(
          satir.contains('onPressed: () => aboneligiYonet(context)'), isTrue);
      expect(
          ekranKaynagiSync('lib/widgets/sik_sorulanlar.dart')
              .contains('aboneligiYonet(context)'),
          isTrue);
      expect(
          ekranKaynagiSync('lib/screens/settings_screen.dart')
              .contains('onPressed: () => aboneligiYonet(context)'),
          isTrue);
    });
  });

  group('#2 kilitli "Çok"', () {
    test('ilk dokunuş önizler, paywall düğmesi SandikAsyncTap', () {
      final kart = ekranKaynagiSync('lib/widgets/bildirim_on_ayar_karti.dart');
      expect(kart.contains('if (_onizleme != a)'), isTrue);
      expect(kart.contains('SandikAsyncTap('), isTrue);
      expect(kart.contains('l10n.bildirimOnAyarPremiumlaAc'), isTrue);
    });
  });

  group('#3 tekrar eden başlık', () {
    testWidgets('Hesap & güvenlik: "Güvenlik ve hesap" yok, "Veri" var',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(abone: false));
      await tester.pumpAndSettle();
      expect(find.text('Güvenlik ve hesap'), findsNothing);
      expect(find.text(_tr.settingsGroupData), findsOneWidget);
    });

    test('ölü anahtar iki .arb\'dan da kalktı', () {
      for (final p in ['lib/l10n/app_tr.arb', 'lib/l10n/app_en.arb']) {
        final arb = jsonDecode(File(p).readAsStringSync()) as Map;
        expect(arb.containsKey('settingsGroupSecurityAccount'), isFalse,
            reason: p);
        expect(arb.containsKey('biometricLockSubtitle'), isFalse, reason: p);
      }
    });
  });

  test('#4 alarm sayacı l10n anahtarından', () {
    final s = ekranKaynagiSync('lib/screens/settings_screen.dart');
    expect(s.contains("'\$aktif aktif alarm'"), isFalse);
    expect(s.contains('context.l10n.nActiveAlarmsAll(aktif)'), isTrue);
    expect(_en.nActiveAlarmsAll(3), '3 active alerts');
  });

  group('#5-6 hiza, ritim, sinyal', () {
    final s = ekranKaynagiSync('lib/screens/settings_screen.dart');

    test('alt başlık yatay iç boşluksuz, bölüm arası 28 yok', () {
      expect(s.contains('EdgeInsets.fromLTRB(8, 18, 8, 6)'), isFalse);
      expect(s.contains('SizedBox(height: 28)'), isFalse);
    });

    test('Görünüm açıklamaları seçici kenarında (4 pt içeride değil)', () {
      for (final not in [
        'l.textSizeNote',
        'l.languageNote',
        'context.l10n.investorLevelNote',
        'context.l10n.rateNotFetched',
      ]) {
        final i = s.indexOf(not);
        expect(i, greaterThan(0), reason: not);
        final once = s.substring(i - 220, i);
        expect(once.contains('EdgeInsets.symmetric(horizontal:'), isFalse,
            reason: not);
      }
    });

    test('baz para Altın: varlık türü sikkesi, madalya değil', () {
      expect(s.contains('Icons.workspace_premium'), isFalse);
      expect(s.contains('(BaseCurrency.gold, AssetType.altin.icon)'), isTrue);
    });

    test('"Özel" rozeti w600 tavanında', () {
      final kart = ekranKaynagiSync('lib/widgets/bildirim_on_ayar_karti.dart');
      expect(kart.contains('FontWeight.w700'), isFalse);
    });
  });

  group('#7 jargon', () {
    test('KVKK parantezi alt yazıdan kalktı (iki dil)', () {
      expect(_tr.downloadMyDataSubtitle.contains('KVKK'), isFalse);
      expect(_en.downloadMyDataSubtitle.contains('KVKK'), isFalse);
    });

    test('kilit alt yazısı platforma göre tek ad', () {
      expect(_tr.biometricLockSubtitleIos.contains('/'), isFalse);
      expect(_tr.biometricLockSubtitleAndroid.contains('/'), isFalse);
      expect(_tr.biometricLockSubtitleIos, contains('Face ID'));
      expect(_tr.biometricLockSubtitleAndroid, contains('parmak izi'));
      final s = ekranKaynagiSync('lib/screens/settings_screen.dart');
      expect(s.contains('context.l10n.biometricLockSubtitleIos'), isTrue);
      expect(s.contains('context.l10n.biometricLockSubtitleAndroid'), isTrue);
    });
  });
}
