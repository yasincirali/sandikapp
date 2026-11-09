import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/grafik_cizimi.dart';
import 'package:portfoy_takip/models/ohlc.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show premiumKilitliProvider;
import 'package:portfoy_takip/providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import 'package:portfoy_takip/screens/tam_ekran_grafik_screen.dart';
import 'package:portfoy_takip/services/cizim_alarmi.dart';
import 'package:portfoy_takip/services/mum_verisi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yatay grafikte çizimden alarm (0170, yasin 2026-10-29: *"Gösterge ya da
/// çizgiye değdiğinde push gelmesi yapılabilir mi?"*).
///
/// Kilitlenen:
///  · Birim kapısı: çizginin fiyatı grafiğin (TL) birimindedir; alarm
///    sembolün kendi kotasyonuyla karşılaştırılır. Birimler aynı değilse
///    "Alarm kur" HİÇ sunulmaz (uydurma hedef yok).
///  · Trend/ışın → sunucu doğrusu: grafikte görünen doğruyla aynı değer.
///  · Çizim kimliği yerelde saklanır (alarm çizimi onunla bulur).
///  · Yatay ekranda düğmenin görünürlüğü: yatay çizgi ücretsiz, trend
///    Premium görünürken.
const _gun = 86400000;

Asset _varlik({String ticker = 'THYAO.IS', String para = 'TRY',
        double fiyat = 101, String? alt, bool elle = false}) =>
    Asset(
      id: 'v1',
      userId: 'u1',
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      subCategory: alt,
      quantity: 1,
      purchasePrice: 100,
      currency: para,
      notes: '',
      isManualPrice: elle,
      currentPrice: fiyat,
      addedDate: DateTime(2025, 3, 14),
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('birim kapısı', () {
    test('TL kote BIST hissesi: sembol döner', () {
      expect(cizimAlarmSembolu(_varlik(), 101), 'THYAO.IS');
    });

    test('dolar kote ABD hissesi: grafik TL, alarm USD → sunulmaz', () {
      expect(cizimAlarmSembolu(_varlik(ticker: 'AAPL', para: 'USD'), 9500),
          isNull);
    });

    test('elle fiyatlanan ve eurobond: sunulmaz', () {
      expect(cizimAlarmSembolu(_varlik(elle: true), 101), isNull);
      expect(
          cizimAlarmSembolu(
              _varlik(ticker: 'EUROBOND:US900123DF45'), 101),
          isNull);
    });

    test('grafik birimi varlık fiyatından %2\'den fazla saparsa sunulmaz', () {
      expect(cizimAlarmSembolu(_varlik(fiyat: 100), 101.5), 'THYAO.IS');
      expect(cizimAlarmSembolu(_varlik(fiyat: 100), 110), isNull);
      // Fiyatı bilinmeyen gözlem varlığı: sembol kuralı yeter.
      expect(cizimAlarmSembolu(_varlik(fiyat: 0), 101), 'THYAO.IS');
    });
  });

  group('doğru', () {
    // Basit ölçek: mum indeksi = gün sayısı (boşluksuz).
    double indeks(int t) => t / _gun;
    const simdi = 100 * _gun;

    GrafikCizimi trend(int ta, double pa, int tb, double pb,
            {CizimTuru tur = CizimTuru.trend}) =>
        GrafikCizimi(
            tur: tur, a: CizimNoktasi(ta, pa), b: CizimNoktasi(tb, pb));

    test('süren trend: şimdiki noktadan sağ uca', () {
      // 90. günde 100, 110. günde 120 → mum başı 1; şimdi (100) = 110.
      final r = cizimAlarmDogrusu(trend(90 * _gun, 100, 110 * _gun, 120),
          indeks: indeks, aralikMs: _gun, simdiMs: simdi)!;
      final d = r.dogru!;
      expect(d.t1, simdi);
      expect(d.p1, closeTo(110, 1e-9));
      expect(d.t2, 110 * _gun);
      expect(d.p2, 120);
      expect(d.uzanir, isFalse);
    });

    test('ters çizilmiş trend (sağdan sola) aynı doğru', () {
      final d = cizimAlarmDogrusu(trend(110 * _gun, 120, 90 * _gun, 100),
              indeks: indeks, aralikMs: _gun, simdiMs: simdi)!
          .dogru!;
      expect(d.p1, closeTo(110, 1e-9));
      expect(d.t2, 110 * _gun);
    });

    test('geçmişte bitmiş trend: alarm kurulmaz', () {
      final r = cizimAlarmDogrusu(trend(50 * _gun, 100, 80 * _gun, 120),
          indeks: indeks, aralikMs: _gun, simdiMs: simdi)!;
      expect(r.dogru, isNull);
      expect(r.engel, CizimAlarmEngeli.bitti);
    });

    test('ışın: şimdiden bir mum sonraya, uzar', () {
      final d = cizimAlarmDogrusu(
              trend(90 * _gun, 100, 95 * _gun, 105, tur: CizimTuru.isin),
              indeks: indeks,
              aralikMs: _gun,
              simdiMs: simdi)!
          .dogru!;
      expect(d.t1, simdi);
      expect(d.p1, closeTo(110, 1e-9));
      expect(d.t2, simdi + _gun);
      expect(d.p2, closeTo(111, 1e-9));
      expect(d.uzanir, isTrue);
    });

    test('geçmişe bakan ışın ve dikey çizgi: yönsüz', () {
      expect(
          cizimAlarmDogrusu(
                  trend(95 * _gun, 100, 90 * _gun, 105, tur: CizimTuru.isin),
                  indeks: indeks,
                  aralikMs: _gun,
                  simdiMs: simdi)!
              .engel,
          CizimAlarmEngeli.yonsuz);
      expect(
          cizimAlarmDogrusu(trend(95 * _gun, 100, 95 * _gun, 120),
                  indeks: indeks, aralikMs: _gun, simdiMs: simdi)!
              .engel,
          CizimAlarmEngeli.yonsuz);
    });

    test('sıfırın altına inen doğru: geçersiz (fiyat orada olamaz)', () {
      final r = cizimAlarmDogrusu(
          trend(90 * _gun, 20, 95 * _gun, 5, tur: CizimTuru.isin),
          indeks: indeks,
          aralikMs: _gun,
          simdiMs: simdi)!;
      expect(r.engel, CizimAlarmEngeli.gecersiz);
    });

    test('yatay ve kutu buraya gelmez', () {
      expect(
          cizimAlarmDogrusu(
              const GrafikCizimi(tur: CizimTuru.yatay, a: CizimNoktasi(0, 1)),
              indeks: indeks,
              aralikMs: _gun,
              simdiMs: simdi),
          isNull);
    });
  });

  group('kimlik ve imza', () {
    test('kimlik JSON\'da gidip gelir, eşitliğe girmez', () {
      final c = GrafikCizimi(
          tur: CizimTuru.trend,
          a: const CizimNoktasi(1, 2),
          b: const CizimNoktasi(3, 4),
          id: GrafikCizimi.yeniKimlik());
      final geri = GrafikCizimi.fromJson(c.toJson())!;
      expect(geri.id, c.id);
      expect(geri, c.copyWith(id: 'baska'));
      // Eski kayıt (kimliksiz) bugünkü gibi okunur.
      final eski = GrafikCizimi.fromJson(
          {'tur': 'yatay', 'a': {'t': 1, 'p': 2}})!;
      expect(eski.id, isNull);
      // Bozuk kimlik düşer, çizim kalır.
      expect(
          GrafikCizimi.fromJson(
                  {'tur': 'yatay', 'a': {'t': 1, 'p': 2}, 'id': 'x' * 65})!
              .id,
          isNull);
    });

    test('imza biçimi izler, kimliği değil', () {
      const a = GrafikCizimi(
          tur: CizimTuru.trend,
          a: CizimNoktasi(1, 2),
          b: CizimNoktasi(3, 4));
      expect(cizimImzasi(a), cizimImzasi(a.copyWith(id: 'k')));
      expect(cizimImzasi(a),
          isNot(cizimImzasi(a.copyWith(b: const CizimNoktasi(3, 5)))));
    });
  });

  group('yatay ekranda "Alarm kur"', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      MumVerisi.instance.onbellegiTemizle();
      final simdi = DateTime.now();
      final bas = DateTime(simdi.year, simdi.month, simdi.day)
          .subtract(const Duration(days: 199))
          .millisecondsSinceEpoch;
      MumVerisi.testCekici = (a, ar, b, s) async => [
            for (var i = 0; i < 200; i++)
              OhlcBar(
                t: bas + i * _gun,
                acilis: 100 + 10 * math.sin(i / 9),
                enYuksek: 104 + 10 * math.sin(i / 9),
                enDusuk: 96 + 10 * math.sin(i / 9),
                kapanis: 101 + 10 * math.sin(i / 9),
                hacim: 1000,
              ),
          ];
    });
    tearDown(() => MumVerisi.testCekici = null);

    Future<TamEkranGrafikEkraniState> ac(WidgetTester t, Asset varlik,
        {bool premium = false}) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(844, 390);
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          premiumOzellikleriGorunurProvider.overrideWithValue(premium),
          premiumKilitliProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TamEkranGrafikEkrani(
              varlik: varlik, ad: varlik.ticker, canliBirim: 101),
        ),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      return t.state<TamEkranGrafikEkraniState>(
          find.byType(TamEkranGrafikEkrani));
    }

    Rect alan(WidgetTester t) => t.getRect(find.byWidgetPredicate((w) =>
        w is Listener && w.onPointerSignal != null && w.onPointerDown != null));

    Future<void> yatayCiz(WidgetTester t) async {
      await t.tap(find.byTooltip('Yatay çizgi'));
      await t.pump();
      await t.tapAt(alan(t).topLeft + const Offset(300, 120));
      await t.pump();
    }

    Future<void> trendCiz(WidgetTester t) async {
      await t.tap(find.byTooltip('Trend çizgisi'));
      await t.pump();
      await t.dragFrom(
          alan(t).topLeft + const Offset(200, 150), const Offset(180, -70));
      await t.pump();
    }

    Future<void> bitir(WidgetTester t) =>
        t.pump(const Duration(seconds: 5));

    const dugme = ValueKey('tamEkranCizimAlarmi');

    testWidgets('yatay çizgi + TL hissesi: görünür, 44 pt, etiketli',
        (t) async {
      final s = await ac(t, _varlik());
      await yatayCiz(t);
      expect(s.secili, 0);
      expect(find.byKey(dugme), findsOneWidget);
      final b = t.getSize(find.byKey(dugme));
      expect(b.width, greaterThanOrEqualTo(SandikTouch.min));
      expect(b.height, greaterThanOrEqualTo(SandikTouch.min));
      expect(find.byTooltip('Bu çizgiye alarm kur'), findsOneWidget);
      await bitir(t);
    });

    testWidgets('yatay çizgi + dolar hissesi: düğme yok (birim farklı)',
        (t) async {
      final s = await ac(t, _varlik(ticker: 'AAPL', para: 'USD'));
      await yatayCiz(t);
      expect(s.secili, 0);
      expect(find.byKey(const ValueKey('tamEkranCizimiSil')), findsOneWidget);
      expect(find.byKey(dugme), findsNothing);
      await bitir(t);
    });

    testWidgets('trend: Premium görünmüyorsa düğme yok', (t) async {
      final s = await ac(t, _varlik());
      await trendCiz(t);
      expect(s.secili, 0);
      expect(find.byKey(dugme), findsNothing);
      await bitir(t);
    });

    testWidgets('trend: Premium görünürken düğme var', (t) async {
      final s = await ac(t, _varlik(), premium: true);
      await trendCiz(t);
      expect(s.secili, 0);
      expect(find.byKey(dugme), findsOneWidget);
      // Yeni çizim kimlik taşır: alarm çizimi onunla bulur.
      expect(s.cizimler.single.id, isNotNull);
      await bitir(t);
    });
  });
}
