import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/fon_xray_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/fon_dagilimi.dart';
import 'package:portfoy_takip/services/zirve_icerik.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/premium_kilit_karti.dart';
import 'package:portfoy_takip/widgets/zirve_icerik_karti.dart';

/// Zirve "fonların içi açılınca" (yasin 2026-10-20): fon ve BES TEFAS
/// dağılımıyla açılır, bilinmeyen pay dağıtılmaz, hisse BIST/yurt dışı
/// sembolden; kart Fon X-Ray kapısıyla aynı dört hâl.
FonDagilimi _d(String kod, Map<String, double> d) => FonDagilimi(
    fonKodu: kod, fonTipi: 'YAT', tarih: DateTime(2026, 10, 20), dagilim: d);

final _dagilimlar = {
  // Hisse yoğun fon: %80 BIST, %20 repo.
  'AFT': _d('AFT', const {'hs': 80, 'tr': 20}),
  // Yabancı hisse fonu, toplamı 90 (10 bilinmeyen).
  'YAY': _d('YAY', const {'yhs': 90}),
  // BES: yarı devlet tahvili yarı altın.
  'AEA': _d('AEA', const {'dt': 50, 'km': 50}),
};

const _pay = {'hisse': 30.0, 'fon': 40.0, 'bes': 20.0, 'kripto': 10.0};
const _fon = {'AFT': 20.0, 'YAY': 10.0, 'XYZ': 5.0, 'DIGER': 5.0};
const _varlik = {
  'hisse': {'THYAO.IS': 15.0, 'AAPL': 10.0, 'DIGER': 5.0},
  'bes': {'AEA': 20.0},
  'kripto': {'BTCUSDT': 10.0},
};

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('zirveIcerigi', () {
    final x = zirveIcerigi(
        pay: _pay,
        fonDetay: _fon,
        varlikDetay: _varlik,
        dagilimlar: _dagilimlar);

    test('fon ve BES kovalara açılır; doğrudan türler kendi kovasında', () {
      expect(x.kovalar[XrayKova.bistHisse], closeTo(15 + 5 + 16, 1e-9));
      expect(x.kovalar[XrayKova.yabanciHisse], closeTo(10 + 9, 1e-9));
      // Para piyasası sade grupta mevduatla birlikte ("Mevduat ve nakit").
      expect(x.kovalar[XrayKova.paraPiyasasi], isNull);
      expect(x.kovalar[XrayKova.mevduat], closeTo(4, 1e-9));
      expect(x.kovalar[XrayKova.devletBorclanma], closeTo(10, 1e-9));
      expect(x.kovalar[XrayKova.kiymetliMaden], closeTo(10, 1e-9));
      expect(x.kovalar[XrayKova.kripto], closeTo(10, 1e-9));
    });

    test('bilinmeyen pay hiçbir kovaya dağıtılmaz', () {
      // XYZ (dağılım yok) 5 + DIGER 5 + YAY'ın eksik %10'u 1 = 11.
      expect(x.bilinmeyen, closeTo(11, 1e-9));
      final toplam = x.kovalar.values.fold(0.0, (a, b) => a + b);
      expect(toplam + x.bilinmeyen, closeTo(100, 1e-9));
    });

    test('kaynaklar: doğrudan önce, sonra fonlar büyükten küçüğe', () {
      final k = x.kaynaklariSirali(XrayKova.bistHisse);
      expect(k.map((e) => e.key).toList(), [zirveDogrudan, 'AFT']);
      expect(k.first.value, closeTo(20, 1e-9));
      final h = x.hisse();
      expect(h.toplam, closeTo(55, 1e-9));
      expect(h.fonlardan, closeTo(25, 1e-9));
      expect(x.tarih, DateTime(2026, 10, 20));
    });

    test('gizli kod ve DIGER sorulmaz; BES kodu sorulur', () {
      expect(
          zirveFonKodlari(const {
            'AFT': 1,
            '?1': 2,
            'DIGER': 3
          }, const {
            'bes': {'AEA': 1, '?2': 1}
          }),
          ['AEA', 'AFT']);
    });

    test('dağılım hiç yoksa açılmaz; fon/BES yoksa açılacak bir şey yok', () {
      final y = zirveIcerigi(
          pay: _pay, fonDetay: _fon, varlikDetay: _varlik, dagilimlar: {});
      expect(y.acildi, isFalse);
      expect(y.bilinmeyen, closeTo(60, 1e-9));
      final z = zirveIcerigi(
          pay: const {'hisse': 100},
          fonDetay: const {},
          varlikDetay: const {},
          dagilimlar: _dagilimlar);
      expect(z.acilacakVar, isFalse);
      expect(z.kovalar[XrayKova.bistHisse], 100);
    });

    test('tür payının koda bölünmemiş kalanı: fon bilinmeyen, hisse BIST', () {
      final y = zirveIcerigi(
          pay: const {'fon': 50, 'hisse': 50},
          fonDetay: const {'AFT': 30},
          varlikDetay: const {},
          dagilimlar: _dagilimlar);
      expect(y.bilinmeyen, closeTo(20, 1e-9));
      expect(y.kovalar[XrayKova.bistHisse], closeTo(50 + 24, 1e-9));
    });
  });

  group('ZirveIcerikKarti — dört hâl', () {
    var okuma = 0;
    Future<void> kur(WidgetTester t,
        {required bool gorunur,
        bool kilitli = false,
        double olcek = 1,
        Map<String, double> pay = _pay}) async {
      okuma = 0;
      t.view.physicalSize = const Size(390, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          fonXrayGorunurProvider.overrideWithValue(gorunur),
          premiumKilitliProvider.overrideWithValue(kilitli),
          zirveFonDagilimlariProvider.overrideWith((ref, kodlar) async {
            okuma++;
            return _dagilimlar;
          }),
        ],
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('tr'),
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(olcek)),
              child: child!),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ZirveIcerikKarti(
                  pay: pay, fonDetay: _fon, varlikDetay: _varlik),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('Premium görünmüyor: hiçbir şey, veri okunmaz', (t) async {
      await kur(t, gorunur: false);
      expect(find.text('FONLARIN İÇİNDE NE VAR'), findsNothing);
      expect(okuma, 0);
    });

    testWidgets('kilitli: kilit kartı, sayı yok, veri okunmaz', (t) async {
      await kur(t, gorunur: true, kilitli: true);
      expect(find.byType(PremiumKilitKarti), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(okuma, 0);
    });

    testWidgets('açık: sınıflar, kaynaklar ve özet cümlesi', (t) async {
      await kur(t, gorunur: true);
      expect(find.text('FONLARIN İÇİNDE NE VAR'), findsOneWidget);
      expect(
          find.text('Hisse payı listede %30, fonların içindekilerle birlikte '
              '%55.'),
          findsOneWidget);
      expect(find.text('Kendi aldığı %20 · AFT %16'), findsOneWidget);
      expect(find.text('İçi bilinmeyen fonlar'), findsOneWidget);
      expect(find.textContaining('TEFAS'), findsOneWidget);
    });

    testWidgets('fon/BES yoksa çizilmez', (t) async {
      await kur(t, gorunur: true, pay: const {'hisse': 100});
      expect(find.text('FONLARIN İÇİNDE NE VAR'), findsNothing);
    });

    testWidgets('×2 ve ×3,1 yazıda taşma yok', (t) async {
      for (final o in [2.0, 3.1]) {
        await kur(t, gorunur: true, olcek: o);
        expect(t.takeException(), isNull);
      }
    });
  });

  test('döviz para birimine ayrılır; birimi bilinmeyen doğrudan kalır', () {
    final x = zirveIcerigi(
      pay: const {'doviz': 10, 'fon': 10},
      fonDetay: const {'AFT': 10},
      varlikDetay: const {
        'doviz': {'USDTRY=X': 6, 'EURTRY=X': 3}
      },
      dagilimlar: _dagilimlar,
    );
    expect(x.kovalar[XrayKova.doviz], closeTo(10, 1e-9));
    final k = x.kaynaklariSirali(XrayKova.doviz);
    expect(k.map((e) => e.key).toList(),
        ['${zirveKurOneki}USD', '${zirveKurOneki}EUR', zirveDogrudan]);
    expect(k.last.value, closeTo(1, 1e-9));
    expect(zirveKurKodu(k.first.key), 'USD');
    expect(zirveKurKodu('AFT'), isNull);
    // Döviz doğrudan sayılır: hisse özetinin "fonlardan" kısmına girmez.
    expect(x.hisse().fonlardan, closeTo(8, 1e-9));
  });
}
