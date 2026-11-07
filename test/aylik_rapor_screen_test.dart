import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/analiz_provider.dart';
import 'package:portfoy_takip/providers/aylik_rapor_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/aylik_rapor_screen.dart';
import 'package:portfoy_takip/services/aylik_rapor_ozeti.dart';
import 'package:portfoy_takip/services/varlik_analizi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/pozisyon_etiketi.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/aylik_rapor_bolumleri.dart';

/// Aylık rapor (S18-B; kapsam 2026-11-07). Özet cümlesi notu çıkan
/// varlıkları sayar; notu çıkmayanlar adlarıyla anılır. 2026-11-07'den
/// beri rapor yalnız yapay zekâ notlarından ibaret değil: kapsam satırı,
/// ayın varlıkları (notu olmayanlar dahil), para girişi/çıkışı, önemli
/// gelişmeler ve "haber yok" kaydı.
void main() {
  final ay = DateTime.utc(2026, 9, 1);

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  AnalizOzeti not(String t, String rozet) => AnalizOzeti(
      ticker: t,
      donem: ay,
      baslik: '$t başlığı',
      rozet: rozet,
      maddeSayisi: 2,
      veriBaslangic: DateTime.utc(2026, 9, 1),
      veriBitis: DateTime.utc(2026, 9, 30));

  Asset lot(String ticker, AssetType tur, {String ad = '', String? alt}) =>
      Asset(
        subCategory: alt,
        id: ticker,
        userId: 'u',
        name: ad.isEmpty ? ticker : ad,
        ticker: ticker,
        type: tur,
        quantity: 10,
        purchasePrice: 100,
        currency: 'TRY',
        notes: '',
        addedDate: DateTime(2026, 8, 1),
      );

  final altin =
      lot('GC=F', AssetType.altin, ad: 'Gram altın', alt: 'Gram Altın');
  final dolu = AylikRaporOzeti(
    bas: DateTime(2026, 9),
    bit: DateTime(2026, 9, 30),
    surenAy: false,
    varliklar: [
      AyinVarligi(
          anahtar: positionKey(lot('THYAO.IS', AssetType.hisse)),
          tur: AssetType.hisse,
          ad: 'THYAO',
          pct: 8.2,
          piyasaTRY: 820),
      AyinVarligi(
          anahtar: positionKey(altin),
          tur: AssetType.altin,
          ad: 'Gram altın',
          pct: -1.5,
          piyasaTRY: -150),
    ],
    akis: const AyinParaAkisi(
        alimTRY: 10000, alimSayisi: 2, satisTRY: 2000, satisSayisi: 1),
    gelismeler: [
      AyinGelismesi(
          tarih: DateTime(2026, 9, 12),
          kod: 'TTE',
          tur: AyinGelismeTuru.fonGiris,
          tutar: 85e6,
          oran: 0.031),
    ],
    fiyatTarihi: DateTime(2026, 9, 30, 18),
  );

  Widget ekran({
    List<Override> ek = const [],
    Map<String, AnalizOzeti>? notlar,
    AylikRaporOzeti? ozet,
    double yazi = 1,
    double genislik = 390,
  }) =>
      ProviderScope(
        overrides: [
          tutulanNotAnahtarlariProvider.overrideWithValue([
            'TEFAS:TTE',
            'TEFAS:AFT',
            'THYAO.IS',
            'KRIPTO:BTC',
            'TEFAS:AH5'
          ]),
          notOzetleriProvider.overrideWith((ref, a) async =>
              notlar ??
              {
                'TEFAS:TTE': not('TEFAS:TTE', 'buyuk_giris'),
                'THYAO.IS': not('THYAO.IS', 'sakin'),
                'KRIPTO:BTC': not('KRIPTO:BTC', 'sakin'),
              }),
          aylikRaporOzetiProvider.overrideWith((ref, d) async => ozet),
          ...ek,
        ],
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                size: Size(genislik, 844), textScaler: TextScaler.linear(yazi)),
            child: child!,
          ),
          home: AylikRaporScreen(donem: ay),
        ),
      );

  AppLocalizations l(WidgetTester t) =>
      AppLocalizations.of(t.element(find.byType(AylikRaporScreen)))!;

  testWidgets('notu çıkmayan tutulan varlıklar adlarıyla yazılır',
      (tester) async {
    await tester.pumpWidget(ekran());
    await tester.pumpAndSettle();
    final l10n = l(tester);
    expect(find.text(l10n.anzAylikOzetVar('3', '1')), findsOneWidget);
    // PDF (2026-10-31): özet cümlesinin sağında tek paylaş simgesi, 44 pt,
    // etiketli; cümleyle aynı satırın üstünde.
    final pdf = find.byTooltip(l10n.anzAylikPdfPaylas);
    expect(pdf, findsOneWidget);
    expect(tester.getSize(pdf).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(pdf).height, greaterThanOrEqualTo(44));
    expect(
        tester.getTopLeft(pdf).dy,
        lessThanOrEqualTo(
            tester.getTopLeft(find.text(l10n.anzAylikOzetVar('3', '1'))).dy));
    await tester.scrollUntilVisible(
        find.text(l10n.anzAylikEksik('AFT, AH5')), 200);
    expect(find.text(l10n.anzAylikEksik('AFT, AH5')), findsOneWidget);
  });

  testWidgets('kapsam satırı ayın günlerini açık tarihle yazar', (t) async {
    await t.pumpWidget(ekran());
    await t.pumpAndSettle();
    final l10n = l(t);
    expect(find.text(l10n.raporKapsam('1–30 Eylül 2026')), findsOneWidget);
    // Notların veri aralığı da yazılır.
    expect(find.text(l10n.anzAylikNotlarAralik('1–30 Eylül 2026')),
        findsOneWidget);
    // Haber kaynağı yok: rapor bunu kendisi söyler, haber metni uydurmaz.
    await t.scrollUntilVisible(find.text(l10n.anzAylikHaberYok), 200);
    expect(find.text(l10n.anzAylikHaberYok), findsOneWidget);
  });

  testWidgets('sayısal veri yoksa yeni bölümler yok (uydurma yok)', (t) async {
    await t.pumpWidget(ekran(ozet: null));
    await t.pumpAndSettle();
    expect(find.byType(AyinVarliklariBolumu), findsNothing);
    expect(find.byType(ParaAkisiBolumu), findsNothing);
    expect(find.byType(GelismelerBolumu), findsNothing);
    // Boş özet de bölüm çizmez.
    await t.pumpWidget(ekran(
        ozet: AylikRaporOzeti(
            bas: DateTime(2026, 9),
            bit: DateTime(2026, 9, 30),
            surenAy: false)));
    await t.pumpAndSettle();
    expect(find.byType(AyinVarliklariBolumu), findsNothing);
    expect(find.byType(ParaAkisiBolumu), findsNothing);
    expect(find.byType(GelismelerBolumu), findsNothing);
  });

  testWidgets('üç bölüm: notu olmayan altın da ayın varlıklarında', (t) async {
    await t.pumpWidget(ekran(ozet: dolu));
    await t.pumpAndSettle();
    final l10n = l(t);
    expect(find.text(l10n.anzAylikVarliklarBaslik), findsOneWidget);
    // Altının notu yok ama satırı var (yasin: "tüm varlıklar").
    final altinAdi = pozisyonEtiketi(positionKey(altin), AssetType.altin, l10n,
        ad: 'Gram altın');
    expect(find.text(altinAdi), findsOneWidget);
    expect(find.text(fmtPctIsaretli(-1.5, digits: 1)), findsOneWidget);
    expect(find.text('−₺150'), findsOneWidget);
    expect(find.text(l10n.anzAylikAkisBaslik), findsOneWidget);
    expect(find.text(l10n.anzAylikAkisNet), findsOneWidget);
    expect(find.text('+₺8.000'), findsOneWidget);
    await t.scrollUntilVisible(find.text(l10n.anzAylikGelismeBaslik), 200);
    expect(find.textContaining('Büyük para girişi'), findsOneWidget);
  });

  testWidgets('not çıkmayan ayda rapor sayısal bölümlerle açılır', (t) async {
    await t.pumpWidget(ekran(notlar: const {}, ozet: dolu));
    await t.pumpAndSettle();
    final l10n = l(t);
    expect(find.text(l10n.anzAylikBos), findsNothing);
    expect(find.byType(AyinVarliklariBolumu), findsOneWidget);
    expect(find.text(l10n.anzAylikNotlarBaslik), findsNothing);
  });

  testWidgets('ikisi de boşsa "hazır değil"', (t) async {
    await t.pumpWidget(ekran(notlar: const {}, ozet: null));
    await t.pumpAndSettle();
    expect(find.text(l(t).anzAylikBos), findsOneWidget);
  });

  for (final (yazi, genislik) in [(3.1, 390.0), (1.0, 320.0), (3.1, 320.0)]) {
    testWidgets('${yazi}x / $genislik pt taşma yok', (t) async {
      t.view.physicalSize = Size(genislik * 2, 844 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(ekran(ozet: dolu, yazi: yazi, genislik: genislik));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.drag(find.byType(ListView), const Offset(0, -3000));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }

  // Kök neden regresyonu (yasin 2026-11-07: "aylık raporda neden sadece
  // fonların raporları var"). Portföydeki hisse ve coin, raporun not
  // sorgusuna sunucunun yazdığı anahtar biçimiyle ('THYAO.IS',
  // 'KRIPTO:BTC') girer ve notları kartlanır; altın gibi radar dışı varlık
  // not sorgusuna girmez ama ayın varlıklarında satırı olur.
  testWidgets('portföydeki hisse ve coin raporun not sorgusuna girer',
      (t) async {
    String? sorgu;
    final lotlar = [
      lot('TEFAS:TTE', AssetType.fon),
      lot('THYAO.IS', AssetType.hisse),
      lot('KRIPTO:BTC', AssetType.kripto),
      altin,
    ];
    await t.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(() => _Portfoy(lotlar)),
        notOzetleriProvider.overrideWith((ref, a) async {
          sorgu = a.$1;
          return {
            for (final k in a.$1.split(',')) k: not(k, 'sakin'),
          };
        }),
        aylikRaporOzetiProvider.overrideWith((ref, d) async => dolu),
      ],
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AylikRaporScreen(donem: ay),
      ),
    ));
    await t.pumpAndSettle();
    expect(sorgu, 'KRIPTO:BTC,TEFAS:TTE,THYAO.IS');
    final l10n = l(t);
    expect(find.text(l10n.anzAylikOzetYok), findsOneWidget);
    for (final kod in ['BTC', 'TTE', 'THYAO']) {
      await t.scrollUntilVisible(find.text(kod), 200);
      expect(find.text(kod), findsOneWidget, reason: kod);
    }
  });
}

class _Portfoy extends PortfolioNotifier {
  _Portfoy(this.lotlar);
  final List<Asset> lotlar;
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: lotlar, ownerId: 'u', usdTry: 42);
}
