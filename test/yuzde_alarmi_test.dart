import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/yuzde_alarmi.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/yuzde_alarmi_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart';
import 'package:portfoy_takip/widgets/sandik_segment.dart';

import 'helpers/kaynak.dart';

/// Günlük yüzde alarmı (0169, Ar-Ge 2026-10-27 §1): "Gram altın bugün %2
/// düşerse haber ver".
class _SahteKapi implements YuzdeAlarmiStore {
  final eklenen = <Map<String, dynamic>>[];
  final silinen = <String>[];

  @override
  Future<List<Map<String, dynamic>>> select(String userId) async => [
        {
          'id': 'y1',
          'user_id': userId,
          'symbol': 'ALTIN_GRAM',
          'label': 'Gram altın',
          'esik_pct': '2.00', // PostgREST numeric'i metin döndürebilir
          'yon': 'dusus',
          'enabled': true,
          'son_tetik_gunu': '2026-10-27',
          'son_tetik_pct': -2.13,
          'son_tetik_fiyat': 4212.37,
          'created_at': '2026-10-27T06:00:00Z',
        },
      ];

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> row) async {
    eklenen.add(row);
    return {...row, 'id': 'yeni', 'created_at': '2026-10-27T07:00:00Z'};
  }

  @override
  Future<void> delete(String id) async => silinen.add(id);
}

void main() {
  group('kapsam (fiyat_kaynagi sözleşmesi: widget kapsamından türer)', () {
    test('altın, TL döviz, kripto evet', () {
      for (final s in ['ALTIN_GRAM', 'ALTIN_CEYREK', 'USDTRY=X', 'KRIPTO:BTC']) {
        expect(FiyatKaynagi.yuzdeAlarmiKapsamindaMi(s), isTrue, reason: s);
      }
    });
    test('fon, BIST, endeks, emtia hayır (uydurma yok)', () {
      for (final s in ['TEFAS:AFT', 'THYAO.IS', 'XU100.IS', 'GC=F', '']) {
        expect(FiyatKaynagi.yuzdeAlarmiKapsamindaMi(s), isFalse, reason: s);
      }
    });
    test('yeni sembol listesi yok: widget kapsamının alt kümesi', () {
      final k = ekranKaynagiSync('lib/services/fiyat_kaynagi.dart');
      final i = k.indexOf('static bool yuzdeAlarmiKapsamindaMi');
      expect(i, greaterThan(0));
      expect(k.substring(i, k.indexOf(';', i)),
          contains('widgetSunucuKapsamindaMi(sembol)'));
    });
    test('çalmış fiyat alarmını yeniden kurarken kip sunulmaz', () {
      const altin = AlarmAdayi('ALTIN_GRAM', 'Gram altın', 4200);
      expect(yuzdeKipiSunulur(altin), isTrue);
      expect(yuzdeKipiSunulur(altin, baslangicHedef: 4300), isFalse);
      expect(yuzdeKipiSunulur(const AlarmAdayi('TEFAS:AFT', 'AFT', 1)),
          isFalse);
    });
  });

  group('model', () {
    test('satır ↔ model; numeric metin olarak da okunur', () async {
      final svc = YuzdeAlarmiService(_SahteKapi());
      final a = (await svc.fetchAll('u1')).single;
      expect(a.esikPct, 2);
      expect(a.yon, YuzdeYon.dusus);
      expect(a.sonTetikGunu, '2026-10-27');
      expect(a.isActive, isTrue);
    });

    test('insert yalnız kullanıcının seçtiklerini yazar', () async {
      final kapi = _SahteKapi();
      final svc = YuzdeAlarmiService(kapi);
      final y = await svc.create(YuzdeAlarmi(
        id: '',
        userId: 'u1',
        symbol: 'KRIPTO:BTC',
        label: 'Bitcoin',
        esikPct: 3,
        yon: YuzdeYon.ikisi,
        createdAt: DateTime(2026),
      ));
      expect(kapi.eklenen.single, {
        'user_id': 'u1',
        'symbol': 'KRIPTO:BTC',
        'label': 'Bitcoin',
        'esik_pct': 3.0,
        'yon': 'ikisi',
      });
      expect(y.id, 'yeni');
      await svc.delete('yeni');
      expect(kapi.silinen, ['yeni']);
    });

    test('bilinmeyen yön kodu ikisine düşer', () {
      expect(YuzdeYon.koddan('below'), YuzdeYon.ikisi);
      expect(YuzdeYon.koddan('yukselis'), YuzdeYon.yukselis);
    });

    test('gün TR takvimiyle (UTC+3): sunucunun istanbulGunu ile aynı', () {
      // TR 23:59 → aynı gün; TR 00:01 → ertesi gün.
      expect(yuzdeAlarmGunu(DateTime.utc(2026, 10, 27, 20, 59)), '2026-10-27');
      expect(yuzdeAlarmGunu(DateTime.utc(2026, 10, 27, 21, 1)), '2026-10-28');
      final a = YuzdeAlarmi(
        id: 'y',
        userId: 'u',
        symbol: 'ALTIN_GRAM',
        label: 'Gram altın',
        esikPct: 2,
        yon: YuzdeYon.dusus,
        createdAt: DateTime(2026),
        sonTetikGunu: '2026-10-27',
      );
      expect(a.bugunCaldi(DateTime.utc(2026, 10, 27, 12)), isTrue);
      expect(a.bugunCaldi(DateTime.utc(2026, 10, 27, 21, 1)), isFalse,
          reason: 'ertesi gün kendiliğinden yeniden nöbette');
    });

    test('etiket yönü metinde de söyler', () {
      final l = AppLocalizationsTr();
      expect(yuzdeAlarmEtiketi(l, 2, YuzdeYon.dusus), 'Günlük %2 düşüş');
      expect(yuzdeAlarmEtiketi(l, 3, YuzdeYon.yukselis), 'Günlük %3 yükseliş');
      expect(yuzdeAlarmEtiketi(l, 1.5, YuzdeYon.ikisi), 'Günlük %1,5 hareket');
    });
  });

  group('sheet', () {
    Future<List<Object?>> kur(WidgetTester t, AlarmAdayi aday,
        {double olcek = 1}) async {
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
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: TextScaler.linear(olcek)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => sonuclar.add(
                    await showModalBottomSheet<Object>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) =>
                            AlarmKurSheet(adaylar: [aday], sabit: true))),
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

    testWidgets('fonda yüzde kipi görünmez (sunucu ölçmüyor)', (t) async {
      await kur(t, const AlarmAdayi('TEFAS:AFT', 'AFT', 1.23));
      expect(find.byType(SandikSegment), findsNothing);
      expect(find.text('Günlük yüzde'), findsNothing);
      expect(find.byType(TextField), findsOneWidget, reason: 'Fiyat kipi');
    });

    testWidgets('hissede de görünmez', (t) async {
      await kur(t, const AlarmAdayi('THYAO.IS', 'THY', 300));
      expect(find.text('Günlük yüzde'), findsNothing);
    });

    testWidgets('altında varsayılan Fiyat; Günlük yüzde ±%2 düşüş kurar',
        (t) async {
      final sonuclar =
          await kur(t, const AlarmAdayi('ALTIN_GRAM', 'Gram altın', 4200));
      expect(find.byType(SandikSegment), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget,
          reason: 'varsayılan bugünkü davranış');

      await t.tap(find.text('Günlük yüzde'));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('±%1'), findsOneWidget);
      expect(find.text('±%3'), findsOneWidget);
      expect(find.text('Düşerse'), findsOneWidget);
      // Varsayılan yön "İkisi de" (müşteri raporu 27 Eki 09:15).
      expect(
          find.text('Gram altın bugün %2 düşer ya da yükselirse '
              'haber vereceğiz.'),
          findsOneWidget);

      await t.tap(find.text('±%3'));
      await t.tap(find.text('Düşerse'));
      await t.pump();
      expect(
          find.text('Gram altın bugün %3 düşerse haber vereceğiz.'),
          findsOneWidget);

      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();
      final k = sonuclar.single as YuzdeAlarmKurulumu;
      expect(k.esik, 3);
      expect(k.yon, YuzdeYon.dusus);
      expect(k.aday.sembol, 'ALTIN_GRAM');
    });

    testWidgets('çipler ≥44pt, ekran okuyucu eşiği sözle okur', (t) async {
      final h = t.ensureSemantics();
      await kur(t, const AlarmAdayi('KRIPTO:BTC', 'Bitcoin', 3456789));
      await t.tap(find.text('Günlük yüzde'));
      await t.pumpAndSettle();
      for (final m in ['±%1', '±%2', '±%3', 'Düşerse', 'Yükselirse']) {
        final cip = find.ancestor(
            of: find.text(m), matching: find.byType(SandikTappable));
        expect(t.getSize(cip).height, greaterThanOrEqualTo(SandikTouch.min),
            reason: m);
      }
      expect(find.bySemanticsLabel('Günlük yüzde 2 eşiği'), findsOneWidget);
      h.dispose();
    });

    for (final olcek in [2.0, 3.1]) {
      testWidgets('×$olcek yazıda yüzde kipi taşmaz', (t) async {
        await kur(t, const AlarmAdayi('ALTIN_GRAM', 'Gram altın', 4200),
            olcek: olcek);
        await t.tap(find.text('Günlük yüzde'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  test('liste ve sınır yüzde alarmlarını da görür', () {
    final ekran = ekranKaynagiSync('lib/screens/price_alerts_screen.dart');
    expect(ekran, contains('yuzdeAlarmlariProvider'));
    final sheet = ekranKaynagiSync('lib/widgets/alarm_kur_sheet.dart');
    final i = sheet.indexOf('int etkinAlarmSayisi(');
    expect(sheet.substring(i, sheet.indexOf('\n}', i)),
        contains('yuzdeAlarmlariProvider'),
        reason: 'ücretsiz tavan (20) iki türün toplamı');
  });
}
