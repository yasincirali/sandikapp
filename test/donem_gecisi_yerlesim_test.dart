import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/secili_donem_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';
import 'package:portfoy_takip/screens/varlik_sayfasi.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/donem_secici.dart';
import 'package:portfoy_takip/widgets/katmanli_fiyat_grafigi.dart';
import 'package:portfoy_takip/widgets/varlik_ozeti.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dönem değişince grafiğin ve kâr/zarar yazısının YERİ değişmez (yasin
/// 2026-11-11, TestFlight: "tüm grafiklerde dönem değişimi akıcı olmalı;
/// grafik yerleşiminin konumu ve kâr/zarar yazısının konumu değişiyor. Fark
/// olacaksa en az olsun").
///
/// `grafik_aralik_gecisi_test` grafiğin SÖKÜLMEDİĞİNİ kilitler; bu dosya
/// çevresindeki YERLEŞİMİ: her yüzeyde, her dönem çipinde
///  • grafik kutusunun üstü ve boyu aynı (≤ 0,5 pt),
///  • kâr/zarar yazısının solu ve dikey ortası aynı (≤ 0,5 pt),
/// 1× ve 2× yazı ölçeğinde. Veri gerçekçi: Performans'ta 60 gün önce büyük
/// alım (kısa dönemde akış yok, uzunda var — alt kat eskiden yalnız akışlı
/// dönemde çiziliyordu, grafik ~110 pt atlıyordu), tutar hanesi ve yüzde
/// hanesi dönemden döneme değişir (₺819 ↔ ₺54.101; %0,6 ↔ dört haneli).
///
/// Ölçülen sebepler ve çözümleri: `kartlar.dart` `_KahramanSatiri` ve alt kat
/// notu, `grafik_kabi.dart` işlem hacmi paneli notu.
const _uid = 'user-1';

Asset _lot({int gunOnce = 800, String id = 'lot-1', double adet = 10}) => Asset(
      id: id,
      userId: _uid,
      name: 'THYAO',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: adet,
      purchasePrice: 90,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 150,
      addedDate: DateTime.now().subtract(Duration(days: gunOnce)),
    );

/// 200 gün önce temettü: 6 ay ve üstünde dönem içinde, kısa dönemde değil
/// (yasin'ın ekran kaydı 2026-11-13: temettü satırı dönemle gelip gidiyordu).
Asset _temettu() => Asset(
      id: 'tem-1',
      userId: _uid,
      name: 'THYAO',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 0,
      purchasePrice: 0,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 150,
      kind: AssetKind.dividend,
      dividendAmount: 25,
      addedDate: DateTime.now().subtract(const Duration(days: 200)),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test',
        createdAt: DateTime(2025, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this.lotlar);
  final List<Asset> lotlar;
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: lotlar,
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
        ownerId: _uid,
      );
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

/// Ağ kapısı: [tut] açıkken yeni çekimler [birak]'a kadar bekler.
class _Kapi {
  bool tut = false;
  final _bekleyen = <(Completer<List<(int, double)>>, String?)>[];

  Future<List<(int, double)>> cek(String sym, String range, String? interval) {
    if (!tut) return Future.value(_seri(interval));
    final c = Completer<List<(int, double)>>();
    _bekleyen.add((c, interval));
    return c.future;
  }

  void birak() {
    tut = false;
    for (final (c, interval) in _bekleyen) {
      c.complete(_seri(interval));
    }
    _bekleyen.clear();
  }

  static List<(int, double)> _seri(String? interval) {
    final simdi = DateTime.now();
    final gunIci =
        interval != null && (interval.endsWith('m') || interval.endsWith('h'));
    if (gunIci) {
      final bas = DateTime(simdi.year, simdi.month, simdi.day);
      return [
        for (var i = 0; i < 288; i++)
          (
            bas.add(Duration(minutes: 5 * i)).millisecondsSinceEpoch,
            148 + (i % 20) * 0.1,
          ),
      ];
    }
    return [
      for (var g = 2200; g >= 0; g--)
        (
          DateTime(simdi.year, simdi.month, simdi.day - g, 12)
              .millisecondsSinceEpoch,
          100 + (2200 - g) * 0.02 + (g % 7),
        ),
    ];
  }
}

Future<void> _yerles(WidgetTester tester, [int kare = 30]) async {
  for (var i = 0; i < kare; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

List<String> _etiketler(WidgetTester t) {
  final s = <String>[];
  for (final e in find
      .descendant(of: find.byType(DonemSecici), matching: find.byType(Text))
      .evaluate()) {
    final d = (e.widget as Text).data;
    if (d != null && !d.contains('%') && d != '—' && !s.contains(d)) s.add(d);
  }
  return s;
}

typedef _Olcum = ({String donem, Rect kutu, Rect? metin, String? yazi});

/// Her dönem çipine sırayla dokunur (sonunda ilk çipe döner), yerleşince
/// grafik kutusunu ve kâr/zarar yazısını ölçer.
Future<List<_Olcum>> _olc(
    WidgetTester tester, Finder kutu, Finder Function() metin) async {
  final etiketler = _etiketler(tester);
  expect(etiketler.length, greaterThanOrEqualTo(5),
      reason: 'ön koşul: dönem çipleri bulundu');
  final sonuc = <_Olcum>[];
  for (final e in [...etiketler, etiketler.first]) {
    await tester.tap(find
        .descendant(of: find.byType(DonemSecici), matching: find.text(e))
        .first);
    await _yerles(tester, 40);
    final m = metin();
    final varMi = m.evaluate().isNotEmpty;
    sonuc.add((
      donem: e,
      kutu: tester.getRect(kutu),
      metin: varMi ? tester.getRect(m.first) : null,
      yazi: varMi ? (m.evaluate().first.widget as Text).data : null,
    ));
  }
  return sonuc;
}

/// [punto]: yazının BOYU da aynı olmalı (1×'te rakam küçülmez; eskiden
/// geniş yüzde rozeti Performans manşetini 28 → 24 pt'ye eziyordu). 2×'te
/// sığmayan tutarın küçülmesi kabul — yeri (sol, dikey orta) yine sabit.
void _ayniYerde(List<_Olcum> o, String yuzey, {bool punto = false}) {
  String tablo() => [
        for (final x in o)
          '${x.donem}: kutu ${x.kutu.top.toStringAsFixed(1)}/'
              '${x.kutu.height.toStringAsFixed(1)} · yazı "${x.yazi}" '
              '${x.metin?.left.toStringAsFixed(1)},'
              '${x.metin?.center.dy.toStringAsFixed(1)} '
              'h ${x.metin?.height.toStringAsFixed(1)}',
      ].join('\n');
  final ilk = o.first;
  expect(ilk.metin, isNotNull,
      reason: '$yuzey: kâr/zarar yazısı bulunamadı\n${tablo()}');
  for (final x in o) {
    expect((x.kutu.top - ilk.kutu.top).abs(), lessThanOrEqualTo(0.5),
        reason: '$yuzey · ${x.donem}: grafik kutusunun üstü kaydı\n${tablo()}');
    expect((x.kutu.height - ilk.kutu.height).abs(), lessThanOrEqualTo(0.5),
        reason: '$yuzey · ${x.donem}: grafik kutusunun boyu değişti\n'
            '${tablo()}');
    expect(x.metin, isNotNull,
        reason: '$yuzey · ${x.donem}: kâr/zarar yazısı yok\n${tablo()}');
    expect((x.metin!.left - ilk.metin!.left).abs(), lessThanOrEqualTo(0.5),
        reason: '$yuzey · ${x.donem}: kâr/zarar yazısı yatay kaydı\n'
            '${tablo()}');
    expect((x.metin!.center.dy - ilk.metin!.center.dy).abs(),
        lessThanOrEqualTo(0.5),
        reason: '$yuzey · ${x.donem}: kâr/zarar yazısı dikey kaydı\n'
            '${tablo()}');
    if (punto) {
      expect(
          (x.metin!.height - ilk.metin!.height).abs(), lessThanOrEqualTo(0.5),
          reason: '$yuzey · ${x.donem}: kâr/zarar yazısı küçüldü/büyüdü\n'
              '${tablo()}');
    }
  }
}

Widget _olcekli(double olcek, Widget cocuk) => Builder(
      builder: (c) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(olcek)),
        child: cocuk,
      ),
    );

/// Performans kartının manşet tutarı ("+₺54.101", "Değişim yok"…): ağaçta
/// ilk eşleşen (alt kat kalemleri ondan sonra gelir).
final _manset = RegExp(r'^[+−]₺|^Değişim yok|^Bugünün verisi');

/// Varlık ekranlarının dönem değişimi satırı ("+%2,47 · +₺3,62 / lot · 1 ay";
/// gün içi veri gelmeden "Bugün…" cümlesi).
final _degisim = RegExp(r'%|Bugün|Değişim yok');

class _Takip extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => const [];
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  late _Kapi kapi;
  setUp(() {
    HistoryService.clearCache();
    kapi = _Kapi();
    HistoryService.seriCekici = kapi.cek;
  });
  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    RemoteConfigService.testAcik = {};
  });

  for (final olcek in [1.0, 2.0]) {
    // Tek akış (RC `performans_tek_akis`) TestFlight'ta açık; manşetin
    // altındaki cümle ve paylaş simgesi orada dönemle gelip gidiyordu
    // (yasin 2026-11-12). İki düzen de ölçülür.
    for (final tek in [false, true]) {
    final ad = tek ? ' · tek akış' : '';
    testWidgets('Performans (${olcek}x$ad): grafik ve manşet yerinde',
        (tester) async {
      if (tek) RemoteConfigService.testAcik = {'performans_tek_akis'};
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          portfolioProvider.overrideWith(() => _FakePortfolio([
                _lot(),
                // 60 gün önce büyük alım: 3 ay ve üstünde akış var.
                _lot(gunOnce: 60, id: 'lot-2', adet: 900),
                _temettu(),
              ])),
          partnersProvider.overrideWith(_FakePartners.new),
          allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        ],
        child: MaterialApp(
          builder: (c, w) => _olcekli(olcek, w!),
          home: PortfolioPerformanceScreen(
            initialPeriodIdx: SummaryPeriod.birAy.index,
          ),
        ),
      ));
      await _yerles(tester);
      final o = await _olc(
        tester,
        find.byType(ZoomableChart),
        () => find.byWidgetPredicate(
            (w) => w is Text && w.data != null && _manset.hasMatch(w.data!)),
      );
      // Tek akışta manşet `numLarge`: altı haneli tutar yüzde rozetiyle
      // satıra sığmayınca küçülür (yeri sabit); punto yalnız eski düzende.
      _ayniYerde(o, 'Performans', punto: olcek == 1.0 && !tek);
      // Grafik kartının DİBİ de yerinde: işlem hacmi paneli her dönemde
      // durur (Bugün/1 hf'de yoktu, kart ~98 pt kısalıp altını çekiyordu).
      final hacimYeri = <String, double>{};
      for (final e in _etiketler(tester)) {
        await tester.tap(find
            .descendant(of: find.byType(DonemSecici), matching: find.text(e))
            .first);
        await _yerles(tester, 40);
        final etiket = find.text('Alım · satış');
        expect(etiket, findsOneWidget, reason: '$e: hacim paneli yok');
        hacimYeri[e] = tester.getRect(etiket).top;
      }
      final ilkHacim = hacimYeri.values.first;
      for (final x in hacimYeri.entries) {
        expect((x.value - ilkHacim).abs(), lessThanOrEqualTo(0.5),
            reason: 'hacim paneli kaydı: $hacimYeri');
      }
      // Kartın üstü de (grafik kutusunun dış çerçevesi) yerinde.
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _yerles(tester, 12);
    });

    // Yerleşmiş hâl yetmez: bekleme kareleri de ölçülür (yasin 2026-11-11,
    // "varlık detaydaki gibi seçimden sonra sabit kalmalı"). İlk kez açılan
    // Bugün'de seri beklenirken dönem kartı boşa düşüyor, grafik ~200 pt
    // yukarı kayıp seri gelince geri iniyordu; eski kodda kırmızı.
    testWidgets('Performans (${olcek}x$ad): bekleme karelerinde de yerinde',
        (tester) async {
      if (tek) RemoteConfigService.testAcik = {'performans_tek_akis'};
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          portfolioProvider.overrideWith(() => _FakePortfolio([
                _lot(),
                _lot(gunOnce: 60, id: 'lot-2', adet: 900),
                _temettu(),
              ])),
          partnersProvider.overrideWith(_FakePartners.new),
          allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        ],
        child: MaterialApp(
          builder: (c, w) => _olcekli(olcek, w!),
          home: PortfolioPerformanceScreen(
            initialPeriodIdx: SummaryPeriod.birAy.index,
          ),
        ),
      ));
      await _yerles(tester);
      final grafik = find.byType(ZoomableChart);
      final secici = find.byType(DonemSecici).first;
      final ilkGrafik = tester.getRect(grafik);
      final ilkSecici = tester.getRect(secici);
      final ilkState = tester.state(grafik);
      final etiketler = _etiketler(tester);
      for (final e in [...etiketler, etiketler.first]) {
        // Yeni çekimler kare 10'a kadar bekler: seri yokken ara kareler.
        kapi.tut = true;
        await tester.tap(find
            .descendant(of: find.byType(DonemSecici), matching: find.text(e))
            .first);
        for (var k = 0; k < 24; k++) {
          if (k == 10) kapi.birak();
          await tester.pump(const Duration(milliseconds: 16));
          expect(grafik, findsOneWidget, reason: '$e kare $k: grafik söküldü');
          final r = tester.getRect(grafik);
          expect((r.top - ilkGrafik.top).abs(), lessThanOrEqualTo(0.5),
              reason: '$e kare $k: grafik ${ilkGrafik.top} -> ${r.top} kaydı');
          expect((r.height - ilkGrafik.height).abs(), lessThanOrEqualTo(0.5),
              reason: '$e kare $k: grafik boyu değişti');
          expect(tester.getRect(secici).top, ilkSecici.top,
              reason: '$e kare $k: dönem seçici kaydı');
          expect(identical(tester.state(grafik), ilkState), isTrue,
              reason: '$e kare $k: grafik yeniden kuruldu (morf yerine '
                  'ilk çizim)');
        }
        await _yerles(tester, 20);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _yerles(tester, 12);
    });

    }

    testWidgets('Varlık detayı (${olcek}x): grafik ve dönem değişimi yerinde',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final lot = _lot(gunOnce: 100);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          portfolioProvider.overrideWith(() => _FakePortfolio([lot])),
        ],
        child: MaterialApp(
          builder: (c, w) => _olcekli(olcek, w!),
          home: AssetDetailScreen(asset: lot, showBackButton: true),
        ),
      ));
      await _yerles(tester);
      final o = await _olc(
        tester,
        find.byType(ZoomableChart),
        () => find.descendant(
            of: find.byType(VarlikFiyatBlogu),
            matching: find.byWidgetPredicate((w) =>
                w is Text && w.data != null && _degisim.hasMatch(w.data!))),
      );
      _ayniYerde(o, 'Varlık detayı', punto: true);
      await tester.pumpWidget(const SizedBox());
      await _yerles(tester, 12);
    });

    testWidgets('Varlık sayfası (${olcek}x): grafik ve dönem değişimi yerinde',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final simdi = DateTime.now().millisecondsSinceEpoch;
      // Dönem sonu fiyatı dönemden döneme hane sayısı ve yön değiştirir.
      Map<int, double> seri(int gun) {
        final bitis = const {
              0: 101.0,
              7: 99.0,
              30: 1234.56,
              90: 12.5,
              180: 15000.0,
              365: 0.9,
              1825: 123456.78,
            }[gun] ??
            100.0;
        final adim =
            gun == 0 ? const Duration(minutes: 5) : const Duration(days: 1);
        final n = gun == 0 ? 80 : (gun < 30 ? 7 : 120);
        return {
          for (var i = 0; i < n; i++)
            simdi - adim.inMilliseconds * (n - 1 - i):
                100 + (bitis - 100) * i / (n - 1),
        };
      }

      await tester.pumpWidget(ProviderScope(
        overrides: [
          seciliDonemProvider.overrideWith((ref) => SummaryPeriod.birAy),
          portfolioProvider.overrideWith(() => _FakePortfolio(const [])),
          watchlistProvider.overrideWith(_Takip.new),
        ],
        child: MaterialApp(
          builder: (c, w) => _olcekli(olcek, w!),
          home: Scaffold(
            body: VarlikSayfasi(
              kimlik: const VarlikKimligi(
                ticker: 'THYAO.IS',
                name: 'Türk Hava Yolları',
                type: AssetType.hisse,
                currency: 'TRY',
              ),
              tamAcilis: true,
              tazeYukleyici: (_, gun) async =>
                  (seri: seri(gun), bayatZaman: null),
              eldekiYukleyici: (_, __) async => null,
            ),
          ),
        ),
      ));
      await _yerles(tester);
      final o = await _olc(
        tester,
        find.byType(KatmanliFiyatGrafigi),
        () => find.descendant(
            of: find.byType(VarlikFiyatBlogu),
            matching: find.byWidgetPredicate((w) =>
                w is Text && w.data != null && _degisim.hasMatch(w.data!))),
      );
      _ayniYerde(o, 'Varlık sayfası', punto: true);
      await tester.pumpWidget(const SizedBox());
      await _yerles(tester, 12);
    });
  }
}
