import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/secili_donem_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/tazelik_ritmi.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';

/// **Varlık sayfası: dönem serisi fiyat turunu beklemeden (Ar-Ge 12 Kas §3).**
///
/// Bildirimden/aramadan soğuk açılan sayfa açılış fiyat turunun ortasına
/// düşer. `_loadHistory` eskiden seriyi istemeden önce turu (en çok 5 dk)
/// bekliyordu; günlük kapanış serisi canlı fiyata bağlı değil, yalnız uç ve
/// ölçek hizası öyle. Bu test sahte, GECİKMELİ bir turla iki anı ölçer:
/// seri isteğinin ağa çıktığı an ve grafiğin ilk çizildiği an.
///
/// Ölçüm (fake zaman, 50 ms adım, tur 2 sn, ağ anında yanıtlıyor; 1A):
/// - önce: seri isteği 2050 ms, ilk çizim 2050 ms (tur süresi kadar boş)
/// - sonra: seri isteği 50 ms, ilk çizim 50 ms (ilk ölçüm adımı)
/// GÜNLÜK dönemde ve canlı kuru henüz bilinmeyen USD/altın varlıkta
/// bekleme sürer (kararın gerekçesi `_loadHistory` yorumunda).

const _uid = 'user-1';
const _turSuresi = Duration(seconds: 2);

Asset _hisse({double fiyat = 312.40}) => Asset(
      id: 'THYAO-1',
      userId: _uid,
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 100,
      purchasePrice: 250.75,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 3, 14),
    );

Asset _usdHisse() => Asset(
      id: 'AAPL-1',
      userId: _uid,
      name: 'Apple',
      ticker: 'AAPL',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 180,
      currency: 'USD',
      notes: '',
      isManualPrice: false,
      currentPrice: 230,
      addedDate: DateTime(2026, 3, 14),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test Kullanıcı',
        createdAt: DateTime(2026, 1, 1),
      );
}

/// Açılış turu ağdayken açılan sayfa: tur [tur] tamamlanınca biter.
class _TurluPortfoy extends PortfolioNotifier {
  _TurluPortfoy(this.varlik, this.tur);
  final Asset varlik;
  final Completer<void> tur;

  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [varlik],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );

  @override
  Future<void> fiyatTurunuBekle({Duration enFazla = TazelikRitmi.yuzey}) =>
      tur.future;

  @override
  Future<void> fiyatTurunuVeKareyiBekle(
          {Duration enFazla = TazelikRitmi.yuzey}) =>
      tur.future;

  @override
  bool get fiyatTuruSuruyor => !tur.isCompleted;

  /// Turun yayını: yeni fiyat defterdeki lot'a yazılır, sonra tur biter.
  void turuBitir(double yeniFiyat) {
    final s = state.valueOrNull!;
    // Gerçek tur da fiyatı lot'a yerinde yazar ve YENİ liste yayınlar.
    for (final a in s.assets) {
      a.currentPrice = yeniFiyat;
    }
    state = AsyncData(s.copyWith(assets: [...s.assets]));
    tur.complete();
  }
}

class _Olcum {
  /// İlk seri isteğinin ağa çıktığı an (hangi dönem olursa).
  Duration? istek;

  /// Gün içi serinin (`range=1d`) ilk istendiği an.
  Duration? gunIciIstek;

  /// Grafiğin ilk çizildiği an.
  Duration? cizim;
}

bool _gunIciMi(String cagri) => cagri.split('|')[1] == '1d';

void main() {
  late List<String> cagrilar;
  final simdiMs = DateTime.now().millisecondsSinceEpoch;
  final kurAsli = HistoryService.canliKur;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  setUp(() {
    HistoryService.clearCache();
    HistoryService.instance.clearTierCache();
    cagrilar = [];
    // Ağ anında yanıtlar: ölçülen şey turun beklettiği süre, ağ değil.
    HistoryService.seriCekici = (sym, range, interval) {
      cagrilar.add('$sym|$range|${interval ?? "-"}');
      return Future.value([
        for (var i = 400; i >= 0; i--)
          (simdiMs - i * const Duration(days: 1).inMilliseconds,
              300.0 + (i % 7)),
      ]);
    };
  });

  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    HistoryService.canliKur = kurAsli;
    HistoryService.clearCache();
  });

  Future<(_Olcum, _TurluPortfoy)> ac(WidgetTester tester,
      {required Asset varlik, required SummaryPeriod donem}) async {
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final tur = Completer<void>();
    late _TurluPortfoy portfoy;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider
            .overrideWith(() => portfoy = _TurluPortfoy(varlik, tur)),
        seciliDonemProvider.overrideWith((ref) => donem),
        sinyalYuzeyiProvider.overrideWithValue(SinyalYuzeyi.gizli),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: AssetDetailScreen(asset: varlik, showBackButton: true),
      ),
    ));
    final o = _Olcum();
    const adim = Duration(milliseconds: 50);
    var gecen = Duration.zero;
    while (gecen < const Duration(seconds: 4)) {
      if (gecen >= _turSuresi && !tur.isCompleted) {
        portfoy.turuBitir(varlik.currentPrice * 1.1);
      }
      await tester.pump(adim);
      gecen += adim;
      o.istek ??= cagrilar.isNotEmpty ? gecen : null;
      o.gunIciIstek ??= cagrilar.any(_gunIciMi) ? gecen : null;
      o.cizim ??= find.byType(ZoomableChart).evaluate().isNotEmpty
          ? gecen
          : null;
    }
    // ignore: avoid_print
    print('ÖLÇÜM ${varlik.ticker} ${donem.name}: istek=${o.istek?.inMilliseconds} ms, '
        'gün içi istek=${o.gunIciIstek?.inMilliseconds} ms, '
        'ilk çizim=${o.cizim?.inMilliseconds} ms (tur ${_turSuresi.inMilliseconds} ms)');
    return (o, portfoy);
  }

  Future<void> kapat(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  testWidgets('1A: seri isteği tur bitmeden başlar, grafik turdan önce çizilir',
      (tester) async {
    final (o, _) =
        await ac(tester, varlik: _hisse(), donem: SummaryPeriod.birAy);
    expect(o.istek, isNotNull);
    expect(o.istek!, lessThan(_turSuresi),
        reason: 'Günlük kapanış serisi canlı fiyata bağlı değil; tur '
            'beklenmeden istenmeli.');
    expect(o.cizim, isNotNull);
    expect(o.cizim!, lessThan(_turSuresi),
        reason: 'Grafik fiyat turunu beklemeden çizilmeli.');
    expect(o.gunIciIstek, isNotNull);
    expect(o.gunIciIstek!, greaterThanOrEqualTo(_turSuresi),
        reason: 'GÜNLÜK çipinin serisi de turu bekler.');
    await kapat(tester);
  });

  testWidgets('GÜNLÜK: gün içi seri tur bitene kadar istenmez',
      (tester) async {
    final (o, _) =
        await ac(tester, varlik: _hisse(), donem: SummaryPeriod.gunluk);
    expect(o.gunIciIstek, isNotNull);
    expect(o.gunIciIstek!, greaterThanOrEqualTo(_turSuresi),
        reason: 'Gün içi uç canlı fiyatla kurulur; tur beklenmeli.');
    expect(o.cizim!, greaterThanOrEqualTo(_turSuresi));
    await kapat(tester);
  });

  testWidgets('canlı kuru bilinmeyen USD varlık: ölçek hizası için tur beklenir',
      (tester) async {
    HistoryService.canliKur = () => null;
    final (o, _) =
        await ac(tester, varlik: _usdHisse(), donem: SummaryPeriod.birAy);
    expect(o.istek, isNotNull);
    expect(o.istek!, greaterThanOrEqualTo(_turSuresi),
        reason: 'Kur serisi canlı kura hizalanamıyorsa (kurSerisiniHizala) '
            'hizasız kare çizilmemeli.');
    await kapat(tester);
  });

  testWidgets('tur bitince uç yeni fiyatla yeniden kurulur (tek yenileme)',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final tur = Completer<void>();
    late _TurluPortfoy portfoy;
    final varlik = _hisse();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider
            .overrideWith(() => portfoy = _TurluPortfoy(varlik, tur)),
        seciliDonemProvider.overrideWith((ref) => SummaryPeriod.birAy),
        sinyalYuzeyiProvider.overrideWithValue(SinyalYuzeyi.gizli),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: AssetDetailScreen(asset: varlik, showBackButton: true),
      ),
    ));
    double sonY() {
      final g = tester.widget<ZoomableChart>(find.byType(ZoomableChart));
      return g.builder(g.fullMinX, g.fullMaxX).lineBarsData.first.spots.last.y;
    }

    AssetDetailScreen.debugTurSonrasiYenilemeler.clear();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ZoomableChart), findsOneWidget,
        reason: 'Grafik tur sürerken çizilmeli.');
    expect(AssetDetailScreen.debugTurSonrasiYenilemeler, isEmpty);
    final istekOnce = cagrilar.length;

    portfoy.turuBitir(varlik.currentPrice * 1.1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Seçili dönem (1A) ve gün içi olmayan çipler TEK yenilemede.
    final yenilemeler = AssetDetailScreen.debugTurSonrasiYenilemeler;
    expect(yenilemeler, hasLength(1),
        reason: 'Tur sonrası yenileme tek setState olmalı: $yenilemeler');
    expect(yenilemeler.single, contains(SummaryPeriod.birAy.days));
    expect(yenilemeler.single, isNot(contains(0)),
        reason: 'Gün içi seri turu bekler, yenilemeye girmez.');
    expect(yenilemeler.single.length, greaterThan(1),
        reason: 'Çipler de aynı yenilemede: $yenilemeler');
    expect(sonY(), isNotNaN);
    // Gün içi çip turdan sonra istenir; dönem serileri ağa yeniden çıkmaz.
    final yeniIstekler = cagrilar.skip(istekOnce).toList();
    expect(
        yeniIstekler.where((c) => !_gunIciMi(c)), isEmpty,
        reason: 'Tur sonrası yenileme tarihî noktaları önbellekten almalı: '
            '$yeniIstekler');
    await kapat(tester);
  });
}
