import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/fon_xray_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/paywall_screen.dart';
import 'package:portfoy_takip/services/fon_dagilimi.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sandik_error_view.dart';
import 'package:portfoy_takip/widgets/zirve_icerik_karti.dart';
import 'package:portfoy_takip/widgets/zirve_varlik_siralamasi.dart';

import 'helpers/kaynak.dart';

/// Ar-Ge 22 Kas 2203 (UI/UX turu 13): Zirve'nin Premium kapıları ve
/// paywall destesinin kaynak→kart eşlemesi.
void main() {
  group('#1 kaynaktanKart: dokunulan kilidin kartı önde', () {
    test('yeni eşlemeler', () {
      const beklenen = {
        'zirve_xray': PaywallKarti.zirve,
        'gosterge_alarmi': PaywallKarti.sinyal,
        'cizim_alarmi': PaywallKarti.sinyal,
        'alarm_gosterge_duzenle': PaywallKarti.sinyal,
        'alarm_sayaci': PaywallKarti.varlik,
        'portfoy_yorumu': PaywallKarti.xray,
        'varlik_yorumu': PaywallKarti.xray,
        // Taramada bulundu: kapanış özetindeki kilitli rapor bağlantısı.
        'kapanis_rapor': PaywallKarti.rapor,
      };
      beklenen.forEach((k, kart) => expect(kaynaktanKart(k), kart, reason: k));
    });

    test('hedef kaynakları bilerek eşlemesiz (destede hedef kartı yok)', () {
      expect(kaynaktanKart('portfoy_hedef'), isNull);
      expect(kaynaktanKart('hedef_tarihi'), isNull);
    });

    // Tetikleyicisiz: dokunulan belirli bir özellik yok (profil bandı,
    // abonelik/hediye satırları) ya da destede karşılığı yok (hedef). Bu
    // listeye ekleme bilinçli olmalı; yeni kilit sessizce persona sırasına
    // düşmesin diye lib taranır.
    const tetikleyicisiz = {
      'profile_banner',
      'hediye_bitti',
      'premium_bitti',
      'hediye_bitiyor',
      'profil_yillik_tasarruf',
      'portfoy_hedef',
      'hedef_tarihi',
    };

    test('lib\'deki her paywall kaynağı eşlenmiş ya da bilinçli listede', () {
      final cagri = RegExp(r'PaywallScreen\.show\((.*?)\);', dotAll: true);
      final kilit = RegExp(
          r'(?:KilitSatiri(?:\.ac)?|PremiumKilitKarti|BasaBasSatiri|sinirUyarisi)\((?:(?!;).)*?kaynak:\s*'
          r"'([a-z0-9_]+)('|\$)",
          dotAll: true);
      // Kapanan tırnak ya da ara değer şart: `reason: 'x.y'` gibi analitik
      // etiketleri kaynak sanılmasın.
      final literal = RegExp(r"'([a-z0-9_]+)('|\$)");
      final bulunan = <String, String>{}; // kaynak → dosya
      final libMetni = StringBuffer();
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final metin = ekranKaynagiSync(f.path);
        libMetni.write(metin);
        void ekle(String k, bool araDeger) =>
            // `'asset_limit_${e.limit}'` gibi ara değerli kaynakta önek
            // sınanır: bir sonek eklenmiş hâli eşlenmeli.
            bulunan[araDeger ? '${k}x' : k] = f.path;
        for (final m in cagri.allMatches(metin)) {
          for (final l in literal.allMatches(m.group(1)!)) {
            ekle(l.group(1)!, l.group(2) == r'$');
          }
        }
        for (final m in kilit.allMatches(metin)) {
          ekle(m.group(1)!, m.group(2) == r'$');
        }
      }
      // Tarama gerçekten çalışıyor mu: bilinen kaynaklar bulundu.
      expect(bulunan.keys, containsAll(['zirve', 'zirve_xray', 'fon_xray']));
      expect(bulunan.length, greaterThan(40));
      final eslemesiz = [
        for (final e in bulunan.entries)
          if (kaynaktanKart(e.key) == null && !tetikleyicisiz.contains(e.key))
            '${e.key} (${e.value})',
      ];
      expect(eslemesiz, isEmpty,
          reason: 'Yeni paywall kaynağı ya kaynaktanKart\'ta bir karta '
              'eşlenir ya da gerekçesiyle tetikleyicisiz listesine girer.');
      // Listede bayat kayıt kalmasın.
      final lib = libMetni.toString();
      for (final k in tetikleyicisiz) {
        expect(lib.contains("'$k'"), isTrue, reason: '$k artık lib\'de yok');
      }
    });
  });

  group('#2 rıza okumasında Premium satırı', () {
    final ekran = ekranKaynagiSync('lib/screens/zirve_portfoyler_screen.dart');

    test('satır kartın dışında, yalnız ilk katılımda', () {
      expect(ekran, contains('context.l10n.zirveKatilimPremiumNotu'));
      // Yeniden onay okumasında verilmez: o kullanıcı zaten katılımcı.
      expect('premiumNotu: katilimPremiumla'.allMatches(ekran).length, 1);
      // `_katil`'in paywall koşuluyla aynı.
      expect(
          ekran,
          contains('ref.watch(premiumKilitliProvider) &&\n'
              '        !(_erisim?.ilkUye ?? false)'));
      // Kart yasal metnin kendisi; satır karta yazılmaz.
      final kart = ekranKaynagiSync('lib/widgets/zirve_riza_karti.dart');
      expect(kart, isNot(contains('zirveKatilimPremiumNotu')));
    });

    test('metin iki dilde', () {
      expect(trMetni('zirveKatilimPremiumNotu'),
          "Zirve'ye katılım Premium ile. Metni okuyup onayladığında "
          'Premium sayfası açılır.');
    });
  });

  group('#3 Fonların içi: hata ve yayımlanmamış hâl', () {
    test('sağlayıcı hatayı yutmaz, raporlar ve fırlatır', () {
      final p = ekranKaynagiSync('lib/providers/fon_xray_provider.dart');
      final blok = p.substring(p.indexOf('final zirveFonDagilimlariProvider'));
      final govde = blok.substring(0, blok.indexOf('\n});'));
      expect(govde, contains("reason: 'zirveFonDagilimlariProvider'"));
      expect(govde, contains('rethrow;'));
    });

    FonDagilimi d(String kod, Map<String, double> m) => FonDagilimi(
        fonKodu: kod,
        fonTipi: 'YAT',
        tarih: DateTime(2026, 10, 20),
        dagilim: m);

    Future<void> kur(WidgetTester t,
        Future<Map<String, FonDagilimi>> Function() okuma) async {
      t.view.physicalSize = const Size(390, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          fonXrayGorunurProvider.overrideWithValue(true),
          premiumKilitliProvider.overrideWithValue(false),
          zirveFonDagilimlariProvider.overrideWith((ref, _) => okuma()),
        ],
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('tr'),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ZirveIcerikKarti(
                pay: {'fon': 40.0, 'hisse': 60.0},
                fonDetay: {'AFT': 40.0},
                varlikDetay: {},
              ),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('hata: tek satır + yeniden dene, dokununca yeniden okur',
        (t) async {
      var okuma = 0;
      await kur(t, () async {
        okuma++;
        throw Exception('ag');
      });
      expect(find.text('Fonların içi şu an okunamadı'), findsOneWidget);
      expect(find.byType(SandikErrorView), findsOneWidget);
      final once = okuma;
      await t.tap(find.text('Tekrar dene'));
      await t.pumpAndSettle();
      expect(okuma, greaterThan(once));
    });

    testWidgets('veri var ama hiçbir fon açılmadı: gerçek durum tek satır',
        (t) async {
      await kur(t, () async => {'XYZ': d('XYZ', const {'hs': 100})});
      expect(find.text('Bu fonların dağılımı henüz yayımlanmadı'),
          findsOneWidget);
      expect(find.text('Fonların içinde ne var'), findsNothing);
    });
  });

  group('#4 çift paywall yok', () {
    test('onKilitli Future; düğme doğrudan bekler', () {
      final ekran =
          ekranKaynagiSync('lib/screens/zirve_portfoyler_screen.dart');
      expect(ekran, isNot(contains('VoidCallback onKilitli')));
      expect(ekran, isNot(contains('onPressed: () async => onKilitli()')));
      expect(ekran, contains('onPressed: onKilitli,'));
      final s = ekranKaynagiSync('lib/widgets/zirve_varlik_siralamasi.dart');
      expect(s, contains('final Future<void> Function()? onKilitli;'));
    });
  });

  group('#5 "Premium\'da görünür" yalnız ilk kilitli satırda', () {
    Future<void> kur(WidgetTester t, Widget w) async {
      t.view.physicalSize = const Size(390 * 3, 1400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        home: Scaffold(body: SingleChildScrollView(child: w)),
      ));
      await t.pumpAndSettle();
    }

    Future<String?> adYok(String _) async => null;

    for (final gruplu in [false, true]) {
      testWidgets(gruplu ? 'gruplu' : 'sıralı', (t) async {
        var acildi = 0;
        await kur(
            t,
            ZirveVarlikSiralamasi(
              fonDetay: const {'?1': 9.0},
              varlikDetay: const {
                'hisse': {'THYAO.IS': 21.0, '?2': 14.0, '?3': 12.0},
              },
              pay: const {'hisse': 47.0, 'fon': 9.0},
              gruplu: gruplu,
              onKilitli: () async => acildi++,
              adBul: adYok,
            ));
        expect(find.text(ZirveKiyas.kilitliYer), findsNWidgets(3));
        expect(find.text("Premium'da görünür"), findsOneWidget);
        // Ekran okuyucu etiketi ve dokunuş her satırda aynı.
        for (final y in ['%14', '%12', '%9']) {
          expect(find.bySemanticsLabel("Kilitli varlık $y. Premium'da görünür."),
              findsOneWidget);
        }
        await t.tap(find.text(ZirveKiyas.kilitliYer).last);
        await t.pump();
        expect(acildi, 1);
      });
    }
  });

  test('#6 Zirve rıza kartında w700 kalmadı', () {
    expect(ekranKaynagiSync('lib/widgets/zirve_riza_karti.dart'),
        isNot(contains('FontWeight.w700')));
  });
}
