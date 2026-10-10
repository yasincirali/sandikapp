import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/portfoy_grubu.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/varlik_eklendi.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/chart_axis.dart';
import 'package:portfoy_takip/utils/pozisyon_etiketi.dart';
import 'package:portfoy_takip/widgets/fiyat_grafigi.dart';
import 'package:portfoy_takip/widgets/gorunum_cipi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// TestFlight bulguları (2026-10-10).
///
///   1. Bugün kartı: eğri geç çiziliyordu — seri fiyat turunu beklerken
///      eğrinin yeri yoktu, sonradan araya girip kartı büyütüyordu.
///   2. AAPL varlık sayfası (22:25): zaman ekseni etiketleri üst üste —
///      "9 Eki 04:00 9 Eki 08:00 …". Kök neden: gün içi sağ pay pencereyi
///      24 saatin üstüne taşıyınca eksen "çok günlü" sanılıp her etikete
///      tarih basılıyordu; grafikler ekran genişliğini de bilmiyordu.
///   3. Varlık ekledikten sonra Portföy'ün tür süzgeci sıfırlanmıyordu;
///      yeni varlık süzgecin dışında kalıp görünmüyordu. Kural: ekleme
///      nereden yapılırsa yapılsın Portföy "Tümü"de açılır, satır parlar.
///   4. Performans › tür dökümü: vadeli mevduat "906B9769-6846-…" (sözleşme
///      UUID'si) olarak yazılıyordu.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  group('#4 mevduat etiketi — sözleşme kimliği ekrana çıkmaz', () {
    final l = lookupAppLocalizations(const Locale('tr'));
    const uuid = '906B9769-6846-477E-9C3A-1B2C3D4E5F60';
    const anahtar = 'mevduat|MEVDUAT:$uuid|TRY';

    test('ad verilince varlığın adı', () {
      expect(
          pozisyonEtiketi(anahtar, AssetType.mevduat, l,
              ad: 'Ziraat · Vadeli'),
          'Ziraat · Vadeli');
    });

    test('ad yoksa tür adı, UUID değil', () {
      final e = pozisyonEtiketi(anahtar, AssetType.mevduat, l);
      expect(e, AssetType.mevduat.labelOf(l));
      expect(e.contains('906B'), isFalse);
    });

    test('tür bilinmese de (Diğer yedeği) önekten tanınır', () {
      // Özet'in en iyi/en zayıfı türü `positionType[k] ?? diger` ile okur.
      final e = pozisyonEtiketi(anahtar, AssetType.diger, l);
      expect(e.contains('906B'), isFalse);
    });

    test('diğer türler değişmedi', () {
      expect(pozisyonEtiketi('hisse|THYAO.IS|TRY', AssetType.hisse, l),
          'THYAO');
      expect(pozisyonEtiketi('doviz|USDTRY=X|TRY', AssetType.doviz, l),
          l.marketDollar);
    });

    test('genel arama satırı UUID yazmaz', () {
      expect(
          ekranKaynagiSync('lib/screens/genel_arama_screen.dart')
              .contains("mevduatSozlesmeId(a.ticker) != null ? ''"),
          isTrue);
    });

    test('tür dökümü ve Özet adı geçirir', () {
      expect(
          ekranKaynagiSync(
                  'lib/screens/portfolio_performance/tur_dokumu_karti.dart')
              .contains('ad: pozLot.firstOrNull?.name'),
          isTrue);
      expect(
          ekranKaynagiSync('lib/screens/portfolio_performance/kartlar.dart')
              .contains('ad: pozisyonAdi[k]'),
          isTrue);
    });
  });

  group('#2 zaman ekseni etiketleri', () {
    final t = DateTime(2026, 10, 9, 20, 0);

    test('sağ payla 24 saati aşan TEK gün tarih basmaz', () {
      // 22:25'te son nokta → pencere 1345/0,82 dk ≈ 1,14 gün.
      expect(zamanEtiketi(t, spanGun: 1.14, gunIci: true), '20:00');
      expect(zamanEtiketi(t, spanGun: 1.2, gunIci: true), '20:00');
    });

    test('hafta sonu kuyruğu (≥ 1,22 gün) tarihini korur', () {
      expect(zamanEtiketi(t, spanGun: 1.25, gunIci: true), '9 Eki 20:00');
      expect(zamanEtiketi(t, spanGun: 3, gunIci: true), '9 Eki 20:00');
    });

    test('eşik sağ payın varabileceği en geniş pencere', () {
      // 23:59'daki son nokta bile eşiğin altında kalır.
      expect(gunIciEksenSonuDk(1439) / 1440, lessThan(gunIciCokGunEsigi));
      // Cumartesi 00:00'daki kuyruk eşiğe değer — tarih basılır.
      expect(gunIciEksenSonuDk(1440) / 1440,
          greaterThanOrEqualTo(gunIciCokGunEsigi - 1e-9));
    });

    test('seyreltme: sığan etiket atlanmaz, sığmayan her k\'incide', () {
      const saat = 3600 * 1000.0;
      // 27 saatlik pencere, 4 saatlik adım, 280px → adım ≈ 41px.
      bool atla(double i, double px) => xEtiketiAtlanir(i * 4 * saat,
          aralik: 27 * saat, tickAraligi: 4 * saat, eksenPx: 280, etiketPx: px);
      expect([for (var i = 0; i < 6; i++) atla(i.toDouble(), 40)],
          everyElement(isFalse));
      // 75px'lik etiket iki adıma sığar → tek sıralar atlanır.
      expect([for (var i = 0; i < 6; i++) atla(i.toDouble(), 75)],
          [false, true, false, true, false, true]);
    });

    test('dört grafik de seyreltmeyi çağırır', () {
      for (final f in [
        'lib/widgets/fiyat_grafigi.dart',
        'lib/widgets/percent_comparison_chart.dart',
        'lib/screens/portfolio_performance/grafik_kabi.dart',
        'lib/screens/asset_detail_screen.dart',
      ]) {
        expect(ekranKaynagiSync(f).contains('xEtiketiAtlanir('), isTrue,
            reason: '$f etiketleri genişliğe göre seyreltmiyor');
      }
    });

    // Gerçek grafik: AAPL senaryosu — ABD seansı 16:30 → 22:25.
    Map<int, double> aaplSeri() {
      final bas = DateTime(2026, 10, 9, 16, 30);
      return {
        for (var i = 0; i <= 71; i++)
          bas.add(Duration(minutes: i * 5)).millisecondsSinceEpoch:
              16396 + i * 4.0,
      };
    }

    Future<List<(double, double, String)>> xEtiketleri(
        WidgetTester tester, double genislik, double olcek) async {
      tester.view.physicalSize = Size(genislik * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('tr', 'TR'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(genislik, 900), textScaler: TextScaler.linear(olcek)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FiyatGrafigi(
                seri: aaplSeri(),
                periodDays: 1,
                bicim: NumberFormat('#,##0.00', 'tr_TR'),
                semanticLabel: 'AAPL',
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      final zaman = RegExp(r'^\d{2}:\d{2}$|Eki');
      final out = <(double, double, String)>[];
      for (final e in find.byType(Text).evaluate()) {
        final w = e.widget as Text;
        final s = w.data ?? '';
        if (!zaman.hasMatch(s)) continue;
        // Text → RichText → RenderParagraph.
        final p = e.findRenderObject()! as RenderParagraph;
        final yazi = p.getMaxIntrinsicWidth(double.infinity);
        final merkez = p.localToGlobal(Offset(p.size.width / 2, 0)).dx;
        out.add((merkez - yazi / 2, merkez + yazi / 2, s));
      }
      out.sort((a, b) => a.$1.compareTo(b.$1));
      return out;
    }

    for (final (gen, olcek) in [(320.0, 1.0), (390.0, 1.0), (390.0, 1.3)]) {
      testWidgets('AAPL 22:25 — ${gen.toInt()}pt, yazı ×$olcek: üst üste yok',
          (tester) async {
        final e = await xEtiketleri(tester, gen, olcek);
        expect(tester.takeException(), isNull);
        expect(e, isNotEmpty, reason: 'X etiketi bulunamadı');
        for (final x in e) {
          expect(x.$3.contains('Eki'), isFalse,
              reason: 'tek günlük eksene tarih basıldı: ${x.$3}');
        }
        for (var i = 1; i < e.length; i++) {
          expect(e[i].$1, greaterThanOrEqualTo(e[i - 1].$2),
              reason: '"${e[i - 1].$3}" ile "${e[i].$3}" üst üste');
        }
      });
    }
  });

  group('#1 Bugün kartı eğrisi', () {
    final src = ekranKaynagiSync('lib/widgets/bugun_karti.dart');

    test('eğri kartla birlikte akarak çizilir (animasyon korunur)', () {
      // Kullanıcı (2026-10-10): "eğri çizili gelmesi değil, kart çizildiği
      // an grafik aynı çizilme animasyonuyla çizilmeli."
      final i = src.indexOf('class _GunIciEgri');
      final govde = src.substring(i, src.indexOf('class _GunIciPainter', i));
      expect(govde.contains('TweenAnimationBuilder'), isTrue);
      expect(govde.contains('SandikMotion.flowOf(context)'), isTrue);
      expect(src.contains('extractPath('), isTrue);
    });

    test('seri beklenirken eğrinin yeri iskeletle tutulur', () {
      expect(
          src.contains('_seri == null && (_yukleniyor || _turBekleniyor)'),
          isTrue);
      expect(src.contains('SandikSkeleton(height: _egriYuksekligi)'), isTrue);
    });
  });

  group('#3 ekleme nereden yapılırsa — Portföy "Tümü", yeni satır parlar', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
      GorunumCipi.hafizayiSifirla();
    });

    Future<void> kur(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          portfolioProvider.overrideWith(_FakePortfolio.new),
          partnersProvider.overrideWith(_FakePartners.new),
          activePartnersProvider.overrideWith((ref) => const []),
          allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        ],
        child: MaterialApp(
            theme: ThemeData.dark(), home: const PortfolioScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> suz(WidgetTester tester, AssetType tur) async {
      final halka = find.byWidgetPredicate((w) {
        final n = w.runtimeType.toString();
        return n == '_KucukHalka' || n == '_AssetTypeDonut';
      });
      expect(halka, findsOneWidget);
      // ignore: avoid_dynamic_calls
      (tester.widget(halka) as dynamic).onTypeSelected(PortfoyGrubu(tur));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    /// Satırın parlama sarmalayıcısı aktif mi?
    bool parliyor(WidgetTester tester, String metin) {
      final sar = find.ancestor(
        of: find.textContaining(metin).first,
        matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_YeniVarlikParlamasi'),
      );
      // ignore: avoid_dynamic_calls
      return (tester.widget(sar.first) as dynamic).aktif as bool;
    }

    testWidgets('altın süzgeci açıkken eklenen hisse görünür ve parlar',
        (tester) async {
      await kur(tester);
      expect(find.textContaining('THYAO'), findsWidgets);
      await suz(tester, AssetType.altin);
      expect(find.textContaining('THYAO'), findsNothing,
          reason: 'süzgeç uygulanmadı — test kurgusu yanlış');

      VarlikEklendi.duyur(pozisyonAnahtari: 'hisse|THYAO.IS|TRY');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('THYAO'), findsWidgets,
          reason: 'süzgeç sıfırlanmadı, yeni varlık görünmüyor');
      expect(parliyor(tester, 'THYAO'), isTrue,
          reason: 'eklenen satır vurgulanmadı');
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('halkada DOKUNARAK seçilen dilim de sıfırlanır',
        (tester) async {
      // TestFlight (2026-10-10): liste "Tümü"ye döndü ama halkada "Altın"
      // seçili kaldı — halka seçimi kendi içinde tutuyordu. Önceki test
      // süzgeci geri çağrıyla kurduğu için halkanın iç durumunu görmedi;
      // burada kullanıcı gibi halkanın lejantına dokunulur.
      await kur(tester);
      final halka = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_AssetTypeDonut');
      if (halka.evaluate().isEmpty) return; // bayrak: küçük halka denetimli
      // Lejant satırı "Altın %63,0" (ad + pay tek metin).
      final altin = find.descendant(
          of: halka, matching: find.textContaining('Altın', findRichText: true));
      await tester.tap(altin.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      double soluk() => tester
          .widgetList<AnimatedOpacity>(find.descendant(
              of: halka, matching: find.byType(AnimatedOpacity)))
          .where((o) => o.opacity < 1)
          .length
          .toDouble();
      expect(soluk(), greaterThan(0), reason: 'dokunuş dilimi seçmedi');
      expect(find.textContaining('THYAO'), findsNothing);

      VarlikEklendi.duyur(pozisyonAnahtari: 'hisse|THYAO.IS|TRY');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(soluk(), 0, reason: 'halkada eski dilim seçili kaldı');
      expect(find.textContaining('THYAO'), findsWidgets);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('var olan pozisyona alış da satırı parlatır', (tester) async {
      await kur(tester);
      expect(parliyor(tester, 'THYAO'), isFalse);
      VarlikEklendi.duyur(pozisyonAnahtari: 'hisse|THYAO.IS|TRY');
      await tester.pump();
      expect(parliyor(tester, 'THYAO'), isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });

    testWidgets("küçük halkada seçili dilime ikinci dokunuş Tümü'ye döner",
        (tester) async {
      // TestFlight (2026-10-10): "parçaya tıklayınca filtreliyor, tekrar
      // tıklayınca Tümü'ye geçmesi lazım ama detaylı sayfa açıyor."
      RemoteConfigService.testAcik = {'goz_alici', 'portfoy_dagilim_cubugu'};
      addTearDown(() => RemoteConfigService.testAcik = {});
      await kur(tester);
      // 120pt halka kutusu; dilimler tepeden saat yönünde, büyükten küçüğe:
      // Altın %63 (0°–227°), Hisse %37 (227°–360°). 300°'de, banttaki nokta.
      final kutu = find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 120 && w.height == 120);
      expect(kutu, findsOneWidget);
      final sol = tester.getTopLeft(kutu);
      const aci = 300 * math.pi / 180, yaricap = 50.0;
      final hisse = sol +
          Offset(60 + yaricap * math.sin(aci), 60 - yaricap * math.cos(aci));
      bool altinGorunur() => find.textContaining('ALTIN').evaluate().isNotEmpty;
      expect(altinGorunur(), isTrue);

      await tester.tapAt(hisse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(altinGorunur(), isFalse, reason: 'ilk dokunuş Hisse süzmedi');

      await tester.tapAt(hisse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(altinGorunur(), isTrue, reason: 'ikinci dokunuş süzgeci kaldırmadı');
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'ikinci dokunuş büyük halka sayfasını açtı');
      expect(tester.takeException(), isNull);
    });

    test('her ekleme yolu duyurur; düzenleme ve sepet duyurmaz', () {
      final form = ekranKaynagiSync('lib/screens/add_asset_screen.dart');
      final i = form.indexOf('void _kayitBitti(Object sonuc)');
      final govde = form.substring(i, form.indexOf('\n  }\n', i));
      expect(govde.contains('!_isEditing && !widget.cartMode'), isTrue);
      expect(govde.contains('VarlikEklendi.duyur('), isTrue);
      // Tekli kayıt, çoklu lot ve sözleşmeli (mevduat/BES) form.
      expect('_kayitBitti('.allMatches(form).length, greaterThanOrEqualTo(4));
      expect(form.contains('Navigator.pop(context, alarmAdayi ?? true)'),
          isFalse,
          reason: 'kayıt duyurusuz kapanıyor');
      expect(
          ekranKaynagiSync('lib/screens/bulk_add_asset_screen.dart')
              .contains('VarlikEklendi.duyur('),
          isTrue);
    });

    test('ana gezinme araya açılan rotaları kapatıp Portföy\'e geçer', () {
      final src = ekranKaynagiSync('lib/screens/main_navigation_screen.dart');
      final i = src.indexOf('void _varlikEklendi()');
      final govde = src.substring(i, src.indexOf('\n  }\n', i));
      expect(govde.contains('_sekmeyeGec(_portfolioTab)'), isTrue);
      expect(govde.contains('addPostFrameCallback'), isTrue,
          reason: 'aynı karede popUntil formun kendi pop\'uyla çakışır');
      expect(govde.contains('popUntil((r) => r == rota || r.isFirst)'),
          isTrue);
      expect(src.contains('VarlikEklendi.kanal.addListener(_varlikEklendi)'),
          isTrue);
    });
  });
}

const _uid = 'user-1';

Asset _lot(String ticker, double qty, double fiyat,
        {AssetType type = AssetType.hisse, String? sub}) =>
    Asset(
      id: '$ticker-$qty',
      userId: _uid,
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: fiyat * 0.9,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      subCategory: sub,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 3, 14),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 't@x',
        displayName: 'Ben',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [
          _lot('THYAO.IS', 300, 310),
          _lot('ALTIN_CEYREK', 15, 10544,
              type: AssetType.altin, sub: 'Çeyrek Altın'),
        ],
        usdTry: 42,
        eurTry: 46,
        gbpTry: 54,
      );
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}
