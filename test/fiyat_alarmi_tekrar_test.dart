import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/models/seviye_alarmi.dart';
import 'package:portfoy_takip/models/yuzde_alarmi.dart';
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/providers/seviye_alarmi_provider.dart';
import 'package:portfoy_takip/providers/yuzde_alarmi_provider.dart';
import 'package:portfoy_takip/screens/price_alerts_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fiyat alarmı "Her geçişte haber ver" (0171, Ar-Ge 29 Eki 20:45 #1).
///
/// Kilitler: kolon yokken tek atış okunur (eski şema), tekrarlı alarm
/// çalmış olsa da BEKLEYENDİR (sayımlar + Alarmlarım grubu), anahtar
/// varsayılan kapalı ve kurulumla sunucuya gider.

PriceAlert _f(String id,
        {DateTime? tetik, bool tekrar = false, DateTime? sonTetik}) =>
    PriceAlert(
      id: id,
      userId: 'u1',
      symbol: 'USDTRY=X',
      label: 'Dolar',
      targetPrice: 42,
      direction: 'above',
      enabled: true,
      triggeredAt: tetik,
      createdAt: DateTime(2026, 10, 1),
      tekrar: tekrar,
      sonTetikAt: sonTetik,
    );

List<PriceAlert> _fiyat = const [];

class _F extends PriceAlertsNotifier {
  @override
  Future<List<PriceAlert>> build() async => _fiyat;
}

class _Y extends YuzdeAlarmlariNotifier {
  @override
  Future<List<YuzdeAlarmi>> build() async => const [];
}

class _G extends GostergeAlarmlariNotifier {
  @override
  Future<List<GostergeAlarmi>> build() async => const [];
}

class _C extends CizimAlarmlariNotifier {
  @override
  Future<List<CizimAlarmi>> build() async => const [];
}

ThemeData get _tema => ThemeData(
      brightness: Brightness.dark,
      extensions: const [SandikPalette.dark],
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('model', () {
    final taban = <String, dynamic>{
      'id': 'a',
      'user_id': 'u1',
      'symbol': 'USDTRY=X',
      'label': 'Dolar',
      'target_price': 42,
      'direction': 'above',
      'enabled': true,
      'triggered_at': '2026-10-29T09:00:00Z',
      'created_at': '2026-10-01T00:00:00Z',
    };

    test('kolon yoksa (0171 öncesi şema) tek atış; çalmışsa sönmüş', () {
      final a = PriceAlert.fromMap(taban);
      expect(a.tekrar, isFalse);
      expect(a.sonTetikAt, isNull);
      expect(a.isActive, isFalse);
      expect(a.sondu, isTrue);
    });

    test('tekrarlı ve çalmış alarm etkin sayılır, sönmüş değildir', () {
      final a = PriceAlert.fromMap({
        ...taban,
        'tekrar': true,
        'son_tetik_at': '2026-10-29T09:00:00Z',
      });
      expect(a.tekrar, isTrue);
      expect(a.isActive, isTrue, reason: 'kendiliğinden nöbete döner');
      expect(a.sondu, isFalse);
      expect(a.sonCalis, DateTime.utc(2026, 10, 29, 9));
    });

    test('kapatılmış tekrarlı alarm etkin değildir', () {
      final a =
          PriceAlert.fromMap({...taban, 'tekrar': true, 'enabled': false});
      expect(a.isActive, isFalse);
    });

    test('nöbete dönmüş tekrarlı alarm: damga yok, son çalış kalır', () {
      final a = PriceAlert.fromMap({
        ...taban,
        'triggered_at': null,
        'tekrar': true,
        'son_tetik_at': '2026-10-29T09:00:00Z',
      });
      expect(a.isActive, isTrue);
      expect(a.sonCalis, isNotNull);
    });

    test('insert: tek atışta `tekrar` yazılmaz (eski şemada da geçer)', () {
      expect(_f('a').toInsertMap().containsKey('tekrar'), isFalse);
      expect(_f('a', tekrar: true).toInsertMap()['tekrar'], isTrue);
    });

    test('copyWith tekrar ve son çalışı korur; damgasiz damgayı siler', () {
      final a = _f('a',
          tetik: DateTime(2026, 10, 29),
          tekrar: true,
          sonTetik: DateTime(2026));
      final b = a.copyWith(label: 'X', damgasiz: true);
      expect(b.tekrar, isTrue);
      expect(b.sonTetikAt, DateTime(2026));
      expect(b.triggeredAt, isNull);
      expect(b.label, 'X');
      expect(a.copyWith(targetPrice: 43).triggeredAt, a.triggeredAt);
    });

    test('çan özeti tekrarlı çalmış alarmı etkin sayar', () {
      final o = etkinAlarmOzeti([
        _f('a', tetik: DateTime(2026, 10, 29), tekrar: true),
        _f('b', tetik: DateTime(2026, 10, 29)),
      ]);
      expect(o?.enYakin.id, 'a');
      expect(o?.digerSayisi, 0);
    });
  });

  group('sheet', () {
    Future<List<AlarmKurulumu?>> ac(WidgetTester tester) async {
      final sonuclar = <AlarmKurulumu?>[];
      await tester.pumpWidget(MaterialApp(
        theme: _tema,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                sonuclar.add(await showModalBottomSheet<AlarmKurulumu>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const AlarmKurSheet(
                      adaylar: [AlarmAdayi('USDTRY=X', 'Dolar', 41.5)],
                      sabit: true),
                ));
              },
              child: const Text('aç'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      return sonuclar;
    }

    testWidgets('varsayılan kapalı: kurulum tek atış', (tester) async {
      final sonuclar = await ac(tester);
      expect(find.text('Her geçişte haber ver'), findsOneWidget);
      final anahtar = tester
          .widget<Switch>(find.byKey(const ValueKey('alarmTekrarAnahtari')));
      expect(anahtar.value, isFalse);
      await tester.enterText(find.byType(TextField), '42');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(sonuclar.single?.tekrar, isFalse);
    });

    testWidgets('satıra dokunmak açar; kurulum tekrarlı gider, ≥44 pt',
        (tester) async {
      final sonuclar = await ac(tester);
      final satir = find.byKey(const ValueKey('alarmTekrarSatiri'));
      expect(
          tester.getSize(satir).height, greaterThanOrEqualTo(SandikTouch.min));
      await tester.tap(find.text('Her geçişte haber ver'));
      await tester.pump();
      expect(
          tester
              .widget<Switch>(find.byKey(const ValueKey('alarmTekrarAnahtari')))
              .value,
          isTrue);
      await tester.enterText(find.byType(TextField), '42');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(sonuclar.single?.tekrar, isTrue);
      expect(sonuclar.single?.hedef, 42);
    });

    testWidgets('ekran okuyucu satırı tek öğe, durumuyla okur', (tester) async {
      final h = tester.ensureSemantics();
      await ac(tester);
      final satir = find.byKey(const ValueKey('alarmTekrarSatiri'));
      final d = tester.getSemantics(satir);
      expect(d.label, contains('Her geçişte haber ver'));
      expect(d.getSemanticsData().flagsCollection.isToggled, Tristate.isFalse);
      h.dispose();
    });
  });

  group('Alarmlarım', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(375 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          priceAlertsProvider.overrideWith(_F.new),
          yuzdeAlarmlariProvider.overrideWith(_Y.new),
          gostergeAlarmlariProvider.overrideWith(_G.new),
          cizimAlarmlariProvider.overrideWith(_C.new),
        ],
        child: MaterialApp(theme: _tema, home: const PriceAlertsScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('çalmış tekrarlı alarm Bekleyenler\'de; son çalış alt satırda',
        (tester) async {
      _fiyat = [
        _f('t',
            tetik: DateTime(2026, 10, 29, 12, 5),
            tekrar: true,
            sonTetik: DateTime(2026, 10, 29, 12, 5)),
        _f('s', tetik: DateTime(2026, 10, 20)),
      ];
      await pump(tester);
      // Çalanlar grubunda yalnız tek atış alarm var; grup kapalı.
      expect(find.text('Bekleyenler'), findsOneWidget);
      expect(find.byKey(const ValueKey('calanlarBasligi')), findsOneWidget);
      expect(find.textContaining('(1)'), findsOneWidget);
      expect(find.byKey(const ValueKey('t')), findsOneWidget);
      expect(find.textContaining('her geçişte'), findsOneWidget);
      expect(find.textContaining('Son çaldı: 29 Eki 2026 · 12:05'),
          findsOneWidget);
      // Tekrarlı alarm "yeniden kur" istemez.
      expect(find.text('Yeniden kur'), findsNothing);
    });

    testWidgets('hiç çalmamış tekrarlı alarm: son çalış satırı yok',
        (tester) async {
      _fiyat = [_f('t', tekrar: true)];
      await pump(tester);
      expect(find.textContaining('her geçişte'), findsOneWidget);
      expect(find.byKey(const ValueKey('alarmSonCaldi')), findsNothing);
      expect(find.byKey(const ValueKey('calanlarBasligi')), findsNothing);
    });
  });
}
