import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_kullanim_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/services/satin_alma_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/premium_abonelik_satiri.dart';

/// "Premium'la kullandıkların" satırı (Ar-Ge 14 Kas #2): yalnız ücretsiz
/// sınırı aşan ya da yalnız Premium'da olan kalemler; sıfırlar yazılmaz,
/// hiçbiri yoksa satır yok.
void main() {
  List<PremiumKullanim> kalemler({
    int varlik = 3,
    int takip = 2,
    int fiyat = 1,
    int gosterge = 0,
    int cizgi = 0,
    int? portfoy,
  }) =>
      premiumKullanimKalemleri(
        varlik: varlik,
        varlikSiniri: 5,
        takip: takip,
        takipSiniri: 5,
        fiyatAlarmi: fiyat,
        toplamAlarm: fiyat + gosterge + cizgi,
        alarmSiniri: 20,
        gostergeAlarmi: gosterge,
        cizgiAlarmi: cizgi,
        portfoy: portfoy,
      );

  group('kalem kararı', () {
    test('ücretsiz sınırın içindeki kullanıcı: kalem yok', () {
      expect(kalemler(), isEmpty);
      expect(kalemler(portfoy: 1), isEmpty, reason: 'yalnız Ana');
    });

    test('sınırı aşan varlık ve takip yazılır, sınırdaki yazılmaz', () {
      expect(kalemler(varlik: 14, takip: 5),
          [(kalem: PremiumKalem.varlik, sayi: 14)]);
      expect(kalemler(takip: 6), [(kalem: PremiumKalem.takip, sayi: 6)]);
    });

    test('gösterge/çizgi alarmı ve ikinci portföy her zaman Premium', () {
      expect(kalemler(gosterge: 3, cizgi: 1, portfoy: 2), [
        (kalem: PremiumKalem.gostergeAlarmi, sayi: 3),
        (kalem: PremiumKalem.cizgiAlarmi, sayi: 1),
        (kalem: PremiumKalem.portfoy, sayi: 2),
      ]);
    });

    test('fiyat alarmı yalnız toplam tavan aşılınca; çift sayım yok', () {
      expect(kalemler(fiyat: 20), isEmpty);
      expect(kalemler(fiyat: 19, gosterge: 3), [
        (kalem: PremiumKalem.fiyatAlarmi, sayi: 19),
        (kalem: PremiumKalem.gostergeAlarmi, sayi: 3),
      ]);
    });

    test('çoklu portföy görünmüyorsa portföy kalemi yok', () {
      expect(kalemler(portfoy: null), isEmpty);
    });
  });

  group('sağlayıcı kapısı', () {
    test('paywall kapalıyken boş', () {
      final c = ProviderContainer(overrides: [
        paywallVisibleProvider.overrideWithValue(false),
        effectivePremiumProvider.overrideWithValue(true),
      ]);
      addTearDown(c.dispose);
      expect(c.read(premiumKullanimProvider), isEmpty);
    });

    test('Premium erişimi yokken (bitmiş) boş', () {
      final c = ProviderContainer(overrides: [
        paywallVisibleProvider.overrideWithValue(true),
        effectivePremiumProvider.overrideWithValue(false),
      ]);
      addTearDown(c.dispose);
      expect(c.read(premiumKullanimProvider), isEmpty);
    });
  });

  test('metin: " · " ile dizilir, boşta null', () {
    final l = AppLocalizationsTr();
    expect(premiumKullanimMetni(l, const []), isNull);
    expect(
        premiumKullanimMetni(l, [
          (kalem: PremiumKalem.varlik, sayi: 14),
          (kalem: PremiumKalem.gostergeAlarmi, sayi: 3),
          (kalem: PremiumKalem.portfoy, sayi: 2),
        ]),
        "Premium'la kullandıkların: 14 varlık · 3 gösterge alarmı · 2 portföy");
  });

  group('abonelik satırında', () {
    setUpAll(() => initializeDateFormatting('tr'));
    final hak = PremiumHakki(
      kaynak: 'revenuecat',
      bitis: DateTime(2026, 12, 19),
      urun: 'sandik_premium_aylik',
      magaza: 'app_store',
    );

    Future<void> kur(WidgetTester t, List<PremiumKullanim> k,
            {double olcek = 1}) =>
        t.pumpWidget(ProviderScope(
          overrides: [
            abonelikDonemiProvider.overrideWith(
                (_) async => const AbonelikDonemi(deneme: false)),
            premiumKullanimProvider.overrideWithValue(k),
          ],
          child: MaterialApp(
            theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
            locale: const Locale('tr'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(olcek)),
                child: child!),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: PremiumAbonelikSatiri(hak: hak))),
          ),
        ));

    testWidgets('kalem varsa tek satır görünür', (t) async {
      await kur(t, [(kalem: PremiumKalem.varlik, sayi: 14)]);
      await t.pump();
      expect(find.text("Premium'la kullandıkların: 14 varlık"), findsOneWidget);
    });

    testWidgets('kalem yoksa satır yok', (t) async {
      await kur(t, const []);
      await t.pump();
      expect(find.textContaining('kullandıkların'), findsNothing);
    });

    testWidgets('Dynamic Type 2× taşma yok', (t) async {
      await kur(
          t,
          [
            (kalem: PremiumKalem.varlik, sayi: 14),
            (kalem: PremiumKalem.gostergeAlarmi, sayi: 3),
            (kalem: PremiumKalem.portfoy, sayi: 2),
          ],
          olcek: 2);
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });
}
