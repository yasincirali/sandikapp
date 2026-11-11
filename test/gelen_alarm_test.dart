import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/gelen_alarm.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/models/seviye_alarmi.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/yuzde_alarmi.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/providers/seviye_alarmi_provider.dart';
import 'package:portfoy_takip/providers/yuzde_alarmi_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/alarm_caldi_bandi.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Alarmdan açılan varlık sayfasının "Alarmın çaldı" bandı (2026-11-11).

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

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 't@example.com',
        displayName: 'T',
        createdAt: DateTime(2026, 1, 1),
      );
}

PriceAlert _a({
  String id = 'a1',
  String yon = 'above',
  double hedef = 245,
  DateTime? tetik,
  DateTime? sonTetik,
  bool tekrar = false,
}) =>
    PriceAlert(
      id: id,
      userId: 'u1',
      symbol: 'THYAO.IS',
      label: 'THY',
      targetPrice: hedef,
      direction: yon,
      enabled: true,
      triggeredAt: tetik,
      sonTetikAt: sonTetik,
      tekrar: tekrar,
      createdAt: DateTime(2026, 11, 1),
    );

Widget _sahne(Widget child, {double olcek = 1}) => ProviderScope(
      overrides: [
        priceAlertsProvider.overrideWith(_F.new),
        yuzdeAlarmlariProvider.overrideWith(_Y.new),
        gostergeAlarmlariProvider.overrideWith(_G.new),
        cizimAlarmlariProvider.overrideWith(_C.new),
        authProvider.overrideWith(_Auth.new),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [SandikPalette.dark]),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(olcek)),
          child: Scaffold(
            body: SizedBox(width: 360, child: Column(children: [child])),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _fiyat = const [];
  });

  group('saf kararlar', () {
    test('kimlikle alarm bulunur; kimliksiz ya da listede yoksa null', () {
      final l = [_a(id: 'x'), _a(id: 'y')];
      expect(gelenAlarmiBul(l, 'y')?.id, 'y');
      expect(gelenAlarmiBul(l, 'z'), isNull);
      expect(gelenAlarmiBul(l, null), isNull);
      expect(gelenAlarmiBul(l, ''), isNull);
    });

    test('Yeniden kur hedefi: üstü güncel×1,05, altı ×0,95', () {
      expect(yenidenKurHedefi(_a(yon: 'above'), 200), closeTo(210, 1e-9));
      expect(yenidenKurHedefi(_a(yon: 'below'), 200), closeTo(190, 1e-9));
    });

    test('güncel fiyat bilinmiyorsa eski hedef (uydurma yok)', () {
      expect(yenidenKurHedefi(_a(hedef: 245), 0), 245);
      expect(yenidenKurHedefi(_a(yon: 'below', hedef: 245), -1), 245);
    });

    test('%5 öte hedef sayfanın türettiği yönle aynı yönü verir', () {
      for (final yon in ['above', 'below']) {
        final h = yenidenKurHedefi(_a(yon: yon), 300);
        expect(PriceAlert.suggestDirection(currentPrice: 300, targetPrice: h),
            yon);
      }
    });

    test('çalma anı: aynı gün saat, başka gün gün + saat, yoksa null', () {
      final simdi = DateTime(2026, 11, 11, 18);
      expect(
          alarmCalmaZamaniMetni(
              _a(tetik: DateTime(2026, 11, 11, 14, 32)), simdi),
          '14:32');
      expect(
          alarmCalmaZamaniMetni(_a(tetik: DateTime(2026, 11, 10, 9, 5)), simdi),
          '10 Kas · 09:05');
      // Tekrarlı alarm nöbete dönünce `triggered_at` silinir, son çalış kalır.
      expect(
          alarmCalmaZamaniMetni(
              _a(tekrar: true, sonTetik: DateTime(2026, 11, 11, 8, 1)), simdi),
          '08:01');
      expect(alarmCalmaZamaniMetni(_a(), simdi), isNull);
    });
  });

  group('bant', () {
    const aday = AlarmAdayi('THYAO.IS', 'THY', 300);

    testWidgets('alarm bulununca koşul, hedef ve eylemler görünür',
        (tester) async {
      final bugun = DateTime.now();
      _fiyat = [
        _a(tetik: DateTime(bugun.year, bugun.month, bugun.day, 14, 32))
      ];
      await tester
          .pumpWidget(_sahne(const AlarmCaldiBandi(alarmId: 'a1', aday: aday)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Alarmın çaldı:'), findsOneWidget);
      expect(find.textContaining('üstü · 14:32'), findsOneWidget);
      expect(find.text('Yeniden kur'), findsOneWidget);
      expect(find.byTooltip('Kapat'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    });

    testWidgets('alarm listede yoksa bant hiç çıkmaz', (tester) async {
      _fiyat = [_a(id: 'baska')];
      await tester
          .pumpWidget(_sahne(const AlarmCaldiBandi(alarmId: 'a1', aday: aday)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Alarmın çaldı'), findsNothing);
      expect(find.text('Yeniden kur'), findsNothing);
    });

    testWidgets('çalma anı bilinmiyorsa saat yazılmaz; altı alarmı "altı"',
        (tester) async {
      _fiyat = [_a(yon: 'below')];
      await tester
          .pumpWidget(_sahne(const AlarmCaldiBandi(alarmId: 'a1', aday: aday)));
      await tester.pumpAndSettle();
      final metin =
          tester.widget<Text>(find.textContaining('Alarmın çaldı')).data!;
      expect(metin, endsWith('altı'));
      expect(metin.contains('·'), isFalse);
    });

    testWidgets('Kapat bandı kaldırır', (tester) async {
      _fiyat = [_a(tetik: DateTime(2026, 11, 11, 14, 32))];
      await tester
          .pumpWidget(_sahne(const AlarmCaldiBandi(alarmId: 'a1', aday: aday)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Alarmın çaldı'), findsNothing);
    });

    testWidgets('Yeniden kur sayfayı güncelden %5 öte ön dolu açar',
        (tester) async {
      _fiyat = [_a(tetik: DateTime(2026, 11, 11, 14, 32))];
      await tester
          .pumpWidget(_sahne(const AlarmCaldiBandi(alarmId: 'a1', aday: aday)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yeniden kur'));
      await tester.pumpAndSettle();
      expect(find.byType(AlarmKurSheet), findsOneWidget);
      final alan = tester.widget<TextField>(find
          .descendant(
              of: find.byType(AlarmKurSheet), matching: find.byType(TextField))
          .first);
      // 300 × 1,05 = 315
      expect(alan.controller!.text, '315,00');
    });

    testWidgets('dokunma alanları ≥44 pt; yazı 2×\'te taşma yok',
        (tester) async {
      _fiyat = [_a(tetik: DateTime(2026, 11, 11, 14, 32))];
      await tester.pumpWidget(
          _sahne(const AlarmCaldiBandi(alarmId: 'a1', aday: aday), olcek: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final kur = tester.getSize(find.ancestor(
          of: find.text('Yeniden kur'), matching: find.byType(TextButton)));
      final kapat = tester.getSize(find.byTooltip('Kapat'));
      for (final s in [kur, kapat]) {
        expect(s.height, greaterThanOrEqualTo(44));
        expect(s.width, greaterThanOrEqualTo(44));
      }
    });
  });

  group('bağlantı', () {
    test('bildirim alarm kimliğini varlık ekranına taşır', () {
      final k = ekranKaynagiSync('lib/services/notification_service.dart');
      expect(k, contains('gelenAlarmId: alertId'));
      expect(
          k,
          contains(
              'openPriceAlertAsset(symbol, onNotFound: onNotFound, alertId: alertId)'));
      expect(k, contains('gelenAlarmId: gelenAlarmId,'));
    });

    test('varlık ekranı bandı yalnız gelenAlarmId ile kurar', () {
      final k = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
      expect(k, contains('final String? gelenAlarmId;'));
      expect(k, contains('final id = widget.gelenAlarmId;'));
      expect(
          k,
          contains(
              'if (id == null || id.isEmpty || _alarmSembolu == null) return null;'));
    });
  });
}
