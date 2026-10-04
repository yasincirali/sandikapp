import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/fon_akisi_provider.dart';
import 'package:portfoy_takip/services/hisse_hacmi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/hacim_radari_karti.dart';

import 'helpers/kaynak.dart';

/// Hacim radarı (Balina B2): saf özet + kart.
///
/// ## Kilitlenen davranışlar
/// 1. Ortalama, son günden ÖNCEKİ 20 işlem günüdür (sunucu kuralıyla aynı
///    pencere); 20 gün yoksa kat gösterilmez.
/// 2. Veri yok / bayat / BIST dışı → kart yok; bayrak kapalıyken sorgu yok.
/// 3. Dil: "giriş/çıkış" ve "balina" yok; "kimin aldığı bilinemez" var.
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
}) async {
  _sorgu = 0;
  final simdi = DateTime(2026, 9, 24);
  t.view.physicalSize = Size(genislik, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      balinaRadariAcikProvider.overrideWithValue(acik),
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
      home: MediaQuery(
        data: MediaQueryData(
            size: Size(genislik, 1600), textScaler: TextScaler.linear(olcek)),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
            child: kart,
          ),
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
          HacimGunu.satirdan(
                  {'tarih': '2026-10-02', 'kapanis': 310.5, 'para_hacmi': 4.8e9})!
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

  testWidgets('kart: tutar, kat, fiyat, açıklama ve dipnot', (t) async {
    await _kur(t);
    expect(find.byType(SandikCard), findsOneWidget);
    expect(find.text('HACİM RADARI'), findsOneWidget);
    expect(find.text('Para hacmi · 22 Eyl'), findsOneWidget);
    expect(find.text('₺320,00M'), findsOneWidget);
    expect(find.text('Önceki 20 günün ortalamasının 3,2 katı'), findsOneWidget);
    expect(find.text('Aynı gün fiyat +%4,0'), findsOneWidget);
    expect(find.textContaining('Her işlemin bir alıcısı ve bir satıcısı'),
        findsOneWidget);
    expect(find.text('Son 30 günde olağandışı hacim günü yok.'),
        findsOneWidget);
    expect(find.textContaining('Kimin alıp sattığı bu veriden bilinemez'),
        findsOneWidget);
    expect(find.textContaining('veri tarihi 22 Eyl'), findsOneWidget);
  });

  testWidgets('olay satırı: tarih ve kanıt (tutar, kat, fiyat)', (t) async {
    await _kur(t,
        ozet: hacimOzeti(_seri(21), [_olay(9, 19), _olay(9, 10, yukselis: false)],
            simdi: simdi));
    expect(find.text('Olağandışı hacim · 19 Eyl'), findsOneWidget);
    expect(find.text('₺35,46Mr · ortalamanın 4,7 katı · fiyat +%10,0'),
        findsOneWidget);
    expect(find.text('₺35,46Mr · ortalamanın 4,7 katı · fiyat −%6,7'),
        findsOneWidget);
    expect(find.textContaining('olağandışı hacim günü yok'), findsNothing);
  });

  testWidgets('20 gün dolmadıysa kat satırı yok', (t) async {
    // 8 günlük seri 9 Eylül'de biter; bayat sayılmasın diye yakın bir 'şimdi'.
    final kisa = hacimOzeti(_seri(8), const [], simdi: DateTime(2026, 9, 12));
    expect(kisa, isNotNull);
    await _kur(t, ozet: kisa);
    expect(find.textContaining('ortalamasının'), findsNothing);
    expect(find.text('₺320,00M'), findsOneWidget);
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
    expect(_sorgu, 0);
  });

  testWidgets('fon varlığında çizilmez', (t) async {
    await _kur(t,
        kart: const HacimRadariKarti(tur: AssetType.fon, ticker: 'TEFAS:TTE'));
    expect(find.byType(SandikCard), findsNothing);
    expect(_sorgu, 0);
  });

  testWidgets('dar ekran (320) ve büyük yazı (1,5×) taşmaz', (t) async {
    await _kur(t,
        genislik: 320,
        olcek: 1.5,
        ozet: hacimOzeti(_seri(21), [_olay(9, 19)], simdi: simdi));
    expect(t.takeException(), isNull);
  });

  testWidgets('İngilizce: metinler çevrili', (t) async {
    await _kur(t, dil: const Locale('en'));
    expect(find.text('VOLUME RADAR'), findsOneWidget);
    expect(find.textContaining('cannot show who bought or sold'),
        findsOneWidget);
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
      final sql = ekranKaynagiSync('supabase/migrations/0104_hisse_hacim.sql');
      expect(
          sql,
          contains(
              'alter table public.hisse_hacim_gunluk force row level security'));
      expect(
          sql,
          contains(
              'grant select on table public.hisse_hacim_gunluk to authenticated'));
      expect(sql, contains('balina_olay_alan_tutarliligi'));
      expect(RegExp(r'security definer\s+set search_path').allMatches(sql).length,
          RegExp(r'security definer').allMatches(sql).length);
    });
  });
}
