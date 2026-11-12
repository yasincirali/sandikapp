import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/models/seviye_alarmi.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/yuzde_alarmi.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show priceAlertLimitProvider;
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/providers/seviye_alarmi_provider.dart';
import 'package:portfoy_takip/providers/yuzde_alarmi_provider.dart';
import 'package:portfoy_takip/screens/price_alerts_screen.dart';
import 'package:portfoy_takip/services/alarm_siniri.dart';
import 'package:portfoy_takip/services/bildirim_izni.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart';
import 'package:portfoy_takip/widgets/tek_dokunus_alarm.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Ücretsiz alarm tavanı her giriş yolunda tutar (yasin 2026-11-12:
/// "alarm ekleme kısmında sonsuz alarma gidebilecek bir bug var").
///
/// Üç delik vardı: (1) sayım yüklenmemiş listeyi 0 sayıyordu — yüzde/
/// gösterge/çizim listeleri yalnız Alarmlar ekranında izlendiğinden varlık
/// sayfasından ilk girişte tavan atlanıyordu; (2) kontrol yalnız sayfa
/// açılırken bir kez yapılıyordu; (3) Alarmlarım'daki "Geri al" tavana hiç
/// bakmıyordu (sil → kur → geri al döngüsü sınırsız). Sunucu (0181) son
/// bekçi; reddi ham hata değil ortak sınır uyarısı olarak görünür.

List<PriceAlert> _fiyat = const [];
List<YuzdeAlarmi> _yuzde = const [];
Completer<List<YuzdeAlarmi>>? _yuzdeGecikmeli;
Object? _yuzdeYazmaHatasi;
Object? _fiyatYazmaHatasi;
final _yazilan = <Object>[];

class _F extends PriceAlertsNotifier {
  @override
  Future<List<PriceAlert>> build() async => _fiyat;
  @override
  Future<PriceAlert> create(PriceAlert alarm) async {
    final h = _fiyatYazmaHatasi;
    if (h != null) throw h;
    _yazilan.add(alarm);
    state = AsyncData([alarm, ...(state.valueOrNull ?? const [])]);
    return alarm;
  }

  @override
  Future<void> delete(String id) async {
    state = AsyncData([
      for (final a in state.valueOrNull ?? const <PriceAlert>[])
        if (a.id != id) a,
    ]);
  }
}

class _Y extends YuzdeAlarmlariNotifier {
  @override
  Future<List<YuzdeAlarmi>> build() =>
      _yuzdeGecikmeli?.future ?? Future.value(_yuzde);
  @override
  Future<YuzdeAlarmi> create(YuzdeAlarmi alarm) async {
    final h = _yuzdeYazmaHatasi;
    if (h != null) throw h;
    _yazilan.add(alarm);
    state = AsyncData([alarm, ...(state.valueOrNull ?? const [])]);
    return alarm;
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

PriceAlert _f(String id) => PriceAlert(
      id: id,
      userId: 'u1',
      symbol: 'ALTIN_GRAM',
      label: 'Gram altın',
      targetPrice: 4000,
      direction: 'above',
      enabled: true,
      createdAt: DateTime(2026, 10, 1),
    );

YuzdeAlarmi _y(String id) => YuzdeAlarmi(
      id: id,
      userId: 'u1',
      symbol: 'USDTRY=X',
      label: 'Dolar',
      esikPct: 2,
      yon: YuzdeYon.ikisi,
      createdAt: DateTime(2026, 10, 1),
    );

List<Override> _overrides(int limit, {bool oturum = true}) => [
      priceAlertsProvider.overrideWith(_F.new),
      yuzdeAlarmlariProvider.overrideWith(_Y.new),
      gostergeAlarmlariProvider.overrideWith(_G.new),
      cizimAlarmlariProvider.overrideWith(_C.new),
      if (oturum) authProvider.overrideWith(_Auth.new),
      priceAlertLimitProvider.overrideWithValue(limit),
    ];

/// Hiçbir alarm listesini İZLEMEYEN bir yüzey (varlık sayfası gibi):
/// sayım listeleri kendisi uyandırmak zorunda.
Future<WidgetRef> _bosYuzey(WidgetTester tester, {int limit = 20}) async {
  late WidgetRef r;
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(limit),
    child: MaterialApp(
      theme: ThemeData(extensions: const [SandikPalette.dark]),
      home: Scaffold(
        body: Consumer(builder: (_, ref, __) {
          r = ref;
          ref.watch(authProvider); // oturum; alarm listeleri izlenmez
          return const SizedBox.expand(key: ValueKey('yuzey'));
        }),
      ),
    ),
  ));
  return r;
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _fiyat = const [];
    _yuzde = const [];
    _yuzdeGecikmeli = null;
    _yuzdeYazmaHatasi = null;
    _fiyatYazmaHatasi = null;
    _yazilan.clear();
    BildirimIzni.testOkuyucu = () async => false;
  });
  tearDown(() => BildirimIzni.testOkuyucu = null);

  testWidgets('yüklenmemiş liste 0 sayılmaz: sayım gelmesini bekler',
      (tester) async {
    _fiyat = [for (var i = 0; i < 10; i++) _f('f$i')];
    _yuzdeGecikmeli = Completer();
    final r = await _bosYuzey(tester);
    // Eski hata: o anki değer okunurdu; yüzde listesi yüklenmemişken
    // 10 + 0 = 10 < 20 → tavan atlanırdı.
    expect(bilinenEtkinAlarmSayisi(r), 0);
    final karar = alarmSiniriDoluMu(r);
    _yuzdeGecikmeli!.complete([for (var i = 0; i < 10; i++) _y('y$i')]);
    await tester.pump();
    expect(await karar, isTrue);
  });

  testWidgets('sınırsız planda listeler hiç beklenmez', (tester) async {
    _yuzdeGecikmeli = Completer(); // hiç tamamlanmaz
    final r = await _bosYuzey(tester, limit: 1 << 30);
    expect(await alarmSiniriDoluMu(r), isFalse);
  });

  testWidgets('yazmadan hemen önce yeniden sayar: dolduysa yazma koşmaz',
      (tester) async {
    _fiyat = [for (var i = 0; i < 19; i++) _f('f$i')];
    final r = await _bosYuzey(tester);
    expect(await alarmSiniriDoluMu(r), isFalse, reason: 'açılışta 19/20');
    // Sayfa açıkken başka yüzeyden 20. alarm kuruldu.
    await r.read(priceAlertsProvider.notifier).create(_f('baska'));
    _yazilan.clear();
    var yazildi = false;
    await expectLater(
        alarmYazimiTavanli(r, () async => yazildi = true),
        throwsA(isA<AlarmSiniriDolu>()));
    expect(yazildi, isFalse);
  });

  test('sunucunun tavan reddi tanınır, başka hata tanınmaz', () {
    expect(
        alarmSiniriHatasiMi(const PostgrestException(
            message: 'alarm_siniri: ucretsiz tavan 20', code: '54000')),
        isTrue);
    expect(alarmSiniriHatasiMi(const AlarmSiniriDolu()), isTrue);
    expect(
        alarmSiniriHatasiMi(
            const PostgrestException(message: 'cihaz_siniri', code: '54000')),
        isFalse);
    expect(alarmSiniriHatasiMi(Exception('x')), isFalse);
  });

  testWidgets('sunucu reddi ortak sınır uyarısı olur, ham hata görünmez',
      (tester) async {
    _yuzdeYazmaHatasi = const PostgrestException(
        message: 'alarm_siniri: ucretsiz tavan 20', code: '54000');
    final r = await _bosYuzey(tester);
    await tester.pump();
    final ctx = tester.element(find.byKey(const ValueKey('yuzey')));
    await tekDokunusYuzdeAlarmiKur(
        ctx, r, const AlarmAdayi('ALTIN_GRAM', 'Gram altın', 4200));
    await tester.pump();
    expect(find.textContaining('20 aktif alarm'), findsOneWidget);
    expect(find.textContaining('alarm_siniri'), findsNothing);
    expect(find.textContaining('54000'), findsNothing);
  });

  testWidgets('kurma sayfası: sunucu tavan reddinde sayfa kapanır, '
      'alanın altına hata değil ortak uyarı', (tester) async {
    _fiyatYazmaHatasi = const PostgrestException(
        message: 'alarm_siniri: ucretsiz tavan 20', code: '54000');
    final r = await _bosYuzey(tester);
    await tester.pump();
    final ctx = tester.element(find.byKey(const ValueKey('yuzey')));
    final akis = alarmKurAkisi(ctx, r,
        sabit: const AlarmAdayi('ALTIN_GRAM', 'Gram altın', 4200));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '5000');
    await tester.pump();
    await tester.tap(find.text('Alarmı kur').last);
    await tester.pumpAndSettle();
    expect(await akis, isNull);
    expect(find.byType(AlarmKurSheet), findsNothing);
    expect(find.textContaining('20 aktif alarm'), findsOneWidget);
    expect(find.textContaining('kurulamadı'), findsNothing);
    expect(find.textContaining('alarm_siniri'), findsNothing);
  });

  testWidgets('tek dokunuş: yüklenmemiş yüzde listesiyle tavan doluysa '
      'sessizce kurmaz', (tester) async {
    _fiyat = [for (var i = 0; i < 12; i++) _f('f$i')];
    _yuzdeGecikmeli = Completer();
    final r = await _bosYuzey(tester);
    await tester.pump();
    final ctx = tester.element(find.byKey(const ValueKey('yuzey')));
    final is_ = tekDokunusYuzdeAlarmiKur(
        ctx, r, const AlarmAdayi('ALTIN_GRAM', 'Gram altın', 4200));
    _yuzdeGecikmeli!.complete([for (var i = 0; i < 8; i++) _y('y$i')]);
    await tester.pumpAndSettle();
    await is_;
    await tester.pumpAndSettle();
    expect(_yazilan, isEmpty);
    expect(find.textContaining('20 aktif alarm'), findsOneWidget);
  });

  testWidgets('Alarmlarım "Geri al" tavana uyar', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    _fiyat = [for (var i = 0; i < 20; i++) _f('f$i')];
    await tester.pumpWidget(ProviderScope(
      // Oturumsuz: ekranın portföy/takip okumaları sahte sunucuya gitmesin.
      overrides: _overrides(20, oturum: false),
      child: MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: const PriceAlertsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const ValueKey('kaydir_f0')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Alarm silindi'), findsOneWidget);

    // Silinen yerin dolduğu an: başka bir alarm kuruldu (19 → 20).
    final kap = ProviderScope.containerOf(
        tester.element(find.byType(PriceAlertsScreen)));
    await kap.read(priceAlertsProvider.notifier).create(_f('yeni'));
    _yazilan.clear();

    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(_yazilan, isEmpty, reason: '21. aktif alarm yazılmamalı');
    expect(find.textContaining('20 aktif alarm'), findsOneWidget);
  });
}
