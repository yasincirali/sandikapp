import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/screens/paywall_screen.dart'
    show DenemeCizelgesi;
import 'package:portfoy_takip/services/deneme_hatirlatici.dart';
import 'package:portfoy_takip/services/notification_service.dart';
import 'package:portfoy_takip/services/satin_alma_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Deneme bitiş hatırlatması (Ar-Ge 14 Kas #3): denemede ve iptal
/// edilmemişken bitişten 2 gün önce TEK yerel bildirim; iptalde kaldırılır,
/// izin yoksa sessiz, bitişe 2 günden az kaldıysa kurulmaz, sabit kimlik.
/// Paywall çizelgesinde "N−2. gün · Hatırlatırız" düğümü.
class _SahtePlatform implements YerelBildirimPlatformu {
  _SahtePlatform({this.izin = true});

  bool izin;
  final planlar = <({int id, DateTime zaman, String govde, String payload})>[];
  final iptaller = <int>[];

  @override
  Future<bool> izinVar() async => izin;

  @override
  Future<void> planla({
    required int id,
    required DateTime zaman,
    required String baslik,
    required String govde,
    required String payload,
  }) async =>
      planlar.add((id: id, zaman: zaman, govde: govde, payload: payload));

  @override
  Future<void> iptal(int id) async => iptaller.add(id);
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  final simdi = DateTime(2026, 11, 14, 10);
  final bitis = DateTime(2026, 11, 21, 10);

  AbonelikDonemi deneme({
    bool yenilenecek = true,
    DateTime? b,
    String? tutar = '₺649,99',
  }) =>
      AbonelikDonemi(
          deneme: true,
          bitis: b ?? bitis,
          yenilenecek: yenilenecek,
          ilkOdemeTutari: tutar);

  group('zaman kararı', () {
    test('denemede, yenilenecekken: bitişten 2 gün önce', () {
      expect(denemeHatirlatmaZamani(deneme(), simdi),
          bitis.subtract(const Duration(days: 2)));
    });

    test('iptal edilmiş, ücretli dönem ya da bitiş bilinmiyorsa yok', () {
      expect(denemeHatirlatmaZamani(deneme(yenilenecek: false), simdi), isNull);
      expect(
          denemeHatirlatmaZamani(
              AbonelikDonemi(deneme: false, bitis: bitis, yenilenecek: true),
              simdi),
          isNull);
      expect(
          denemeHatirlatmaZamani(
              const AbonelikDonemi(deneme: true, yenilenecek: true), simdi),
          isNull);
    });

    test('bitişe 2 günden az kaldıysa yok', () {
      expect(
          denemeHatirlatmaZamani(
              deneme(b: simdi.add(const Duration(days: 1, hours: 23))), simdi),
          isNull);
    });
  });

  group('hatırlatıcı', () {
    final l10n = AppLocalizationsTr();

    test('kurar: sabit kimlik, Profil payload, mağaza tutarı', () async {
      final p = _SahtePlatform();
      await DenemeHatirlatici(p).guncelle(deneme(), l10n: l10n, simdi: simdi);
      expect(p.planlar, hasLength(1));
      final plan = p.planlar.single;
      expect(plan.id, DenemeHatirlatici.bildirimId);
      expect(plan.zaman, DateTime(2026, 11, 19, 10));
      expect(plan.payload, NotificationService.denemeHatirlatmaPayload);
      expect(
          plan.govde,
          'Ücretsiz denemen 21 Kasım tarihinde bitiyor; sonra ₺649,99. Devam '
          'etmek istemezsen mağazanın abonelik sayfasından iptal edebilirsin.');
    });

    test('yeniden çağrı aynı kimlikle kurar (idempotent)', () async {
      final p = _SahtePlatform();
      final h = DenemeHatirlatici(p);
      await h.guncelle(deneme(), l10n: l10n, simdi: simdi);
      await h.guncelle(deneme(), l10n: l10n, simdi: simdi);
      expect(p.planlar.map((e) => e.id).toSet(), {DenemeHatirlatici.bildirimId});
    });

    test('tutar bilinmiyorsa tutarsız metin', () async {
      final p = _SahtePlatform();
      await DenemeHatirlatici(p)
          .guncelle(deneme(tutar: null), l10n: l10n, simdi: simdi);
      expect(p.planlar.single.govde, isNot(contains('₺')));
      expect(p.planlar.single.govde, contains('21 Kasım'));
    });

    test('iptal edilmiş deneme: kurulmaz, var olan kaldırılır', () async {
      final p = _SahtePlatform();
      await DenemeHatirlatici(p)
          .guncelle(deneme(yenilenecek: false), l10n: l10n, simdi: simdi);
      expect(p.planlar, isEmpty);
      expect(p.iptaller, [DenemeHatirlatici.bildirimId]);
    });

    test('izin yoksa sessiz: kurulmaz', () async {
      final p = _SahtePlatform(izin: false);
      await DenemeHatirlatici(p).guncelle(deneme(), l10n: l10n, simdi: simdi);
      expect(p.planlar, isEmpty);
    });

    test('dönem bilinmiyorsa hiçbir şeye dokunulmaz', () async {
      final p = _SahtePlatform();
      await DenemeHatirlatici(p).guncelle(null, l10n: l10n, simdi: simdi);
      expect(p.planlar, isEmpty);
      expect(p.iptaller, isEmpty);
    });
  });

  group('paywall çizelgesi', () {
    Future<void> kur(WidgetTester t, int gun, {double olcek = 1}) async {
      t.view.physicalSize = const Size(390 * 2, 844 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
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
                padding: const EdgeInsets.all(16),
                child: DenemeCizelgesi(gun: gun))),
      ));
      await t.pump();
    }

    testWidgets('7 günlük deneme: 5. gün hatırlatırız', (t) async {
      await kur(t, 7);
      expect(find.text('5. gün'), findsOneWidget);
      expect(find.text('Hatırlatırız'), findsOneWidget);
      expect(find.text('7. gün'), findsOneWidget);
    });

    testWidgets('gün deneme süresinden türetilir', (t) async {
      await kur(t, 14);
      expect(find.text('12. gün'), findsOneWidget);
    });

    testWidgets('2 günlük denemede hatırlatma vaat edilmez', (t) async {
      await kur(t, 2);
      expect(find.text('Hatırlatırız'), findsNothing);
    });

    testWidgets('Dynamic Type 2× taşma yok, alt alta', (t) async {
      await kur(t, 7, olcek: 2);
      expect(t.takeException(), isNull);
      expect(find.text('Hatırlatırız'), findsOneWidget);
    });
  });
}
