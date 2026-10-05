import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/config/pref_keys.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/fon_akisi_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show initPreferencesCache;
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/hacim_detay_screen.dart';
import 'package:portfoy_takip/services/hisse_hacmi.dart';
import 'package:portfoy_takip/services/radar_okuma.dart';
import 'package:portfoy_takip/widgets/radar_ortak.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/hacim_radari_karti.dart';

import 'helpers/kaynak.dart';

/// Hacim radarı (Balina B2): saf özet + kart.
///
/// ## Kilitlenen davranışlar
/// 1. Ortalama, son günden ÖNCEKİ 20 işlem günüdür (sunucu kuralıyla aynı
///    pencere); 20 gün yoksa kat gösterilmez.
/// 2. Veri yok / bayat / BIST dışı → kart yok; bayrak kapalıyken sorgu yok.
/// 3. Dil: "giriş/çıkış" ve "balina" yok; kart cümle → sayı → ölçek düzeninde
///    (S4-B), kripto halat + saatlik net alım (S5-A), kilitliyken seyir yok.
/// 4. Fon olay sorgusu hisse satırı, hisse sorgusu fon satırı okumaz.
DateTime _g(int ay, int gun) => DateTime.utc(2026, ay, gun);

/// [n] ardışık gün; para hacmi sabit [taban], son gün [son].
List<HacimGunu> _seri(int n, {double taban = 100e6, double son = 320e6}) => [
      for (var i = 0; i < n; i++)
        HacimGunu(
          tarih: DateTime.utc(2026, 9, 2 + i),
          kapanis: i == n - 1 ? 10.4 : 10,
          paraHacmi: i == n - 1 ? son : taban,
        ),
    ];

HacimOlayi _olay(int ay, int gun, {bool yukselis = true}) => HacimOlayi(
    tarih: _g(ay, gun),
    yukselis: yukselis,
    paraHacmi: 35.46e9,
    ortalamaKati: 4.7,
    fiyatDegisim: yukselis ? 0.0997 : -0.0673);

int _sorgu = 0;

Future<void> _kur(
  WidgetTester t, {
  Widget kart =
      const HacimRadariKarti(tur: AssetType.hisse, ticker: 'thyao.is'),
  bool acik = true,
  HacimOzeti? ozet,
  bool veriYok = false,
  double genislik = 390,
  double olcek = 1,
  Locale dil = const Locale('tr'),
  bool kilitli = false,
}) async {
  SharedPreferences.setMockInitialValues({PrefKeys.radarKocuGoruldu: true});
  await initPreferencesCache();
  _sorgu = 0;
  final simdi = DateTime(2026, 9, 24);
  t.view.physicalSize = Size(genislik, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      balinaRadariAcikProvider.overrideWithValue(acik),
      radarKilitliProvider.overrideWithValue(kilitli),
      hisseHacmiProvider.overrideWith((ref, sembol) async {
        _sorgu++;
        expect(sembol, 'THYAO.IS');
        return veriYok
            ? null
            : (ozet ?? hacimOzeti(_seri(21), const [], simdi: simdi));
      }),
    ],
    child: MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: dil,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(olcek)),
        child: child!,
      ),
      home: kart is HacimDetayScreen
          ? kart
          : Scaffold(
              body: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
                child: kart,
              ),
            ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  final simdi = DateTime(2026, 9, 24);

  group('hacimOzeti', () {
    test('ortalama = son günden önceki 20 gün; kat ve fiyat değişimi', () {
      final o = hacimOzeti(_seri(21), const [], simdi: simdi)!;
      expect(o.ortalama, 100e6);
      expect(o.kat, closeTo(3.2, 1e-9));
      expect(o.fiyatDegisim, closeTo(0.04, 1e-9));
      expect(o.gunler, hasLength(grafikGun));
      expect(o.gunler.last, same(o.sonGun));
    });

    test('20 önceki gün yoksa ortalama ve kat YOK (kısa pencereden uydurulmaz)',
        () {
      final o = hacimOzeti(_seri(20), const [], simdi: simdi)!;
      expect(o.ortalama, isNull);
      expect(o.kat, isNull);
      expect(o.sonGun.paraHacmi, 320e6);
    });

    test('veri yoksa ya da bayatsa özet yok', () {
      expect(hacimOzeti(const [], const [], simdi: simdi), isNull);
      // Son gün 22 Eylül; 12 günden eski.
      expect(hacimOzeti(_seri(21), const [], simdi: DateTime(2026, 10, 6)),
          isNull);
    });

    test('olaylar: son 30 gün, yeniden eskiye, en çok 4', () {
      final o = hacimOzeti(
        _seri(21),
        [
          _olay(8, 1), // 30 günden eski
          _olay(9, 3),
          _olay(9, 19),
          _olay(9, 10),
          _olay(9, 5),
          _olay(9, 15),
        ],
        simdi: simdi,
      )!;
      expect(o.olaylar.map((e) => e.tarih),
          [_g(9, 19), _g(9, 15), _g(9, 10), _g(9, 5)]);
    });

    test('satır ayrıştırma: bozuk satır atılır, fon türü hisse olayı değildir',
        () {
      expect(
          HacimGunu.satirdan({
            'tarih': '2026-10-02',
            'kapanis': 310.5,
            'para_hacmi': 4.8e9
          })!
              .paraHacmi,
          4.8e9);
      expect(HacimGunu.satirdan({'tarih': '2026-10-02', 'kapanis': 0}), isNull);
      final o = HacimOlayi.satirdan({
        'tarih': '2026-10-01',
        'tur': 'hisse_hacim_dusus',
        'tutar': 30.2e9,
        'ortalama_kati': 3.1,
        'fiyat_degisim': -0.0673,
      })!;
      expect(o.yukselis, isFalse);
      expect(
          HacimOlayi.satirdan({
            'tarih': '2026-10-01',
            'tur': 'fon_giris',
            'tutar': 1e9,
            'ortalama_kati': 3.1,
            'fiyat_degisim': 0.1,
          }),
          isNull);
    });
  });

  testWidgets('kart (S4-B): cümle, sayı, gün kademesi, ölçek, seyir',
      (t) async {
    await _kur(t);
    expect(find.text('HACİM RADARI'), findsOneWidget);
    expect(
        find.text('22 Eyl günü bu hissede olağanın çok üstünde işlem yapıldı.'),
        findsOneWidget);
    expect(find.text('₺320,00M'), findsOneWidget);
    expect(find.text('Çok hareketli gün'), findsOneWidget);
    expect(find.text('para hacmi · fiyat +%4,0'), findsOneWidget);
    expect(find.byType(OlcekCubugu), findsOneWidget);
    expect(find.byType(GunCubuklari), findsOneWidget);
    expect(
        find.text('kesikli çizgi: önceki 20 günün ortalaması'), findsOneWidget);
    expect(find.textContaining('Yahoo Finance · 22 Eyl · tavsiye değildir'),
        findsOneWidget);
    // Hissede yön dili yok: hacim giriş/çıkış değildir.
    expect(find.textContaining('girdi'), findsNothing);
    expect(find.textContaining('çıktı'), findsNothing);
  });

  testWidgets('20 gün dolmadıysa ölçek yok, cümle yalın', (t) async {
    final kisa = hacimOzeti(_seri(8), const [], simdi: DateTime(2026, 9, 12));
    await _kur(t, ozet: kisa);
    expect(find.byType(OlcekCubugu), findsNothing);
    expect(find.text('9 Eyl günü bu hissede ₺320,00M tutarında işlem yapıldı.'),
        findsOneWidget);
  });

  testWidgets('kilitli: sayı açık, seyir kilitli', (t) async {
    await _kur(t, kilitli: true);
    expect(find.text('₺320,00M'), findsOneWidget);
    expect(find.byType(GunCubuklari), findsNothing);
    expect(find.text("Ayrıntılar Premium'da"), findsOneWidget);
  });

  testWidgets('bayrak kapalıyken çizilmez ve sorgu başlamaz', (t) async {
    await _kur(t, acik: false);
    expect(find.byType(SandikCard), findsNothing);
    expect(_sorgu, 0);
  });

  testWidgets('veri yoksa yer kaplamaz', (t) async {
    await _kur(t, veriYok: true);
    expect(find.byType(SandikCard), findsNothing);
    expect(t.getSize(find.byType(HacimRadariKarti)).height, 0);
  });

  testWidgets('BIST dışı hisse ve fon için çizilmez, sorgu yok', (t) async {
    await _kur(t,
        kart: const HacimRadariKarti(tur: AssetType.hisse, ticker: 'AAPL'));
    expect(find.byType(SandikCard), findsNothing);
    await _kur(t,
        kart: const HacimRadariKarti(tur: AssetType.fon, ticker: 'TEFAS:TTE'));
    expect(find.byType(SandikCard), findsNothing);
    expect(_sorgu, 0);
  });

  testWidgets('dar ekran (320) ve büyük yazı (1,6×) taşmaz', (t) async {
    await _kur(t,
        genislik: 320,
        olcek: 1.6,
        ozet: hacimOzeti(_seri(21), [_olay(9, 19)], simdi: simdi));
    expect(t.takeException(), isNull);
  });

  testWidgets('İngilizce: metinler çevrili', (t) async {
    await _kur(t, dil: const Locale('en'));
    expect(find.text('VOLUME RADAR'), findsOneWidget);
    expect(find.text('On 22 Sep this stock traded far more than usual.'),
        findsOneWidget);
  });

  group('hisse ayrıntı', () {
    testWidgets('kat, güne dokunma (fiyat önceki kapanışa göre), olaylar',
        (t) async {
      await _kur(t,
          kart: const HacimDetayScreen(anahtar: 'THYAO.IS', kripto: false),
          ozet: hacimOzeti(
              _seri(21), [_olay(9, 19), _olay(9, 10, yukselis: false)],
              simdi: simdi));
      expect(find.text('THYAO · Hacim radarı'), findsOneWidget);
      expect(
          find.text('Önceki 20 günün ortalamasının 3,2 katı'), findsOneWidget);
      final gunler = find.descendant(
          of: find.byType(GunCubuklari),
          matching: find.byType(GestureDetector));
      await t.tap(gunler.last);
      await t.pumpAndSettle();
      expect(find.text('22 Eyl: ₺320,00M · fiyat +%4,0'), findsOneWidget);
      // Grafiğin ilk gününün öncesi seride yok: fiyat yazılmaz.
      await t.tap(gunler.first);
      await t.pumpAndSettle();
      expect(find.text('3 Eyl: ₺100,00M'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Olağandışı hacim · 19 Eyl'), 200);
      expect(find.text('₺35,46Mr · ortalamanın 4,7 katı · fiyat +%10,0'),
          findsOneWidget);
      expect(find.text('₺35,46Mr · ortalamanın 4,7 katı · fiyat −%6,7'),
          findsOneWidget);
    });

    testWidgets('olay yoksa bunu söyler; dar ekran taşmaz', (t) async {
      await _kur(t,
          kart: const HacimDetayScreen(anahtar: 'THYAO.IS', kripto: false),
          genislik: 320,
          olcek: 1.6);
      expect(t.takeException(), isNull);
      await t.scrollUntilVisible(
          find.text('Son 30 günde olağandışı hacim günü yok.'), 200);
    });
  });

  group('kripto alıcı baskısı kartı', () {
    HacimOzeti kriptoOzet() => hacimOzeti(
          [
            for (var i = 0; i < 21; i++)
              HacimGunu(
                tarih: DateTime.utc(2026, 9, 2 + i),
                kapanis: 60000,
                paraHacmi: i == 20 ? 2.62e9 : 1e9,
                aliciPayi: i >= 14 ? 0.52 : 0.49,
              ),
          ],
          [
            HacimOlayi(
                tarih: _g(9, 21),
                yukselis: true,
                paraHacmi: 2.62e9,
                ortalamaKati: 2.3,
                fiyatDegisim: 0.0729,
                aliciPayi: 0.5183),
          ],
          simdi: simdi,
        )!;

    SaatlikAkis saatlik() => saatlikAkis([
          for (var h = 0; h < 24; h++)
            KriptoSaati(
                saat: DateTime.utc(2026, 9, 22, h),
                paraHacmi: 100e6,
                aliciPayi: h == 3 ? 0.9 : (h.isEven ? 0.55 : 0.45)),
        ], simdi: DateTime.utc(2026, 9, 22, 23, 30))!;

    Future<void> kur(WidgetTester t, Widget kart,
        {HacimOzeti? ozet,
        SaatlikAkis? akis,
        bool kilitli = false,
        double genislik = 390,
        double olcek = 1}) async {
      SharedPreferences.setMockInitialValues({PrefKeys.radarKocuGoruldu: true});
      await initPreferencesCache();
      t.view.physicalSize = Size(genislik, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          balinaRadariAcikProvider.overrideWithValue(true),
          radarKilitliProvider.overrideWithValue(kilitli),
          kriptoBaskiProvider.overrideWith((ref, ticker) async {
            expect(ticker, 'KRIPTO:BTC');
            return ozet;
          }),
          kriptoSaatlikProvider.overrideWith((ref, ticker) async => akis),
        ],
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('tr'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(olcek)),
            child: child!,
          ),
          home: kart is HacimDetayScreen
              ? kart
              : Scaffold(body: SingleChildScrollView(child: kart)),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('kart (S5-A): cümle, halat, 7 gün, ölçek, saatlik', (t) async {
      await kur(t,
          const KriptoBaskiKarti(tur: AssetType.kripto, ticker: 'kripto:btc'),
          ozet: kriptoOzet(), akis: saatlik());
      expect(find.text('ALICI BASKISI'), findsOneWidget);
      expect(find.text('22 Eyl günü alanlar satanlardan daha istekliydi.'),
          findsOneWidget);
      expect(find.text('Alıcı %52,0'), findsOneWidget);
      expect(find.text('Satıcı %48,0'), findsOneWidget);
      expect(find.text('7 günde alıcı payı: %52,0'), findsOneWidget);
      expect(find.byType(OlcekCubugu), findsOneWidget);
      expect(find.byType(SaatlikCubuklar), findsOneWidget);
      // 03:00–04:00: 100 mn × (2 × 0,9 − 1) = +$80 mn.
      expect(
          find.textContaining(
              r'alıcıların en istekli olduğu saat · +$80,00M net alım'),
          findsOneWidget);
      expect(find.textContaining('Binance · son mum'), findsOneWidget);
      expect(find.textContaining('₺'), findsNothing);
    });

    testWidgets('saatlik veri yoksa saatlik bölüm yok, kaynak günlük',
        (t) async {
      await kur(t,
          const KriptoBaskiKarti(tur: AssetType.kripto, ticker: 'KRIPTO:BTC'),
          ozet: kriptoOzet());
      expect(find.byType(SaatlikCubuklar), findsNothing);
      expect(find.textContaining('Binance · 22 Eyl'), findsOneWidget);
    });

    testWidgets('kilitli: halat açık, saatlik kilitli', (t) async {
      await kur(t,
          const KriptoBaskiKarti(tur: AssetType.kripto, ticker: 'KRIPTO:BTC'),
          ozet: kriptoOzet(), akis: saatlik(), kilitli: true);
      expect(find.text('Alıcı %52,0'), findsOneWidget);
      expect(find.byType(SaatlikCubuklar), findsNothing);
      expect(find.text("Ayrıntılar Premium'da"), findsOneWidget);
    });

    testWidgets('ayrıntı: saate dokunma, dolar olaylar, taşma yok', (t) async {
      await kur(t, const HacimDetayScreen(anahtar: 'KRIPTO:BTC', kripto: true),
          ozet: kriptoOzet(), akis: saatlik(), genislik: 320, olcek: 1.6);
      expect(t.takeException(), isNull);
      expect(find.text('BTC · Alıcı baskısı'), findsOneWidget);
      expect(find.text(r'İşlem hacmi $2,62Mr'), findsOneWidget);
      final saatler = find.descendant(
          of: find.byType(SaatlikCubuklar),
          matching: find.byType(GestureDetector));
      await t.scrollUntilVisible(saatler.first, 200);
      await t.tap(saatler.at(3));
      await t.pumpAndSettle();
      expect(find.textContaining(r'+$80,00M · Alıcı %90,0'), findsOneWidget);
      await t.scrollUntilVisible(
          find.text(r'$2,62Mr · ortalamanın 2,3 katı · fiyat +%7,3 · '
              'alıcı payı %51,8'),
          200);
    });

    testWidgets('USDT ve kripto dışı varlıkta çizilmez', (t) async {
      await kur(t,
          const KriptoBaskiKarti(tur: AssetType.kripto, ticker: 'KRIPTO:USDT'),
          ozet: kriptoOzet());
      expect(find.byType(SandikCard), findsNothing);
      await kur(
          t, const KriptoBaskiKarti(tur: AssetType.hisse, ticker: 'THYAO.IS'),
          ozet: kriptoOzet());
      expect(find.byType(SandikCard), findsNothing);
    });

    test('alıcı payı 7 günün hepsinde yoksa ortalama verilmez', () {
      final o = hacimOzeti(_seri(21), const [], simdi: simdi)!;
      expect(o.aliciPayi, isNull);
      expect(o.aliciPayi7, isNull);
    });

    test('7 günlük alıcı payı hacim ağırlıklı (sunucu notuyla aynı)', () {
      // 6 sakin gün %50 (1 mr), 1 yoğun gün %80 (4 mr).
      // Basit ortalama %54,3; hacim ağırlıklı (6×0,5 + 4×0,8) / 10 = %62.
      final gunler = [
        for (var i = 0; i < 7; i++)
          HacimGunu(
              tarih: DateTime.utc(2026, 9, 16 + i),
              kapanis: 1,
              paraHacmi: i == 6 ? 4e9 : 1e9,
              aliciPayi: i == 6 ? 0.8 : 0.5),
      ];
      final o = hacimOzeti(gunler, const [], simdi: DateTime.utc(2026, 9, 23))!;
      expect(o.aliciPayi7, closeTo(0.62, 1e-9));
      // Haftalık okunuş haftanın payına, kartın okunuşu son güne bakar.
      expect(kriptoHaftaOkunusu(o)!.kademe, Kademe.cokHareketli);
      expect(kriptoOkunusu(o)!.kademe, Kademe.cokHareketli);
    });

    test('kisaDolar ve kriptoTickeri', () {
      expect(kisaDolar(243e6), r'$243,00M');
      expect(kriptoTickeri(tur: AssetType.kripto, ticker: 'kripto:eth'),
          'KRIPTO:ETH');
      expect(kriptoTickeri(tur: AssetType.kripto, ticker: 'ETH'), isNull);
    });
  });

  group('değişmezler (kaynak taraması)', () {
    test('kart metinleri akış/balina dili kullanmaz', () {
      for (final arb in ['lib/l10n/app_tr.arb', 'lib/l10n/app_en.arb']) {
        final vol = RegExp(r'"vol\w+": "([^"]*)"')
            .allMatches(ekranKaynagiSync(arb))
            .map((m) => m[1]!.toLowerCase())
            .toList();
        expect(vol, isNotEmpty);
        for (final yasak in ['balina', 'whale', 'net giriş', 'net çıkış']) {
          expect(vol.where((m) => m.contains(yasak)), isEmpty,
              reason: '$arb: $yasak');
        }
      }
    });

    test('fon ve hisse olay sorguları birbirinin satırını okumaz', () {
      final svc = ekranKaynagiSync('lib/services/supabase_service.dart');
      expect(svc, contains(".inFilter('tur', ['fon_giris', 'fon_cikis'])"));
      expect(
          svc,
          contains(
              ".inFilter('tur', ['hisse_hacim_yukselis', 'hisse_hacim_dusus'])"));
    });

    test('kart iki yüzeyde bağlı; eşikler yalnız sunucuda', () {
      expect(ekranKaynagiSync('lib/screens/asset_detail_screen.dart'),
          contains('HacimRadariKarti('));
      expect(ekranKaynagiSync('lib/screens/varlik_sayfasi.dart'),
          contains('HacimRadariKarti('));
      final sunucu = ekranKaynagiSync('supabase/functions/_shared/hacim.ts');
      expect(sunucu, contains('export const Z_ESIGI = 3;'));
      expect(sunucu, contains('export const KAT_ESIGI = 2;'));
      expect(sunucu, contains('export const ASGARI_PARA_HACMI = 50_000_000;'));
      expect(ekranKaynagiSync('lib/services/hisse_hacmi.dart'),
          isNot(contains('ASGARI_PARA_HACMI')));
    });

    test('sunucu: fail-closed kapı, RLS + GRANT, tutarlılık kısıtı', () {
      final fn = ekranKaynagiSync('supabase/functions/hacim-gozlem/index.ts');
      expect(fn, contains('cronSecretZorunlu('));
      expect(fn, contains('cronYetkisiVarMi('));
      expect(fn, isNot(contains('err.message')));
      final sql = ekranKaynagiSync('supabase/migrations/0107_hisse_hacim.sql');
      expect(
          sql,
          contains(
              'alter table public.hisse_hacim_gunluk force row level security'));
      expect(
          sql,
          contains(
              'grant select on table public.hisse_hacim_gunluk to authenticated'));
      expect(sql, contains('balina_olay_alan_tutarliligi'));
      expect(
          RegExp(r'security definer\s+set search_path').allMatches(sql).length,
          RegExp(r'security definer').allMatches(sql).length);
    });
  });
}
