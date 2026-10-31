import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/alarm_mesafesi.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/models/seviye_alarmi.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/yuzde_alarmi.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/providers/seviye_alarmi_provider.dart';
import 'package:portfoy_takip/providers/yuzde_alarmi_provider.dart';
import 'package:portfoy_takip/screens/price_alerts_screen.dart';
import 'package:portfoy_takip/services/bildirim_izni.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Alarmlarım "ne kadar kaldı" paketi (müşteri raporu 31 Eki 21:15, yasin
/// "yap"): satırda hedefe mesafe, varlığa göre gruplama, çöp kutusu yerine
/// kaydırarak sil + geri al, satıra dokununca düzenle, boş durumda öneri.

List<PriceAlert> _fiyat = const [];
List<YuzdeAlarmi> _yuzde = const [];
final _silinen = <String>[];
final _kurulan = <Object>[];
final _duzenlenen = <({String id, double hedef, String yon, bool tekrar})>[];

class _F extends PriceAlertsNotifier {
  @override
  Future<List<PriceAlert>> build() async => _fiyat;
  @override
  Future<void> delete(String id) async {
    _silinen.add(id);
    state = AsyncData([
      for (final a in state.valueOrNull ?? const <PriceAlert>[])
        if (a.id != id) a
    ]);
  }

  @override
  Future<PriceAlert> create(PriceAlert alarm) async {
    _kurulan.add(alarm);
    final yeni = PriceAlert(
      id: '${alarm.id}-geri',
      userId: alarm.userId,
      symbol: alarm.symbol,
      label: alarm.label,
      targetPrice: alarm.targetPrice,
      direction: alarm.direction,
      enabled: true,
      createdAt: DateTime(2026, 10, 31),
      tekrar: alarm.tekrar,
    );
    state = AsyncData([yeni, ...(state.valueOrNull ?? const [])]);
    return yeni;
  }

  @override
  Future<void> duzenle(String id,
      {required double hedef,
      required String yon,
      required bool tekrar}) async {
    _duzenlenen.add((id: id, hedef: hedef, yon: yon, tekrar: tekrar));
    state = AsyncData([
      for (final a in state.valueOrNull ?? const <PriceAlert>[])
        a.id == id
            ? a.copyWith(targetPrice: hedef, direction: yon, tekrar: tekrar)
            : a,
    ]);
  }
}

class _Y extends YuzdeAlarmlariNotifier {
  @override
  Future<List<YuzdeAlarmi>> build() async => _yuzde;
  @override
  Future<YuzdeAlarmi> create(YuzdeAlarmi alarm) async {
    _kurulan.add(alarm);
    state = AsyncData([alarm, ...(state.valueOrNull ?? const [])]);
    return alarm;
  }

  @override
  Future<void> delete(String id) async {
    _silinen.add(id);
    state = AsyncData([
      for (final a in state.valueOrNull ?? const <YuzdeAlarmi>[])
        if (a.id != id) a
    ]);
  }
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

class _Portfoy extends PortfolioNotifier {
  _Portfoy(this._assets);
  final List<Asset> _assets;
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: _assets,
      ownerId: 'u1',
      usdTry: 42.0,
      eurTry: 46.0,
      gbpTry: 54.0);
}

Asset _altin(double fiyat) => Asset(
      id: 'g1',
      userId: 'u1',
      name: 'Gram altın',
      ticker: 'GA',
      subCategory: 'ALTIN_GRAM',
      type: AssetType.altin,
      quantity: 10,
      purchasePrice: 3000,
      currentPrice: fiyat,
      currency: 'TRY',
      notes: '',
      addedDate: DateTime(2026, 9, 1),
    );

PriceAlert _f(String id, double hedef,
        {String yon = 'above', DateTime? tetik, bool tekrar = false}) =>
    PriceAlert(
      id: id,
      userId: 'u1',
      symbol: 'ALTIN_GRAM',
      label: 'Gram altın',
      targetPrice: hedef,
      direction: yon,
      enabled: true,
      triggeredAt: tetik,
      createdAt: DateTime(2026, 10, 1),
      tekrar: tekrar,
    );

YuzdeAlarmi _y(String id) => YuzdeAlarmi(
      id: id,
      userId: 'u1',
      symbol: 'ALTIN_GRAM',
      label: 'Gram altın',
      esikPct: 2,
      yon: YuzdeYon.ikisi,
      createdAt: DateTime(2026, 10, 2),
    );

Future<void> _pump(WidgetTester tester, {List<Asset> varliklar = const []}) async {
  tester.view.physicalSize = const Size(375 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      priceAlertsProvider.overrideWith(_F.new),
      yuzdeAlarmlariProvider.overrideWith(_Y.new),
      gostergeAlarmlariProvider.overrideWith(_G.new),
      cizimAlarmlariProvider.overrideWith(_C.new),
      authProvider.overrideWith(_Auth.new),
      portfolioProvider.overrideWith(() => _Portfoy(varliklar)),
    ],
    child: MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const PriceAlertsScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RemoteConfigService.testAcik = {};
    BildirimIzni.testOkuyucu = () async => false;
    _fiyat = const [];
    _yuzde = const [];
    _silinen.clear();
    _kurulan.clear();
    _duzenlenen.clear();
  });
  tearDown(() {
    RemoteConfigService.testAcik = {};
    BildirimIzni.testOkuyucu = null;
  });

  group('alarmMesafesi', () {
    test('yukarı alarm: hedefe kalan yüzde, aşılınca yok', () {
      expect(alarmMesafesi(fiyat: 100, hedef: 103.2, yukari: true),
          closeTo(3.2, 1e-9));
      expect(alarmMesafesi(fiyat: 104, hedef: 103.2, yukari: true), isNull);
    });
    test('aşağı alarm: işaretsiz mesafe, aşılınca yok', () {
      expect(alarmMesafesi(fiyat: 100, hedef: 95, yukari: false),
          closeTo(5, 1e-9));
      expect(alarmMesafesi(fiyat: 94, hedef: 95, yukari: false), isNull);
    });
    test('iki yönlü çizgi: mutlak uzaklık', () {
      expect(alarmMesafesi(fiyat: 100, hedef: 98, yukari: null),
          closeTo(2, 1e-9));
    });
    test('fiyat bilinmiyorsa uydurma sayı yok', () {
      expect(alarmMesafesi(fiyat: 0, hedef: 95, yukari: false), isNull);
      expect(alarmMesafesi(fiyat: double.nan, hedef: 95, yukari: true), isNull);
    });
    test('%1 altında iki hane', () {
      expect(alarmMesafesiHanesi(0.45), 2);
      expect(alarmMesafesiHanesi(3.2), 1);
    });
  });

  testWidgets('aynı varlığın alarmları tek başlıkta; fiyat ve mesafe yazar',
      (tester) async {
    _fiyat = [_f('a', 5160), _f('b', 4900, yon: 'below')];
    _yuzde = [_y('y')];
    await _pump(tester, varliklar: [_altin(5000)]);
    expect(find.byKey(const ValueKey('grup_ALTIN_GRAM')), findsOneWidget);
    expect(find.text('Gram altın'), findsOneWidget,
        reason: 'Varlık adı bir kez, başlıkta.');
    expect(find.textContaining('şimdi'), findsOneWidget);
    expect(find.text('%3,2 kaldı'), findsOneWidget);
    expect(find.text('%2,0 kaldı'), findsOneWidget);
    // Çöp kutusu satırda yok; ▲▼ metin karakteri yok.
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    expect(find.text('▲'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fiyat bilinmiyorsa mesafe yazılmaz', (tester) async {
    _fiyat = [_f('a', 5160)];
    await _pump(tester);
    expect(find.byKey(const ValueKey('alarmMesafe')), findsNothing);
    expect(find.textContaining('şimdi'), findsNothing);
  });

  testWidgets('kaydırarak sil: hemen silinir, Geri al yeniden kurar',
      (tester) async {
    _fiyat = [_f('a', 5160)];
    await _pump(tester, varliklar: [_altin(5000)]);
    await tester.drag(find.byKey(const ValueKey('kaydir_a')),
        const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(_silinen, ['a']);
    expect(find.byKey(const ValueKey('a')), findsNothing);
    expect(find.text('Alarm silindi'), findsOneWidget);
    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(_kurulan.single, isA<PriceAlert>());
    expect((_kurulan.single as PriceAlert).targetPrice, 5160);
    expect(find.text('%3,2 kaldı'), findsOneWidget);
  });

  testWidgets('çalmış alarmda geri al yok', (tester) async {
    _fiyat = [_f('a', 5160), _f('b', 4100, tetik: DateTime(2026, 10, 20))];
    await _pump(tester, varliklar: [_altin(5000)]);
    await tester.tap(find.byKey(const ValueKey('calanlarBasligi')));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const ValueKey('kaydir_b')),
        const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(_silinen, ['b']);
    expect(find.text('Alarm silindi'), findsOneWidget);
    expect(find.text('Geri al'), findsNothing);
  });

  testWidgets('satıra dokununca düzenlenir; aynı satır güncellenir',
      (tester) async {
    _fiyat = [_f('a', 5160)];
    await _pump(tester, varliklar: [_altin(5000)]);
    await tester.tap(find.text('Üstüne çıkınca · ₺5.160,00'));
    await tester.pumpAndSettle();
    expect(find.text('Alarmı düzenle'), findsOneWidget);
    expect(find.byKey(const ValueKey('alarmiSil')), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '5.300');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(_duzenlenen.single.id, 'a');
    expect(_duzenlenen.single.hedef, 5300);
    expect(_duzenlenen.single.yon, 'above');
    expect(_kurulan, isEmpty, reason: 'Yeni alarm kurulmaz.');
    expect(find.text('Alarm güncellendi'), findsOneWidget);
  });

  testWidgets('düzenleme sayfasından sil: satır gider, geri al sunulur',
      (tester) async {
    _fiyat = [_f('a', 5160)];
    await _pump(tester, varliklar: [_altin(5000)]);
    await tester.tap(find.text('Üstüne çıkınca · ₺5.160,00'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('alarmiSil')));
    await tester.pumpAndSettle();
    expect(_silinen, ['a']);
    expect(find.text('Geri al'), findsOneWidget);
  });

  testWidgets('boş durum: kapsamdaki varlığa tek dokunuş öneri', (tester) async {
    await _pump(tester, varliklar: [_altin(5000)]);
    expect(find.byKey(const ValueKey('oneri_ALTIN_GRAM')), findsOneWidget);
    await tester.tap(find.text('Kur'));
    await tester.pumpAndSettle();
    expect(_kurulan.single, isA<YuzdeAlarmi>());
    expect(find.byKey(const ValueKey('oneri_ALTIN_GRAM')), findsNothing);
  });

  testWidgets('2× yazı: grup ve satır taşmaz', (tester) async {
    _fiyat = [_f('a', 5160, tekrar: true), _f('b', 4900, yon: 'below')];
    _yuzde = [_y('y')];
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester, varliklar: [_altin(5000)]);
    expect(tester.takeException(), isNull);
  });

  test('satırda çöp kutusu düğmesi kalmadı (kaynak)', () {
    final k = ekranKaynagiSync('lib/screens/price_alerts_screen.dart');
    expect(RegExp(r'IconButton\([^)]*delete_outline').hasMatch(k), isFalse);
    expect(k, isNot(contains("'▲'")));
  });
}
