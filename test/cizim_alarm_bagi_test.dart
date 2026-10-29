import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/grafik_cizimi.dart';
import 'package:portfoy_takip/models/seviye_alarmi.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show premiumKilitliProvider;
import 'package:portfoy_takip/providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/providers/seviye_alarmi_provider.dart';
import 'package:portfoy_takip/screens/price_alerts_screen.dart';
import 'package:portfoy_takip/services/price_alert_service.dart';
import 'package:portfoy_takip/services/seviye_alarmi_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/alarm_seridi.dart';
import 'package:portfoy_takip/widgets/tam_ekran/cizim_alarm_dugmesi.dart';
import 'package:portfoy_takip/widgets/tam_ekran/grafik_olcegi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Uçtan uca alarm testinde bulunanlar (2026-10-29):
///  1. "Tüm çizimleri sil" → "Geri al" çizimleri getiriyor, alarmı getirmiyordu.
///  2. Yatay çizgi alarmı çizgiye bağlı değildi (zil dolmuyor, ikinci dokunuş
///     ikinci alarm, çizgi silinince/taşınınca alarm yerinde).
///  3. Varlık şeridi gösterge/çizgi alarmlarını saymıyordu.
///  4. Alarmlar ekranı "Fiyat Alarmları" başlıklı, çizgi satırı seviyesizdi.

class _FiyatKapi implements PriceAlertStore {
  final rows = <Map<String, dynamic>>[];
  var _sira = 0;

  @override
  Future<List<Map<String, dynamic>>> select(String userId) async =>
      [for (final r in rows) if (r['user_id'] == userId) Map.of(r)];

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> row) async {
    final r = {
      ...row,
      'id': 'f${++_sira}',
      'enabled': true,
      'created_at': '2026-10-29T09:00:00Z',
    };
    rows.add(r);
    return Map.of(r);
  }

  @override
  Future<void> delete(String id) async => rows.removeWhere((r) => r['id'] == id);

  @override
  Future<void> update(String id, Map<String, dynamic> patch) async =>
      rows.firstWhere((r) => r['id'] == id).addAll(patch);
}

class _SeviyeDepo implements SeviyeAlarmiStore {
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
      'id': 's${++_sira}',
      'enabled': true,
      'triggered_at': null,
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

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 't@e.com',
        displayName: 'T',
        createdAt: DateTime(2026),
      );
}

const _sembol = 'THYAO.IS';
const _gun = 86400000;

final _varlik = Asset(
  id: 'v1',
  userId: 'u1',
  name: 'THY',
  ticker: _sembol,
  type: AssetType.hisse,
  quantity: 1,
  purchasePrice: 100,
  currency: 'TRY',
  notes: '',
  currentPrice: 101,
  addedDate: DateTime(2025, 3, 14),
);

Map<String, dynamic> _fiyatSatiri(String id, double hedef) => {
      'id': id,
      'user_id': 'u1',
      'symbol': _sembol,
      'label': 'THY',
      'target_price': hedef,
      'direction': 'above',
      'enabled': true,
      'created_at': '2026-10-28T09:00:00Z',
    };

Map<String, dynamic> _cizgiSatiri(String id, String cizimId,
        {bool uzanir = true}) {
  final simdi = DateTime.now().millisecondsSinceEpoch;
  return {
    'id': id,
    'user_id': 'u1',
    'symbol': _sembol,
    'label': 'THY',
    'cizim_id': cizimId,
    'cizim_imzasi': 'x',
    't1': simdi - _gun,
    'p1': 90.0,
    't2': simdi + _gun,
    'p2': 110.0,
    'uzanir': uzanir,
    'yon': 'yukari',
    'enabled': true,
    'created_at': '2026-10-28T09:00:00Z',
  };
}

GrafikCizimi _yatay(String id, double p) =>
    GrafikCizimi(tur: CizimTuru.yatay, a: CizimNoktasi(0, p), id: id);

GrafikCizimi _trend(String id) => GrafikCizimi(
      tur: CizimTuru.trend,
      a: const CizimNoktasi(0, 90),
      b: const CizimNoktasi(_gun, 110),
      id: id,
    );

class _Ortam {
  final fiyat = _FiyatKapi();
  final seviye = _SeviyeDepo();
  late WidgetRef ref;

  List<Override> get overrides => [
        authProvider.overrideWith(_FakeAuth.new),
        priceAlertServiceProvider.overrideWithValue(PriceAlertService(fiyat)),
        seviyeAlarmiServiceProvider
            .overrideWithValue(SeviyeAlarmiService(seviye)),
        premiumOzellikleriGorunurProvider.overrideWithValue(true),
        premiumKilitliProvider.overrideWithValue(false),
      ];

  Widget uygulama(Widget govde) => ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: govde,
        ),
      );

  /// Ref'i yakalar ve listelerin yüklenmesini bekler.
  Future<void> kur(WidgetTester t, {Widget? govde}) async {
    await t.pumpWidget(uygulama(Scaffold(
      body: Consumer(builder: (_, r, __) {
        ref = r;
        // Dinleyicisiz provider yeniden kurulmaz (auth gelince liste
        // yüklenmez); ekran gibi izlenir.
        r.watch(priceAlertsProvider);
        r.watch(cizimAlarmlariProvider);
        r.watch(gostergeAlarmlariProvider);
        r.watch(yatayAlarmBaglariProvider);
        return govde ?? const SizedBox();
      }),
    )));
    // Yüklemeler sahte zamanın içinde başlar ve pump ile akar; `runAsync`
    // içinden beklemek, sahte bölgede başlamış geleceği hiç bitirmezdi.
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> esitle(WidgetTester t, List<GrafikCizimi> cizimler,
      CizimAlarmCopu cop,
      {double canliBirim = 101, List<String>? bildirimler}) async {
    var bitti = false;
    unawaited(cizimAlarmlariniEsitle(ref,
        varlik: _varlik,
        canliBirim: canliBirim,
        cizimler: cizimler,
        olcek: null,
        bildir: (m) => bildirimler?.add(m),
        l10n: lookupAppLocalizations(const Locale('tr')),
        cop: cop).then((_) => bitti = true));
    for (var i = 0; i < 5 && !bitti; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
    expect(bitti, isTrue, reason: 'eşitleme bitmedi');
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('geri al alarmı da getirir (1)', () {
    testWidgets('trend: tümünü sil → geri al → alarm aynı çizimle döner',
        (t) async {
      final o = _Ortam();
      o.seviye.satirlar[SeviyeAlarmiService.cizimTablosu] = [
        _cizgiSatiri('s0', 'c1'),
      ];
      await o.kur(t);
      final cop = CizimAlarmCopu();
      final bildirim = <String>[];

      await o.esitle(t, const [], cop, bildirimler: bildirim);
      expect(o.seviye.satirlar[SeviyeAlarmiService.cizimTablosu], isEmpty);
      expect(cop.cizgi.keys, ['c1']);
      expect(bildirim, ['Çizim silindi, çizgi alarmı da kaldırıldı']);

      await o.esitle(t, [_trend('c1')], cop, bildirimler: bildirim);
      final satir =
          o.seviye.satirlar[SeviyeAlarmiService.cizimTablosu]!.single;
      expect(satir['cizim_id'], 'c1');
      expect(satir['p1'], 90.0);
      expect(satir['p2'], 110.0);
      expect(cop.cizgi, isEmpty);
      expect(bildirim.last, 'Çizginin alarmı da geri geldi');
      expect(o.ref.read(cizimAlarmlariProvider).value!.single.cizimId, 'c1');
    });

    testWidgets('tek çizim sil → geri al: yalnız o çizimin alarmı döner',
        (t) async {
      final o = _Ortam();
      o.seviye.satirlar[SeviyeAlarmiService.cizimTablosu] = [
        _cizgiSatiri('s0', 'c1'),
        _cizgiSatiri('s9', 'c2'),
      ];
      await o.kur(t);
      final cop = CizimAlarmCopu();
      await o.esitle(t, [_trend('c2')], cop);
      expect(
          o.seviye.satirlar[SeviyeAlarmiService.cizimTablosu]!
              .map((r) => r['cizim_id']),
          ['c2']);
      await o.esitle(t, [_trend('c1'), _trend('c2')], cop);
      expect(
          o.seviye.satirlar[SeviyeAlarmiService.cizimTablosu]!
              .map((r) => r['cizim_id'])
              .toSet(),
          {'c1', 'c2'});
    });

    testWidgets('çöp yoksa (eski çağrı) geri al alarm kurmaz', (t) async {
      final o = _Ortam();
      o.seviye.satirlar[SeviyeAlarmiService.cizimTablosu] = [
        _cizgiSatiri('s0', 'c1'),
      ];
      await o.kur(t);
      final cop = CizimAlarmCopu();
      await o.esitle(t, const [], cop);
      // Başka bir ekranın çöpü bu çizimi bilmez.
      await o.esitle(t, [_trend('c1')], CizimAlarmCopu());
      expect(o.seviye.satirlar[SeviyeAlarmiService.cizimTablosu], isEmpty);
    });
  });

  group('yatay çizgi ↔ fiyat alarmı bağı (2)', () {
    testWidgets('silinen çizgi alarmını siler, geri al yeniden kurar',
        (t) async {
      final o = _Ortam();
      o.fiyat.rows.add(_fiyatSatiri('a1', 120));
      await o.kur(t);
      o.ref.read(yatayAlarmBaglariProvider.notifier).bagla('y1', 'a1', 120);
      final cop = CizimAlarmCopu();

      await o.esitle(t, const [], cop);
      expect(o.fiyat.rows, isEmpty);
      expect(o.ref.read(yatayAlarmBaglariProvider), isEmpty);
      expect(cop.yatay.keys, ['y1']);

      await o.esitle(t, [_yatay('y1', 120)], cop);
      final yeni = o.fiyat.rows.single;
      expect(yeni['target_price'], 120);
      expect(yeni['direction'], 'above');
      expect(o.ref.read(yatayAlarmBaglariProvider)['y1']?.alarmId, yeni['id']);
      // Bağ cihazda saklanır.
      await t.pump(const Duration(milliseconds: 20));
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('pref_grafik_cizim_alarm_baglari_v1'),
          contains(yeni['id'] as String));
    });

    testWidgets('taşınan çizgi aynı alarmın hedefini ve yönünü değiştirir',
        (t) async {
      final o = _Ortam();
      o.fiyat.rows.add(_fiyatSatiri('a1', 120));
      await o.kur(t);
      o.ref.read(yatayAlarmBaglariProvider.notifier).bagla('y1', 'a1', 120);
      await o.esitle(t, [_yatay('y1', 95)], CizimAlarmCopu());
      final r = o.fiyat.rows.single;
      expect(r['id'], 'a1');
      expect(r['target_price'], 95);
      expect(r['direction'], 'below');
      expect(o.ref.read(yatayAlarmBaglariProvider)['y1']?.fiyat, 95);
    });

    testWidgets('taşınmayan çizgi elle değiştirilmiş hedefe dokunmaz',
        (t) async {
      final o = _Ortam();
      o.fiyat.rows.add(_fiyatSatiri('a1', 125));
      await o.kur(t);
      // Sayfada hedef 125'e çekildi; çizgi 120'de duruyor.
      o.ref.read(yatayAlarmBaglariProvider.notifier).bagla('y1', 'a1', 120);
      await o.esitle(t, [_yatay('y1', 120)], CizimAlarmCopu());
      expect(o.fiyat.rows.single['target_price'], 125);
    });

    testWidgets('Alarmlarım\'dan silinmiş alarmın bağı çözülür', (t) async {
      final o = _Ortam();
      await o.kur(t);
      o.ref.read(yatayAlarmBaglariProvider.notifier).bagla('y1', 'yok', 120);
      await o.esitle(t, [_yatay('y1', 120)], CizimAlarmCopu());
      expect(o.ref.read(yatayAlarmBaglariProvider), isEmpty);
      expect(o.fiyat.rows, isEmpty);
    });

    GrafikOlcegi olcek() => GrafikOlcegi(
          zamanlar: const [0, _gun],
          aralikMs: _gun,
          gorunum: (bas: 0, son: 1),
          genislik: 300,
          fiyatAlani: 200,
          dusuk: 90,
          yuksek: 130,
        );

    Widget zil(_Ortam o, GrafikCizimi c) => Center(
          child: CizimAlarmDugmesi(
            cizim: c,
            varlik: _varlik,
            ad: 'THY',
            canliBirim: 101,
            olcek: olcek(),
            kimlikVer: () => c.id!,
            bildir: (_) {},
          ),
        );

    testWidgets('bağlı, nöbetteki alarm zili doldurur; dokunuş kaldırır',
        (t) async {
      final o = _Ortam();
      o.fiyat.rows.add(_fiyatSatiri('a1', 120));
      SharedPreferences.setMockInitialValues({
        'pref_grafik_cizim_alarm_baglari_v1':
            '{"y1":{"a":"a1","p":120.0}}',
      });
      await o.kur(t, govde: zil(o, _yatay('y1', 120)));
      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
      expect(find.byTooltip('Çizgi alarmını kaldır'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('tamEkranCizimAlarmi')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(o.fiyat.rows, isEmpty, reason: 'ikinci alarm değil, kaldırma');
      expect(o.ref.read(yatayAlarmBaglariProvider), isEmpty);
      expect(find.byIcon(Icons.add_alert_outlined), findsOneWidget);
    });

    testWidgets('bağsız yatay çizgide zil boş', (t) async {
      final o = _Ortam();
      o.fiyat.rows.add(_fiyatSatiri('a1', 120));
      await o.kur(t, govde: zil(o, _yatay('y2', 120)));
      expect(find.byIcon(Icons.add_alert_outlined), findsOneWidget);
      expect(find.byTooltip('Bu çizgiye alarm kur'), findsOneWidget);
    });
  });

  group('varlık şeridi gösterge/çizgi alarmlarını sayar (3)', () {
    testWidgets('2 fiyat + EMA50 + trend → "4 aktif alarm" + özet çipi',
        (t) async {
      final o = _Ortam();
      o.fiyat.rows
        ..add(_fiyatSatiri('a1', 120))
        ..add(_fiyatSatiri('a2', 130));
      o.seviye.satirlar[SeviyeAlarmiService.gostergeTablosu] = [
        {
          'id': 'g1',
          'user_id': 'u1',
          'symbol': _sembol,
          'label': 'THY',
          'gosterge': GostergeKodu.ema50.kod,
          'yon': 'yukari',
          'enabled': true,
        },
      ];
      o.seviye.satirlar[SeviyeAlarmiService.cizimTablosu] = [
        _cizgiSatiri('s0', 'c1'),
      ];
      await o.kur(t,
          govde: const AlarmSeridi(sembol: _sembol, ad: 'THY', guncelFiyat: 101));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('4 aktif alarm'), findsOneWidget);
      expect(find.text('2 gösterge/çizgi alarmı'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('alarmSeridiSeviyeOzeti')));
      await t.pumpAndSettle();
      expect(find.byType(PriceAlertsScreen), findsOneWidget);
      // (4) Başlık ve çizgi satırının seviyesi (ışın: bitiş yok).
      expect(find.text('Alarmlarım'), findsOneWidget);
      expect(find.text('Fiyat Alarmları'), findsNothing);
      expect(find.textContaining('Çizgi şu an ₺100'), findsOneWidget);
      expect(find.textContaining('tarihine kadar'), findsNothing);
    });
  });

  group('Alarmlarım ekranı (4)', () {
    test('model: çizginin bugünkü seviyesi sunucuyla aynı kural', () {
      final a = CizimAlarmi.fromMap({
        ..._cizgiSatiri('s0', 'c1', uzanir: false),
        't1': 0,
        't2': 1000,
      })!;
      expect(a.seviye(500), closeTo(100, 1e-9));
      expect(a.seviye(-5), 90, reason: 'başlamamış doğru: başlangıç seviyesi');
      expect(a.seviye(1001), isNull, reason: 'bitmiş parça: seviye yok');
      final isin = CizimAlarmi.fromMap({
        ..._cizgiSatiri('s0', 'c1'),
        't1': 0,
        't2': 1000,
      })!;
      expect(isin.seviye(2000), closeTo(130, 1e-9));
    });

    test('başlık "Alarmlarım", çizgi satırı seviye ve bitiş yazar', () {
      final k = ekranKaynagiSync('lib/screens/price_alerts_screen.dart');
      expect(k, contains('title: context.l10n.myAlarms'));
      expect(k, contains('cizimAlarmSeviyesiBitisli('));
      expect(k, contains('c.seviye('));
    });
  });
}
