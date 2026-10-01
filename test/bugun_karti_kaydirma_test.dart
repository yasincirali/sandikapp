import 'package:flutter/material.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/widgets/bugun_karti.dart';
import 'package:portfoy_takip/widgets/kaydirmali_gecis.dart';
import 'package:portfoy_takip/widgets/sandik_skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/screens/home_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/widgets/gorunum_cipi.dart';

/// Kullanıcı bildirimi (2026-10-01): *"Ana sayfa varlık kartı
/// kaydırıldığında günlük veri kartı yüklenmediğinde slide yaptırmıyor."*
///
/// İki kök neden, ikisi de burada ana ekranın gerçek ağacında kilitli:
/// 1. Toplam kartının geçiş yayı görünmez bir kuyrukla ~1 sn sürüyordu;
///    kart oturmuş görünürken atılan ikinci kaydırma bekleyen geçişi
///    siliyordu (ayrıntı `kaydirmali_gecis.dart` "Görünmez kuyruk").
/// 2. Bugün kartı görünüm başına anahtarlı; geri dönülen görünümde az önce
///    yüklediği sonucu yeniden yüklerken iskelet çiziyordu.
///
/// Kalıp `ortak_gizlenince_gorunum_test.dart` ile aynı.

const _uid = 'user-1';
const _pid = 'partner-1';

Asset _asset({
  required String owner,
  required String ticker,
  required double qty,
  required double price,
}) =>
    Asset(
      id: '$owner-$ticker',
      userId: owner,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: price,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: price,
      addedDate: DateTime(2026, 3, 14),
    );

// Ben: 100 × 312,40 = ₺31.240 · Ortak: 10 × 1.000 = ₺10.000
final _benim = [_asset(owner: _uid, ticker: 'THYAO', qty: 100, price: 312.40)];
final _ortagin = [_asset(owner: _pid, ticker: 'ASELS', qty: 10, price: 1000)];

final _ortak = AppUser(
  id: _pid,
  email: 'p@x',
  displayName: 'Mehmet Yılmaz',
  createdAt: DateTime(2026, 1, 1),
);

/// Test ortasında değiştirilen ortak listesi — "Gizle" düğmesinin etkisi.
final _ortaklarCtl = StateProvider<List<AppUser>>((_) => [_ortak]);

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Ben',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: _benim,
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => {_pid: _ortagin};
}

class _FakeSignals extends SignalNotifier {
  @override
  Future<List<SignalAlert>> build() async => const [];
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    GorunumCipi.hafizayiSifirla();
    BugunKarti.anliklariTemizle();
    HistoryService.clearCache();
    // Seri anında (boş) döner: Bugün kartı ağ beklemeden yüklenir.
    HistoryService.seriCekici = (s, r, i) async => const [];
  });
  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    BugunKarti.anliklariTemizle();
  });

  Future<void> kur(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      partnersProvider.overrideWith(_FakePartners.new),
      activePartnersProvider.overrideWith((ref) => ref.watch(_ortaklarCtl)),
      allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
      signalProvider.overrideWith(_FakeSignals.new),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: ThemeData.dark(), home: const HomeScreen()),
    ));
    await tester.pump();
    // Bugün kartı yüklensin (testte ağa çıkan reel getiri kendi bütçesiyle
    // — `BugunYukleyici.varsayilanButce` — düşer), kaydırma ipucu bitsin.
    await tester.pump(const Duration(seconds: 12));
    await tester.pump(const Duration(seconds: 3));
  }

  String? secili(WidgetTester tester) =>
      tester.widget<GorunumCipi>(find.byType(GorunumCipi).first).selectedId;

  /// Gerçek parmak gibi: ~16 ms'lik karelerle sürükle, bırak.
  Future<void> kaydir(WidgetTester tester, double dx) async {
    final g = await tester
        .startGesture(tester.getCenter(find.byType(KaydirmaliGecis)));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(Offset(dx / 10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
  }

  Future<void> kareler(WidgetTester tester, int n) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('kart oturur oturmaz ikinci kaydırma da geçer', (tester) async {
    await kur(tester);
    expect(secili(tester), '');

    await kaydir(tester, -220);
    // Kart görsel olarak oturdu; görünüm de değişmiş olmalı. Ölçüm: yavaş
    // bırakmada yeni yolla ~500 ms, eski görünmez kuyrukla ~1,1 sn+.
    await kareler(tester, 45);
    expect(secili(tester), _pid,
        reason: 'kart yerine oturduğunda görünüm değişmiş olmalı');

    // Yeni görünümün Bugün kartı henüz yükleniyor olabilir — kaydırma
    // bunu beklemez.
    await kaydir(tester, -220);
    await kareler(tester, 45);
    expect(secili(tester), isNull, reason: 'Birlikte\'ye geçmeli');

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('geri dönülen görünümde Bugün kartı iskelet çizmez',
      (tester) async {
    await kur(tester);
    expect(find.byType(SandikSkeleton), findsNothing,
        reason: 'başlangıçta Bugün kartı yüklü');

    await kaydir(tester, -220); // Ben → ortak
    await kareler(tester, 45);
    await tester.pump(const Duration(seconds: 12)); // ortağın kartı yüklensin
    expect(secili(tester), _pid);

    await kaydir(tester, 220); // ortak → Ben
    // Geçişin işlendiği kareyi yakala: yeni kart o karede kurulur, yükleme
    // ondan sonra başlar — iskelet varsa tam burada görünür.
    for (var i = 0; i < 90 && secili(tester) != ''; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(secili(tester), '');
    await tester.pump();
    expect(find.byType(SandikSkeleton), findsNothing,
        reason: 'az önce yüklenen Ben kartı iskeletle yeniden açılmamalı');

    await tester.pump(const Duration(seconds: 3));
  });
}
