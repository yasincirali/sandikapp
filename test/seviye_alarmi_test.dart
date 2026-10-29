import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/seviye_alarmi.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/seviye_alarmi_service.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart';
import 'package:portfoy_takip/widgets/sandik_segment.dart';

/// Gösterge ve çizgi alarmları (0170, yasin 2026-10-29: *"Gösterge ya da
/// çizgiye değdiğinde push gelmesi yapılabilir mi?"*).
///
/// Kilitlenen:
///  · Sunucunun gösterge matematiği (`_shared/gosterge_alarmi.ts`) grafiğin
///    çizdiğiyle AYNI sayıyı verir: aynı altın vektör Deno testinde
///    (`supabase/tests/seviye_alarmi_test.ts`) TS'e, burada
///    `TechnicalAnalysisService`'e karşı doğrulanır. Biri değişirse ikisinden
///    biri kırılır — kullanıcı grafikte EMA50'yi 309'da görüp alarmın 311'de
///    çalmasını yaşamasın.
///  · Satır ↔ model ve CRUD (sahte depo; Supabase yok).
///  · Alarm sayfasında "Gösterge" sekmesi yalnız Premium görünürken ve
///    kapsamdaki sembolde; kilitliyken kurmaz, paywall'a gider.
void main() {
  group('gösterge matematiği istemciyle aynı', () {
    // Deno testindeki ALTIN ile birebir.
    final seri = [
      for (var i = 0; i < 260; i++)
        100 + 15 * math.sin(i * math.pi / 23) + 0.05 * i,
    ];
    const beklenen = {
      'ema20': 112.93387852363564,
      'ema50': 113.36301012372883,
      'ema200': 108.7112825901731,
      'sma20': 117.42546631045802,
      'bb_ust': 134.58200938142005,
      'bb_alt': 100.26892323949599,
    };

    test('EMA ve SMA: grafik serisinin son noktası', () {
      expect(TechnicalAnalysisService.emaSeries(seri, 20).last,
          closeTo(beklenen['ema20']!, 1e-9));
      expect(TechnicalAnalysisService.emaSeries(seri, 50).last,
          closeTo(beklenen['ema50']!, 1e-9));
      expect(TechnicalAnalysisService.emaSeries(seri, 200).last,
          closeTo(beklenen['ema200']!, 1e-9));
      expect(TechnicalAnalysisService.smaSeries(seri, 20).last,
          closeTo(beklenen['sma20']!, 1e-9));
    });

    test('Bollinger (20, 2σ, popülasyon sapması)', () {
      // Grafikteki bant tanımı: son 20 kapanışın ortalaması ± 2 × popülasyon
      // standart sapması (TradingView `ta.stdev` ile aynı).
      final son = seri.sublist(seri.length - 20);
      final ort = son.reduce((a, b) => a + b) / 20;
      final sapma = math.sqrt(
          son.map((x) => (x - ort) * (x - ort)).reduce((a, b) => a + b) / 20);
      expect(ort + 2 * sapma, closeTo(beklenen['bb_ust']!, 1e-9));
      expect(ort - 2 * sapma, closeTo(beklenen['bb_alt']!, 1e-9));
    });

    test('her gösterge kodu sunucuyla aynı alfabe', () {
      expect([for (final g in GostergeKodu.values) g.kod],
          ['ema20', 'ema50', 'ema200', 'sma20', 'bb_ust', 'bb_alt']);
      expect(GostergeKodu.koddan('rsi'), isNull);
    });
  });

  group('kapsam', () {
    test('hisse, ABD, kripto, fon evet; altın, TL döviz, eurobond hayır', () {
      for (final s in ['THYAO.IS', 'AAPL', 'KRIPTO:BTC', 'TEFAS:AFT']) {
        expect(FiyatKaynagi.gostergeAlarmiKapsamindaMi(s), isTrue, reason: s);
      }
      for (final s in [
        'ALTIN_GRAM',
        'USDTRY=X',
        'EURTRY=X',
        'GBPTRY=X',
        'EUROBOND:US900123DF45',
        '',
      ]) {
        expect(FiyatKaynagi.gostergeAlarmiKapsamindaMi(s), isFalse, reason: s);
      }
    });
  });

  group('yön', () {
    test('güncel fiyattan türer', () {
      expect(SeviyeYon.fiyattan(guncel: 90, seviye: 100), SeviyeYon.yukari);
      expect(SeviyeYon.fiyattan(guncel: 110, seviye: 100), SeviyeYon.asagi);
      expect(SeviyeYon.fiyattan(guncel: 100, seviye: 100), SeviyeYon.herIkisi);
      expect(SeviyeYon.fiyattan(guncel: 0, seviye: 100), SeviyeYon.herIkisi,
          reason: 'fiyat bilinmiyorsa yön uydurulmaz');
    });

    test('bilinmeyen kod iki yöne düşer', () {
      expect(SeviyeYon.koddan('her_ikisi'), SeviyeYon.herIkisi);
      expect(SeviyeYon.koddan('yukari'), SeviyeYon.yukari);
      expect(SeviyeYon.koddan('yana'), SeviyeYon.herIkisi);
    });
  });

  group('model', () {
    test('gösterge satırı okunur; çalmış alarm etkin değildir', () {
      final a = GostergeAlarmi.fromMap({
        'id': 7,
        'user_id': 'u',
        'symbol': 'THYAO.IS',
        'label': 'THY',
        'gosterge': 'ema50',
        'yon': 'asagi',
        'enabled': true,
        'triggered_at': '2026-10-29T10:00:00Z',
        'tetik_fiyat': '309.5',
        'tetik_seviye': 310,
        'created_at': '2026-10-28T10:00:00Z',
      })!;
      expect(a.id, '7');
      expect(a.gosterge, GostergeKodu.ema50);
      expect(a.yon, SeviyeYon.asagi);
      expect(a.tetikFiyat, 309.5);
      expect(a.isActive, isFalse);
    });

    test('bilinmeyen gösterge (ileri sürüm) listeden düşer', () {
      expect(GostergeAlarmi.fromMap({'id': 1, 'gosterge': 'rsi14'}), isNull);
    });

    test('çizgi satırı: doğrusu eksikse düşer, varsa okunur', () {
      expect(CizimAlarmi.fromMap({'id': 1, 't1': 1, 'p1': 2}), isNull);
      final a = CizimAlarmi.fromMap({
        'id': 'x',
        'user_id': 'u',
        'symbol': 'THYAO.IS',
        'label': 'THY',
        'cizim_id': 'c1',
        't1': 1000,
        'p1': '100.5',
        't2': 2000,
        'p2': 101,
        'uzanir': true,
        'yon': 'yukari',
      })!;
      expect(a.cizimId, 'c1');
      expect(a.p1, 100.5);
      expect(a.uzanir, isTrue);
      expect(a.isActive, isTrue);
      expect(a.toInsertMap()['cizim_id'], 'c1');
      expect(a.toInsertMap().containsKey('id'), isFalse,
          reason: 'kimlik sunucuda üretilir');
    });
  });

  group('servis', () {
    test('kur, yeniden kur (çalmış satır), taşı, sil', () async {
      final depo = _SahteDepo();
      final s = SeviyeAlarmiService(depo);
      final g = await s.gostergeKur(GostergeAlarmi(
          id: '',
          userId: 'u',
          symbol: 'THYAO.IS',
          label: 'THY',
          gosterge: GostergeKodu.ema200,
          yon: SeviyeYon.herIkisi,
          createdAt: DateTime(2026)));
      expect(depo.satirlar[SeviyeAlarmiService.gostergeTablosu], hasLength(1));
      expect((await s.gostergeleriGetir('u')).single.gosterge,
          GostergeKodu.ema200);
      await s.gostergeSil(g.id);
      expect(await s.gostergeleriGetir('u'), isEmpty);

      CizimAlarmi cizgi(double p1) => CizimAlarmi(
          id: '',
          userId: 'u',
          symbol: 'THYAO.IS',
          label: 'THY',
          cizimId: 'c1',
          t1: 1,
          p1: p1,
          t2: 2,
          p2: p1 + 1,
          uzanir: false,
          yon: SeviyeYon.yukari,
          createdAt: DateTime(2026));
      final ilk = await s.cizimKur(cizgi(100));
      // Sunucu çaldırdı; aynı çizimden yeniden kurmak YENİ satır açmaz.
      depo.satirlar[SeviyeAlarmiService.cizimTablosu]!.single
        ..['triggered_at'] = '2026-10-29T10:00:00Z'
        ..['son_taraf'] = 'ust';
      final eski = (await s.cizimleriGetir('u')).single;
      expect(eski.isActive, isFalse);
      final yeni = await s.cizimKur(cizgi(105), eski: eski);
      expect(yeni.id, ilk.id);
      expect(yeni.isActive, isTrue);
      expect(depo.satirlar[SeviyeAlarmiService.cizimTablosu], hasLength(1));
      expect(depo.satirlar[SeviyeAlarmiService.cizimTablosu]!.single['son_taraf'],
          isNull, reason: 'yeniden kurmada ilk tur yalnız taraf yazar');

      final tasinan = await s.cizimTasi(yeni.id, cizgi(120));
      expect(tasinan.p1, 120);
      await s.cizimSil(yeni.id);
      expect(await s.cizimleriGetir('u'), isEmpty);
    });
  });

  group('alarm sayfası Gösterge sekmesi', () {
    Future<List<Object?>> ac(
      WidgetTester t,
      AlarmAdayi aday, {
      bool gorunur = false,
      bool kilitli = false,
      void Function(BuildContext)? onKilitli,
    }) async {
      t.view.physicalSize = const Size(375 * 3, 900 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);
      final sonuclar = <Object?>[];
      await t.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: ThemeData(
              brightness: Brightness.dark,
              extensions: const [SandikPalette.dark]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('tr'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => sonuclar.add(
                    await showModalBottomSheet<Object>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => AlarmKurSheet(
                              adaylar: [aday],
                              sabit: true,
                              gostergeGorunur: gorunur,
                              gostergeKilitli: kilitli,
                              onGostergeKilitli: onKilitli,
                            ))),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
      return sonuclar;
    }

    const thy = AlarmAdayi('THYAO.IS', 'THY', 300);

    testWidgets('varsayılan (Premium görünmüyor): sekme yok', (t) async {
      await ac(t, thy);
      expect(find.text('Gösterge'), findsNothing);
      expect(find.byType(SandikSegment), findsNothing,
          reason: 'hissede yüzde kipi de yok; bugünkü sayfa birebir');
    });

    testWidgets('altında Premium görünse de sekme yok (kapsam dışı)',
        (t) async {
      await ac(t, const AlarmAdayi('ALTIN_GRAM', 'Gram altın', 4200),
          gorunur: true);
      expect(find.text('Günlük yüzde'), findsOneWidget);
      expect(find.text('Gösterge'), findsNothing);
    });

    testWidgets('kilitli: dokunmak paywall\'ı açar, kip değişmez', (t) async {
      var acildi = 0;
      await ac(t, thy, gorunur: true, kilitli: true, onKilitli: (_) => acildi++);
      expect(find.byType(SandikSegment), findsOneWidget);
      final kilit = t.widget<Icon>(find.byIcon(Icons.lock_outline_rounded));
      expect(kilit.semanticLabel, 'Premium gerekir',
          reason: 'kilit yalnız renkle değil, simge ve etiketle de okunur');
      await t.tap(find.text('Gösterge'));
      await t.pumpAndSettle();
      expect(acildi, 1);
      expect(find.byType(TextField), findsOneWidget, reason: 'Fiyat kipi kaldı');
    });

    testWidgets('açık: EMA200 + yukarı seçilir, kurulum döner', (t) async {
      final sonuclar = await ac(t, thy, gorunur: true);
      await t.tap(find.text('Gösterge'));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(
          find.text('THY fiyatı EMA50 çizgisini hangi yöne keserse haber '
              'vereceğiz.'),
          findsOneWidget,
          reason: 'varsayılan EMA50, iki yön');
      for (final g in GostergeKodu.values) {
        final cip = find.byKey(ValueKey('gostergeCipi_${g.kod}'));
        expect(t.getSize(cip).height, greaterThanOrEqualTo(SandikTouch.min),
            reason: g.kod);
      }
      await t.tap(find.byKey(const ValueKey('gostergeCipi_ema200')));
      await t.tap(find.text('Yukarı keserse'));
      await t.pump();
      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();
      final k = sonuclar.single as GostergeAlarmKurulumu;
      expect(k.gosterge, GostergeKodu.ema200);
      expect(k.yon, SeviyeYon.yukari);
      expect(k.aday.sembol, 'THYAO.IS');
    });
  });
}

/// Bellekte iki tablo; sunucunun benzersiz kimliği ve `created_at`'i taklit.
class _SahteDepo implements SeviyeAlarmiStore {
  final satirlar = <String, List<Map<String, dynamic>>>{};
  var _sira = 0;

  @override
  Future<List<Map<String, dynamic>>> select(String tablo, String userId) async =>
      [
        for (final r in satirlar[tablo] ?? const <Map<String, dynamic>>[])
          if (r['user_id'] == userId) Map.of(r),
      ];

  @override
  Future<Map<String, dynamic>> insert(
      String tablo, Map<String, dynamic> row) async {
    final r = {
      ...row,
      'id': 'id${++_sira}',
      'enabled': true,
      'triggered_at': null,
      'son_taraf': null,
      'created_at': '2026-10-29T09:00:00Z',
    };
    (satirlar[tablo] ??= []).add(r);
    return Map.of(r);
  }

  @override
  Future<Map<String, dynamic>> update(
      String tablo, String id, Map<String, dynamic> alanlar) async {
    final r = satirlar[tablo]!.firstWhere((x) => x['id'] == id);
    r.addAll(alanlar);
    return Map.of(r);
  }

  @override
  Future<void> delete(String tablo, String id) async =>
      satirlar[tablo]?.removeWhere((x) => x['id'] == id);
}
