import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart';

import 'helpers/kaynak.dart';

/// Alarmda "maliyetime göre" çipleri (2026-10-23, Ar-Ge): yüzde güncel
/// fiyattan değil kullanıcının kendi ortalama alış fiyatından.
class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
      id: 'u1', email: 't@e.com', displayName: 'T', createdAt: DateTime(2026));
}

Asset _lot(double adet, double alis,
        {AssetKind kind = AssetKind.buy, bool? bilinmiyor, String id = 'a'}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: adet,
      purchasePrice: alis,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 300,
      addedDate: DateTime(2026, 1, 1),
      kind: kind,
      maliyetBilinmiyor: bilinmiyor,
    );

void main() {
  group('alarmMaliyeti', () {
    test('iki alım lot\'unun miktar ağırlıklı ortalaması', () {
      final m = alarmMaliyeti([_lot(10, 200, id: 'a'), _lot(30, 240, id: 'b')]);
      expect(m, closeTo(230, 1e-9));
    });
    test('maliyeti bilinmeyen lot varsa uydurma yok', () {
      expect(
          alarmMaliyeti(
              [_lot(10, 200, id: 'a'), _lot(5, 300, bilinmiyor: true, id: 'b')]),
          isNull);
    });
    test('lot yoksa null', () {
      expect(alarmMaliyeti(const []), isNull);
    });
  });

  group('maliyetHedefleri', () {
    test('başa baş, +%20, −%10', () {
      final h = maliyetHedefleri(200, 300);
      expect(h.map((e) => e.yuzde), [0, 20, -10]);
      expect(h[1].hedef, closeTo(240, 1e-9));
      expect(h[2].hedef, closeTo(180, 1e-9));
    });
    test('güncele eşit düşen hedef elenir', () {
      // Güncel = maliyet: başa baş alarmı hemen çalışırdı.
      expect(maliyetHedefleri(300, 300).map((e) => e.yuzde), [20, -10]);
    });
  });

  Future<void> kur(WidgetTester t, AlarmAdayi aday, {double olcek = 1}) async {
    t.view.physicalSize = const Size(375 * 3, 900 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [authProvider.overrideWith(_FakeAuth.new)],
      child: MaterialApp(
        theme: ThemeData(
            brightness: Brightness.dark, extensions: const [SandikPalette.dark]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(olcek)),
          child: child!,
        ),
        home: Scaffold(body: AlarmKurSheet(adaylar: [aday], sabit: true)),
      ),
    ));
    await t.pump();
  }

  testWidgets('maliyet çipi hedefi doldurur', (t) async {
    await kur(t, const AlarmAdayi('THYAO.IS', 'THY', 300, maliyet: 200));
    expect(find.text('Maliyetim'), findsOneWidget);
    expect(find.text('Maliyet +%20'), findsOneWidget);
    await t.tap(find.text('Maliyetim'));
    await t.pump();
    expect(find.widgetWithText(TextField, '200,00'), findsOneWidget);
    await t.tap(find.text('Maliyet +%20'));
    await t.pump();
    expect(find.widgetWithText(TextField, '240,00'), findsOneWidget);
  });

  testWidgets('maliyetsiz aday (takip listesi) çip görmez', (t) async {
    await kur(t, const AlarmAdayi('THYAO.IS', 'THY', 300));
    expect(find.text('Maliyetim'), findsNothing);
    expect(find.textContaining('Maliyetine göre'), findsNothing);
  });

  for (final olcek in [2.0, 3.1]) {
    testWidgets('×$olcek yazıda taşma yok, çip ≥44pt', (t) async {
      await kur(t, const AlarmAdayi('THYAO.IS', 'THY', 300, maliyet: 200),
          olcek: olcek);
      expect(t.takeException(), isNull);
      final cip = find.ancestor(
          of: find.text('Maliyetim'), matching: find.byType(SandikTappable));
      expect(t.getSize(cip).height, greaterThanOrEqualTo(SandikTouch.min));
    });
  }

  test('varlık detayı ve alarm listesi maliyeti geçirir', () {
    for (final y in [
      'lib/screens/asset_detail_screen.dart',
      'lib/screens/price_alerts_screen.dart',
    ]) {
      expect(ekranKaynagiSync(y).contains('alarmMaliyeti('), isTrue, reason: y);
    }
  });
}
