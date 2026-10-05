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
import 'package:portfoy_takip/screens/para_akisi_detay_screen.dart';
import 'package:portfoy_takip/services/fon_akisi.dart';
import 'package:portfoy_takip/services/radar_okuma.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart';
import 'package:portfoy_takip/widgets/radar_ortak.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Para akışı kartı (S1-B) ve ayrıntı ekranı (S2-A + S3-B), 2026-10-05.
///
/// ## Kilitlenen davranışlar
/// 1. Bayrak kapalıyken hiçbir şey çizilmez VE veri sorgusu hiç başlamaz.
/// 2. Veri yoksa / fon değilse kart yer kaplamaz.
/// 3. Kart cümle → sayı → ölçek düzeninde; cümle ile işaret çelişmez.
/// 4. Kilitliyken (paywall açık, Premium değil) ilk sayı açık, seyir kilitli
///    ve kart ayrıntıya gitmez (S12-B).
/// 5. Terime dokununca tanım sayfası; ayrıntıda ilk açılışta 3 adımlı koç.
/// 6. Ayrıntı: haftaya dokununca o haftanın rakamı; kategori sırası ilk 5 +
///    bu fon; bilinmeyen yatırımcı satırı yok.
/// 7. Dar ekranda (320) ve büyük yazıda (1,6×) taşma yok.
DateTime _g(int ay, int gun) => DateTime.utc(2026, ay, gun);

FonAkisOzeti _ozet({
  double net = 412e6,
  int? yatirimci = 48210,
  int? yatirimciDegisimi = 38,
  List<FonBalinaOlayi> olaylar = const [],
  DonemAkisi? ay1,
}) =>
    FonAkisOzeti(
      haftalar: [
        for (var i = 7; i >= 1; i--)
          HaftaAkisi(
              baslangic: DateTime.utc(2026, 9, 28 - 7 * i),
              net: i == 4 ? null : (i.isEven ? 120e6 : -80e6)),
        HaftaAkisi(baslangic: _g(9, 28), net: net),
      ],
      sonHaftaNet: net,
      sonHaftaIlkGun: _g(9, 28),
      veriTarihi: _g(10, 2),
      buyukluk: 13.4e9,
      yatirimci: yatirimci,
      yatirimciDegisimi: yatirimciDegisimi,
      olaylar: olaylar,
      ay1: ay1,
      ay3: null,
      seri: null,
    );

int _sorguSayisi = 0;

Future<void> _kur(
  WidgetTester t, {
  Widget? govde,
  bool acik = true,
  bool kilitli = false,
  FonAkisOzeti? ozet,
  bool veriYok = false,
  List<KategoriSirasi>? sira,
  double genislik = 390,
  double olcek = 1,
  bool kocGoruldu = true,
}) async {
  SharedPreferences.setMockInitialValues(
      kocGoruldu ? {PrefKeys.radarKocuGoruldu: true} : {});
  await initPreferencesCache();
  _sorguSayisi = 0;
  t.view.physicalSize = Size(genislik, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      balinaRadariAcikProvider.overrideWithValue(acik),
      radarKilitliProvider.overrideWithValue(kilitli),
      fonAkisiProvider.overrideWith((ref, kod) async {
        _sorguSayisi++;
        return veriYok ? null : (ozet ?? _ozet());
      }),
      fonKategoriSirasiProvider.overrideWith((ref, kod) async => sira),
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
      home: govde ??
          const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: SandikSpace.smd),
              child: ParaAkisiKarti(tur: AssetType.fon, ticker: 'TEFAS:TTE'),
            ),
          ),
    ),
  ));
  await t.pumpAndSettle();
}

KategoriSirasi _s(int sira, String kod, double net, {bool kendi = false}) =>
    KategoriSirasi(
        sira: sira,
        fonKodu: kod,
        netAkis: net,
        kendi: kendi,
        kategori: 'Hisse Senedi Fonu',
        fonSayisi: 14);

void main() {
  group('kart', () {
    testWidgets('cümle, sayı, ölçek, seyir ve kaynak', (t) async {
      await _kur(t);
      expect(find.text('PARA AKIŞI'), findsOneWidget);
      // Önceki haftaların |net| ortalaması ≈ ₺93 mn; 412 / 93 ≈ 4,4 kat.
      expect(find.text('Bu fona son hafta olağanın çok üstünde para girdi.'),
          findsOneWidget);
      expect(find.text('+₺412,00M'), findsOneWidget);
      expect(find.text('Çok hareketli hafta'), findsOneWidget);
      expect(find.text('net akış · 28 Eyl - 2 Eki'), findsOneWidget);
      expect(find.byType(OlcekCubugu), findsOneWidget);
      expect(find.byType(HaftaCubuklari), findsOneWidget);
      expect(find.text('son 8 hafta · büyük hareket yok'), findsOneWidget);
      expect(find.textContaining('TEFAS · 2 Eki · tavsiye değildir'),
          findsOneWidget);
      // Eski açıklama paragrafları yok: terimler dokunulabilir.
      expect(find.textContaining('fiyat değişimi dahil değildir'),
          findsNothing);
    });

    testWidgets('çıkış: eksi işaret (U+2212) ve çıkış cümlesi', (t) async {
      await _kur(t, ozet: _ozet(net: -150e6));
      expect(find.text('−₺150,00M'), findsOneWidget);
      expect(find.text('Bu fondan son hafta olağandan fazla para çıktı.'),
          findsOneWidget);
      expect(find.text('Hareketli hafta'), findsOneWidget);
    });

    testWidgets('olay sayısı seyrin altında yazılır', (t) async {
      await _kur(
          t,
          ozet: _ozet(olaylar: [
            FonBalinaOlayi(
                tarih: _g(9, 29),
                tutar: 398e6,
                buyuklukOrani: 0.031,
                sapmaKati: 4.2),
            FonBalinaOlayi(
                tarih: _g(9, 16),
                tutar: -151e6,
                buyuklukOrani: 0.022,
                sapmaKati: 3.4),
          ]));
      expect(find.text('son 8 hafta · 2 büyük hareket'), findsOneWidget);
    });

    testWidgets('bayrak kapalıyken çizilmez ve sorgu BAŞLAMAZ', (t) async {
      await _kur(t, acik: false);
      expect(find.byType(SandikCard), findsNothing);
      expect(_sorguSayisi, 0);
    });

    testWidgets('veri yoksa hiç yer kaplamaz', (t) async {
      await _kur(t, veriYok: true);
      expect(find.byType(SandikCard), findsNothing);
      expect(t.getSize(find.byType(ParaAkisiKarti)).height, 0);
    });

    testWidgets('varlık fon değilse çizilmez ve sorgu başlamaz', (t) async {
      await _kur(t,
          govde: const Scaffold(
              body:
                  ParaAkisiKarti(tur: AssetType.hisse, ticker: 'THYAO.IS')));
      expect(find.byType(SandikCard), findsNothing);
      expect(_sorguSayisi, 0);
    });

    testWidgets('kilitli: ilk sayı açık, seyir kilitli, ayrıntıya gitmez',
        (t) async {
      await _kur(t, kilitli: true);
      expect(find.text('+₺412,00M'), findsOneWidget);
      expect(find.byType(OlcekCubugu), findsOneWidget);
      expect(find.byType(HaftaCubuklari), findsNothing);
      expect(find.text("8 haftalık seyir ve 0 büyük hareket Premium'da"),
          findsOneWidget);
      await t.tap(find.text('+₺412,00M'));
      await t.pumpAndSettle();
      expect(find.byType(ParaAkisiDetayScreen), findsNothing);
    });

    testWidgets('terime dokununca tanım ve bu varlıktaki değeri açılır',
        (t) async {
      await _kur(t);
      await t.tap(find.text('net akış · 28 Eyl - 2 Eki'));
      await t.pumpAndSettle();
      expect(find.text('Net akış'), findsOneWidget);
      expect(find.textContaining('Fon fiyatının artması ya da düşmesi buna'),
          findsOneWidget);
      expect(find.text('Bu varlıkta: TTE · +₺412,00M'), findsOneWidget);
    });

    testWidgets('dar ekran (320) ve büyük yazı (1,6×) taşmaz', (t) async {
      await _kur(t, genislik: 320, olcek: 1.6);
      expect(t.takeException(), isNull);
      expect(find.text('+₺412,00M'), findsOneWidget);
    });
  });

  group('ayrıntı', () {
    Widget detay() => const ParaAkisiDetayScreen(kod: 'TTE');

    testWidgets('ilk açılışta 3 adımlı "nasıl okunur", sonra açılmaz',
        (t) async {
      await _kur(t, govde: detay(), kocGoruldu: false);
      expect(find.text('1 / 3'), findsOneWidget);
      await t.tap(find.text('İleri'));
      await t.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      await t.tap(find.text('İleri'));
      await t.pumpAndSettle();
      await t.tap(find.text('Anladım'));
      await t.pumpAndSettle();
      expect(find.text('1 / 3'), findsNothing);
      // "?" her zaman yeniden açar.
      await t.tap(find.byTooltip('Nasıl okunur'));
      await t.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('üst: cümle, kat, seyirde haftaya dokunma', (t) async {
      await _kur(t, govde: detay());
      expect(find.text('TTE · Para akışı'), findsOneWidget);
      expect(find.text(' · olağan haftanın 4,4 katı'), findsOneWidget);
      expect(find.text('Bir haftaya dokun, o haftanın rakamı burada görünür.'),
          findsOneWidget);
      // Son hafta çubuğu: sağdaki ilk dokunulabilir alan.
      final cubuklar = find.descendant(
          of: find.byType(HaftaCubuklari), matching: find.byType(GestureDetector));
      await t.tap(cubuklar.last);
      await t.pumpAndSettle();
      expect(find.text('28 Eyl - 2 Eki haftası: +₺412,00M'), findsOneWidget);
      // Veri olmayan hafta "veri yok" der, sıfır yazmaz.
      await t.tap(cubuklar.at(3));
      await t.pumpAndSettle();
      expect(find.textContaining('haftası: veri yok'), findsOneWidget);
    });

    testWidgets('bağlam: bilinmeyen yatırımcı satırı yok', (t) async {
      await _kur(t,
          govde: detay(),
          ozet: _ozet(yatirimci: null, yatirimciDegisimi: null));
      expect(find.text('Fon büyüklüğü'), findsOneWidget);
      expect(find.text('Yatırımcı sayısı'), findsNothing);
    });

    testWidgets('ayrıştırma: fiyat + yeni para, işaretleriyle', (t) async {
      await _kur(t,
          govde: detay(),
          ozet: _ozet(
              ay1: const DonemAkisi(
                  para: 300e6, paraOrani: 0.025, toplamDegisim: 0.015)));
      await t.scrollUntilVisible(find.text('DÖNEM'), 200);
      expect(find.text('Son 1 ayda fon büyüklüğü +%1,5 değişti.'),
          findsOneWidget);
      expect(find.text('fiyat −%1,0'), findsOneWidget);
      expect(find.text('yeni para +%2,5'), findsOneWidget);
    });

    testWidgets('kategori sırası: ilk 5 + bu fon; yoksa bölüm yok', (t) async {
      await _kur(t, govde: detay(), sira: [
        _s(1, 'AAA', 900e6),
        _s(2, 'BBB', 500e6),
        _s(3, 'CCC', 300e6),
        _s(4, 'DDD', 200e6),
        _s(5, 'EEE', 100e6),
        _s(9, 'TTE', 20e6, kendi: true),
      ]);
      await t.scrollUntilVisible(find.text('KATEGORİDE AKIŞ SIRASI'), 200);
      expect(find.text('TTE (bu fon)'), findsOneWidget);
      expect(find.text('14 fon içinde'), findsOneWidget);
      expect(
          find.text(
              'Hisse Senedi Fonu · aynı haftanın net akışına göre sıra'),
          findsOneWidget);
    });

    testWidgets('kategori sırası verisi yoksa bölüm yok', (t) async {
      await _kur(t, govde: detay());
      expect(find.text('KATEGORİDE AKIŞ SIRASI'), findsNothing);
    });

    testWidgets('dar ekran + büyük yazı taşmaz (koç dahil)', (t) async {
      await _kur(t,
          govde: detay(), genislik: 320, olcek: 1.6, kocGoruldu: false);
      expect(t.takeException(), isNull);
      await t.tap(find.text('İleri'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('değişmezler (kaynak taraması)', () {
    test('bayrak varsayılanı KAPALI', () {
      final kaynak =
          ekranKaynagiSync('lib/services/remote_config_service.dart');
      expect(kaynak, contains("'balina_radari_acik': false"));
      expect(RemoteConfigService.instance.balinaRadariAcik, isFalse);
    });

    test('radar metinleri "balina" demez', () {
      // TEFAS/Binance kimin alıp sattığını vermiyor; etiket kanıtla sınırlı.
      for (final arb in ['lib/l10n/app_tr.arb', 'lib/l10n/app_en.arb']) {
        final metinler = RegExp(r'"(?:flow|vol|cry|rdr|anz|prm)\w+": "([^"]*)"')
            .allMatches(ekranKaynagiSync(arb))
            .map((m) => m[1]!.toLowerCase());
        expect(metinler, isNotEmpty);
        expect(
            metinler.where((m) => m.contains('balina') || m.contains('whale')),
            isEmpty,
            reason: arb);
      }
    });

    test('kart iki fon yüzeyinde de bağlı: varlık detayı ve varlık sayfası',
        () {
      expect(ekranKaynagiSync('lib/screens/asset_detail_screen.dart'),
          contains('ParaAkisiKarti('));
      expect(ekranKaynagiSync('lib/screens/varlik_sayfasi.dart'),
          contains('ParaAkisiKarti('));
    });

    test('kural istemcide yeniden yazılmaz: eşik sabitleri yalnız sunucuda',
        () {
      final istemci = ekranKaynagiSync('lib/services/fon_akisi.dart') +
          ekranKaynagiSync('lib/widgets/para_akisi_karti.dart') +
          ekranKaynagiSync('lib/services/radar_okuma.dart');
      expect(istemci, isNot(contains('stddev')));
      expect(istemci, isNot(contains('ASGARI_BUYUKLUK')));
      final sunucu = ekranKaynagiSync('supabase/functions/_shared/balina.ts');
      expect(sunucu, contains('export const SAPMA_KATI = 4;'));
      expect(sunucu, contains('export const BUYUKLUK_ORANI = 0.03;'));
      expect(sunucu, contains('export const ASGARI_BUYUKLUK = 250_000_000;'));
    });

    test('kripto "çok" kademesi sunucu rozetiyle aynı sınırda', () {
      // Sunucu: alıcı payı ≥ 0,55 → 'alici_istekli', ≤ 0,45 → 'satici_istekli'.
      final sunucu = ekranKaynagiSync('supabase/functions/_shared/analiz.ts');
      expect(sunucu, contains('0.55'));
      expect(sunucu, contains('0.45'));
      expect(kriptoCokHareketliFark, 0.05);
    });

    test('sunucu: cron kapısı fail-closed, yanıt ayrıntı sızdırmaz', () {
      final fn = ekranKaynagiSync('supabase/functions/akis-gozlem/index.ts');
      expect(fn, contains('cronSecretZorunlu('));
      expect(fn, contains('cronYetkisiVarMi('));
      expect(fn, isNot(contains('err.message')));
    });
  });
}
