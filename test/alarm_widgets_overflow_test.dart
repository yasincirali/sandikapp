import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/services/price_alert_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart';
import 'package:portfoy_takip/widgets/alarm_seridi.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Alarm kurma sayfası ve varlık ekranındaki alarm şeridinin taşma
/// regresyonu (2026-09-14'te geldiler, taşma testi yoktu).
///
/// `price_alert_provider_test` davranışı doğruluyor; burası yalnızca
/// yerleşim: uzun varlık adı, çok sayıda alarm, dar ekran, büyük metin.
class _Kapi implements PriceAlertStore {
  _Kapi(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  Future<List<Map<String, dynamic>>> select(String userId) async => rows;
  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> row) async => row;
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> update(String id, Map<String, dynamic> patch) async {}
}

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 't@e.com',
        displayName: 'T',
        createdAt: DateTime(2026),
      );
}

List<Map<String, dynamic>> _alarmlar(int n) => [
      for (var i = 0; i < n; i++)
        {
          'id': 'a$i',
          'user_id': 'u1',
          'symbol': 'THYAO.IS',
          'label': 'Türk Hava Yolları Anonim Ortaklığı',
          'target_price': 250.0 + i * 12.345,
          'direction': i.isEven ? 'above' : 'below',
          'enabled': true,
          if (i % 3 == 2) 'triggered_at': '2026-09-01T00:00:00Z',
        },
    ];

Future<void> _pump(WidgetTester tester, Widget body,
    {double width = 375, List<Map<String, dynamic>> rows = const []}) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      priceAlertServiceProvider
          .overrideWithValue(PriceAlertService(_Kapi(rows))),
    ],
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: Scaffold(body: body),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AlarmSeridi', () {
    for (final w in <double>[320, 375, 430]) {
      testWidgets('${w.toInt()}pt — 7 alarm, uzun ad', (tester) async {
        await _pump(
          tester,
          const AlarmSeridi(
            sembol: 'THYAO.IS',
            ad: 'Türk Hava Yolları Anonim Ortaklığı',
            guncelFiyat: 312.4,
          ),
          width: w,
          rows: _alarmlar(7),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('alarm yok — boş durum taşmaz, 320pt', (tester) async {
      await _pump(
        tester,
        const AlarmSeridi(sembol: 'X', ad: 'X', guncelFiyat: 1),
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('AlarmKurSheet', () {
    final adaylar = [
      const AlarmAdayi('THYAO.IS', 'Türk Hava Yolları Anonim Ortaklığı', 312.4),
      const AlarmAdayi('TEFAS:YKT', 'Yapı Kredi Portföy Teknoloji Değişken Fon',
          0.9123),
      const AlarmAdayi('ALTIN_GRAM', 'Gram altın', 4890.0),
    ];

    for (final w in <double>[320, 375, 430]) {
      testWidgets('${w.toInt()}pt — seçicili', (tester) async {
        await _pump(tester, AlarmKurSheet(adaylar: adaylar), width: w);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('sabit aday, 320pt', (tester) async {
      await _pump(tester, AlarmKurSheet(adaylar: [adaylar.first], sabit: true),
          width: 320);
      expect(tester.takeException(), isNull);
    });

    testWidgets('büyük metin ölçeği (1.6×), 320pt', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          priceAlertServiceProvider
              .overrideWithValue(PriceAlertService(_Kapi(const []))),
        ],
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              extensions: const [SandikPalette.dark],
            ),
            home: Scaffold(body: AlarmKurSheet(adaylar: adaylar)),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  });
}
