import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/fon_akisi_provider.dart'
    show balinaRadariAcikProvider;
import 'package:portfoy_takip/providers/fon_xray_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/raporlar_provider.dart';
import 'package:portfoy_takip/screens/portfoy_xray_screen.dart';
import 'package:portfoy_takip/screens/recap_screen.dart' show yilOzetiProvider;
import 'package:portfoy_takip/services/fon_dagilimi.dart';
import 'package:portfoy_takip/services/portfoy_xray.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/fon_dagilimi_karti.dart';
import 'package:portfoy_takip/widgets/premium_kilit_karti.dart';
import 'package:portfoy_takip/widgets/raporlar_kapisi.dart';
import 'package:portfoy_takip/widgets/sandik_bos_durum.dart';
import 'package:portfoy_takip/widgets/sandik_error_view.dart';

import 'helpers/kaynak.dart';

/// Fon X-Ray yüzeyleri (Premium, 2026-10-10) — görünürlük ve kilit.
///
/// Dört kullanıcı hâli (kullanıcı kuralı: "varolan hiçbir feature'a etki
/// edip bozmamalı"):
///   1. paywall kapalı, admin değil (canlıdaki herkes) → HİÇBİR ŞEY;
///   2. admin (paywall kapalı) → veri;
///   3. paywall açık, ücretsiz → kilit kartı, sayı yok, veri okunmaz;
///   4. paywall açık, Premium → veri.
final _dag = FonDagilimi(
  fonKodu: 'AAL',
  fonTipi: 'YAT',
  tarih: DateTime(2026, 10, 9),
  dagilim: const {
    'dt': 10.29,
    'fb': 9.03,
    'hb': 3.91,
    'tpp': 14.53,
    'tr': 34.29,
    'vmtl': 23.88,
    'khtl': 1.19,
    'ost': 1.48,
    'osks': 0.7,
    'vdm': 0.7,
  },
);

final _kalemler = FonKalemleri(
  fonKodu: 'AAL',
  donem: DateTime(2026, 9, 30),
  kaynakUrl: 'https://www.kap.org.tr/tr/Bildirim/1678119',
  kalemler: [
    for (var i = 1; i <= 12; i++)
      FonKalemi(ad: 'Kalem $i', kod: 'K$i', tur: 'hisse', agirlik: 13.0 - i),
  ],
);

int _okuma = 0;

Future<void> _kur(
  WidgetTester t,
  Widget govde, {
  required bool gorunur,
  bool kilitli = false,
  FonDagilimi? dag,
  bool kalemAcik = false,
  FonKalemleri? kalemler,
  List<Override> ek = const [],
}) async {
  _okuma = 0;
  t.view.physicalSize = const Size(390, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    // Aynı testte ikinci kurulum yeni kapsam: `overrideWith` ilk
    // kurulumdakini korurdu.
    key: UniqueKey(),
    overrides: [
      fonXrayGorunurProvider.overrideWithValue(gorunur),
      premiumKilitliProvider.overrideWithValue(kilitli),
      fonXrayKalemAcikProvider.overrideWithValue(kalemAcik),
      fonDagilimiProvider.overrideWith((ref, kod) async {
        _okuma++;
        return dag;
      }),
      fonKalemleriProvider
          .overrideWith((ref, kod) async => kalemAcik ? kalemler : null),
      ...ek,
    ],
    child: MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      home: govde,
    ),
  ));
  await t.pumpAndSettle();
}

Widget _kart({AssetType tur = AssetType.fon, String ticker = 'TEFAS:AAL'}) =>
    Scaffold(
      body: SingleChildScrollView(
        child: FonDagilimiKarti(tur: tur, ticker: ticker),
      ),
    );

/// Kartın ya da ekranın herhangi bir yerinde yüzde/tutar var mı.
bool _sayiVar() =>
    find.textContaining('%').evaluate().isNotEmpty ||
    find.textContaining('₺').evaluate().isNotEmpty;

void main() {
  tearDown(() {
    RemoteConfigService.testAcik = {};
    RemoteConfigService.instance.yonetici = false;
  });

  group('varlık kartı — dört hâl', () {
    testWidgets('1) paywall kapalı, admin değil: hiçbir şey, veri okunmaz',
        (t) async {
      await _kur(t, _kart(), gorunur: false, dag: _dag);
      expect(find.byType(SandikCard), findsNothing);
      expect(find.byType(PremiumKilitKarti), findsNothing);
      expect(find.text('FONUN İÇİNDE NE VAR'), findsNothing);
      expect(_okuma, 0);
    });

    testWidgets('2) admin: çubuk, kovalar, kaynak ve tarih', (t) async {
      await _kur(t, _kart(), gorunur: true, dag: _dag);
      expect(find.text('FONUN İÇİNDE NE VAR'), findsOneWidget);
      expect(find.byType(XrayCubugu), findsOneWidget);
      // Para piyasası (tpp + tr) en büyük kova, kaynaktaki toplamıyla.
      expect(find.text('Para piyasası / repo'), findsOneWidget);
      expect(find.text('%48,82'), findsOneWidget);
      expect(find.text('Mevduat / katılma hesabı'), findsOneWidget);
      expect(find.text('%25,07'), findsOneWidget);
      expect(find.text('Devlet borçlanması (TL)'), findsOneWidget);
      expect(find.text('Özel sektör borçlanması'), findsOneWidget);
      expect(find.text('TEFAS · 9 Ekim 2026'), findsOneWidget);
      // Fonda olmayan sınıf satırı yok.
      expect(find.text('BIST hisse'), findsNothing);
      // Toplam 100: sapma notu yok.
      expect(find.textContaining('fark hiçbir sınıfa eklenmedi'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets(
        '3) paywall açık + ücretsiz: kilit kartı, sayı yok, veri '
        'okunmaz', (t) async {
      await _kur(t, _kart(), gorunur: true, kilitli: true, dag: _dag);
      expect(find.byType(PremiumKilitKarti), findsOneWidget);
      expect(find.text("Fonun içinde ne var Premium'da"), findsOneWidget);
      expect(find.byType(XrayCubugu), findsNothing);
      expect(find.text('Para piyasası / repo'), findsNothing);
      expect(_sayiVar(), isFalse);
      expect(_okuma, 0);
    });

    testWidgets('4) Premium: veri; veri yoksa kart hiç yok', (t) async {
      await _kur(t, _kart(), gorunur: true, dag: _dag);
      expect(find.byType(XrayCubugu), findsOneWidget);

      await _kur(t, _kart(), gorunur: true, dag: null);
      expect(find.byType(SandikCard), findsNothing);
      expect(find.text('FONUN İÇİNDE NE VAR'), findsNothing);
    });

    testWidgets('BES fonu da kart alır; hisse/mevduat almaz', (t) async {
      await _kur(t, _kart(tur: AssetType.bes, ticker: 'AEA'),
          gorunur: true, dag: _dag);
      expect(find.byType(XrayCubugu), findsOneWidget);

      for (final (tur, ticker) in [
        (AssetType.hisse, 'THYAO.IS'),
        (AssetType.mevduat, 'MEV'),
      ]) {
        await _kur(t, _kart(tur: tur, ticker: ticker),
            gorunur: true, kilitli: true, dag: _dag);
        expect(find.byType(PremiumKilitKarti), findsNothing, reason: '$tur');
        expect(find.byType(SandikCard), findsNothing, reason: '$tur');
      }
    });

    testWidgets('Σ ≠ 100: kart toplamı söyler, farkı dağıtmaz', (t) async {
      await _kur(t, _kart(),
          gorunur: true,
          dag: FonDagilimi(
              fonKodu: 'AAL',
              fonTipi: 'YAT',
              tarih: DateTime(2026, 10, 9),
              dagilim: const {'hs': 60, 'dt': 30}));
      expect(find.text('%60,00'), findsOneWidget);
      expect(find.text('%30,00'), findsOneWidget);
      expect(
          find.text(
              'Kaynaktaki sınıfların toplamı %90,00; fark hiçbir sınıfa eklenmedi.'),
          findsOneWidget);
      expect(find.text('Diğer'), findsNothing);
    });

    testWidgets('Katman A: bayrak kapalıyken kalem yok, açıkken ilk 10',
        (t) async {
      await _kur(t, _kart(), gorunur: true, dag: _dag, kalemler: _kalemler);
      expect(find.textContaining('En büyük'), findsNothing);
      expect(find.textContaining('KAP Portföy Dağılım Raporu'), findsNothing);

      await _kur(t, _kart(),
          gorunur: true, dag: _dag, kalemAcik: true, kalemler: _kalemler);
      expect(find.text('En büyük 10 kalem'), findsOneWidget);
      expect(find.text('K1 · Kalem 1'), findsOneWidget);
      expect(find.text('K10 · Kalem 10'), findsOneWidget);
      expect(find.text('K11 · Kalem 11'), findsNothing);
      expect(find.text('KAP Portföy Dağılım Raporu · Eylül 2026 sonu'),
          findsOneWidget);
      expect(find.text("Raporu KAP'ta aç"), findsOneWidget);
    });

    testWidgets('cizilir: kartın kendi koşuluyla aynı', (t) async {
      late bool sonuc;
      Widget yoklayici(AssetType tur) => Consumer(builder: (_, ref, __) {
            sonuc = FonDagilimiKarti.cizilir(ref, tur, 'AAL');
            return const SizedBox();
          });
      await _kur(t, yoklayici(AssetType.fon), gorunur: false, dag: _dag);
      expect(sonuc, isFalse);
      await _kur(t, yoklayici(AssetType.fon), gorunur: true, kilitli: true);
      expect(sonuc, isTrue);
      await _kur(t, yoklayici(AssetType.fon), gorunur: true, dag: null);
      expect(sonuc, isFalse);
      await _kur(t, yoklayici(AssetType.fon), gorunur: true, dag: _dag);
      expect(sonuc, isTrue);
      await _kur(t, yoklayici(AssetType.hisse), gorunur: true, dag: _dag);
      expect(sonuc, isFalse);
    });
  });

  group('görünürlük kararı tek anahtardan', () {
    test(
        'paywall kapalı + admin değil → görünmez; paywall açık ya da admin '
        '→ görünür', () {
      bool oku() {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        return c.read(fonXrayGorunurProvider);
      }

      RemoteConfigService.testAcik = {};
      RemoteConfigService.instance.yonetici = false;
      expect(oku(), isFalse);
      RemoteConfigService.testAcik = {'paywall_enabled'};
      expect(oku(), isTrue);
      RemoteConfigService.testAcik = {};
      RemoteConfigService.instance.yonetici = true;
      expect(oku(), isTrue);
    });

    test('fon_xray_kalem varsayılan KAPALI', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(fonXrayKalemAcikProvider), isFalse);
      final src = ekranKaynagiSync('lib/services/remote_config_service.dart');
      expect(src.contains("'fon_xray_kalem': false,"), isTrue);
    });
  });

  group('Raporlar kapısı satırı', () {
    Future<void> sayfa(WidgetTester t, {required bool kilitli}) async {
      await _kur(
        t,
        Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => raporlarSayfasiniAc(ctx, siralamaAcik: false),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
        gorunur: true,
        kilitli: kilitli,
        ek: [
          balinaRadariAcikProvider.overrideWithValue(false),
          aylikRaporDonemiProvider.overrideWithValue(null),
          yilOzetiProvider.overrideWith((ref) async => null),
        ],
      );
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
    }

    testWidgets('Premium görünmüyorsa satır yok', (t) async {
      RemoteConfigService.testAcik = {};
      RemoteConfigService.instance.yonetici = false;
      await sayfa(t, kilitli: false);
      expect(find.text('Portföy X-Ray'), findsNothing);
    });

    testWidgets(
        'admin: satır var, ok ile; Yıllık rapor ve Temettü hâlâ yerinde',
        (t) async {
      RemoteConfigService.instance.yonetici = true;
      await sayfa(t, kilitli: false);
      expect(find.text('Portföy X-Ray'), findsOneWidget);
      expect(find.text('Fonlarının içi dahil, paran gerçekte nerede'),
          findsOneWidget);
      expect(find.text('Yıllık rapor'), findsOneWidget);
      expect(find.text('Temettü tahmini'), findsOneWidget);
    });

    testWidgets('paywall açık + ücretsiz: satır kilit simgesiyle', (t) async {
      RemoteConfigService.testAcik = {'paywall_enabled'};
      await sayfa(t, kilitli: true);
      expect(find.text('Portföy X-Ray'), findsOneWidget);
      // Üç Premium satırının üçü de kilitli.
      expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(3));
    });
  });

  group('Portföy X-Ray ekranı', () {
    final ornek = PortfoyXray(
      toplam: 20000,
      kovalar: const {
        XrayKova.bistHisse: 6000,
        XrayKova.paraPiyasasi: 5000,
        XrayKova.kiymetliMaden: 4000,
      },
      xrayDisi: 5000,
      xrayDisiFonlar: const [
        XrayDisiFon(ad: 'Yok fonu', kod: 'YOK', tutar: 5000)
      ],
      fonTarihleri: (DateTime(2026, 10, 7), DateTime(2026, 10, 9)),
      ortusmeler: const [
        Ortusme(
            kod: 'THYAO',
            ad: 'TÜRK HAVA YOLLARI',
            fonlar: ['AAA', 'BBB'],
            dogrudan: true,
            tutar: 2400),
      ],
      kalemDonemi: DateTime(2026, 9, 30),
    );

    Future<void> ekran(WidgetTester t,
        {bool kilitli = false, AsyncValue<PortfoyXray>? deger}) async {
      await _kur(t, const PortfoyXrayScreen(),
          gorunur: true,
          kilitli: kilitli,
          ek: [
            portfoyXrayProvider
                .overrideWithValue(deger ?? AsyncValue.data(ornek)),
          ]);
    }

    testWidgets('kilitli: tek kilit kartı, sayı yok', (t) async {
      await ekran(t, kilitli: true);
      expect(find.byType(PremiumKilitKarti), findsOneWidget);
      expect(find.text("Portföy X-Ray Premium'da"), findsOneWidget);
      expect(_sayiVar(), isFalse);
    });

    testWidgets('dağılım, X-Ray dışı, örtüşme ve kaynak satırları', (t) async {
      await ekran(t);
      expect(find.text('₺20.000'), findsOneWidget);
      expect(find.text('BIST hisse'), findsOneWidget);
      expect(find.text('%30,0'), findsOneWidget);
      expect(find.text('₺6.000'), findsOneWidget);
      // X-Ray dışı ayrı satır; %25 — diğerlerine dağıtılmadı.
      expect(find.text('X-Ray dışı'), findsOneWidget);
      expect(find.text('%25,0'), findsWidgets);
      expect(find.text('Dağılımı bulunamayan: YOK'), findsOneWidget);
      // Örtüşme.
      expect(find.text('THYAO · TÜRK HAVA YOLLARI'), findsOneWidget);
      expect(find.text('3 yerden: AAA, BBB, doğrudan'), findsOneWidget);
      expect(find.text('₺2.400'), findsOneWidget);
      expect(
          find.text(
              'Kalemler: KAP Portföy Dağılım Raporları · Eylül 2026 sonu'),
          findsOneWidget);
      // Kaynak + tarih.
      expect(find.text('Fonlar: TEFAS günlük dağılımı · 7 Eki - 9 Ekim 2026'),
          findsOneWidget);
      expect(find.textContaining('ortaklarının varlıkları dahil değil'),
          findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('örtüşme yoksa bölüm yok', (t) async {
      await ekran(t,
          deger: AsyncValue.data(PortfoyXray(
            toplam: 100,
            kovalar: const {XrayKova.bistHisse: 100},
            xrayDisi: 0,
            xrayDisiFonlar: const [],
            fonTarihleri: null,
            ortusmeler: const [],
            kalemDonemi: null,
          )));
      expect(find.text('BİRDEN ÇOK YERDEN TUTTUKLARIN'), findsNothing);
      expect(find.text('X-Ray dışı'), findsNothing);
      expect(find.textContaining('TEFAS günlük'), findsNothing);
    });

    testWidgets('boş portföy: boş durum; hata: yeniden dene', (t) async {
      await ekran(t,
          deger: AsyncValue.data(PortfoyXray(
            toplam: 0,
            kovalar: const {},
            xrayDisi: 0,
            xrayDisiFonlar: const [],
            fonTarihleri: null,
            ortusmeler: const [],
            kalemDonemi: null,
          )));
      expect(find.byType(SandikBosDurum), findsOneWidget);

      await ekran(t,
          deger: AsyncValue.error(Exception('ağ'), StackTrace.empty));
      expect(find.byType(SandikErrorView), findsOneWidget);
    });
  });

  group('yerleşim kaynakta', () {
    test(
        'varlık ekranı: kart fon karnesinin hemen altında (eski yığın ve '
        'katmanlı düzen)', () {
      final src = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
      expect(src.contains('_fonKarnesi(),\n                _fonDagilimi(),'),
          isTrue);
      expect(
          src.contains('FonDagilimiKarti.cizilir(ref, tur, ticker)'), isTrue);
    });

    test('ekran ve kart Supabase/http doğrudan kullanmaz', () {
      for (final yol in [
        'lib/widgets/fon_dagilimi_karti.dart',
        'lib/screens/portfoy_xray_screen.dart',
      ]) {
        final src = ekranKaynagiSync(yol);
        expect(src.contains('Supabase.instance'), isFalse, reason: yol);
        expect(src.contains("package:http/"), isFalse, reason: yol);
      }
    });
  });
}
