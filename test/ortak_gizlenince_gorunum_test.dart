import 'package:flutter/material.dart';
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

/// Regresyon (kullanıcı bildirimi, 2026-09-28): ortaklı kullanıcı ortak
/// görünümündeyken Profil'den ortağı gizleyince ana ekranın toplam kartı
/// **₺0** yazıyordu — `_view` gizlenen ortağın id'sini tutmaya devam
/// ediyor, `allPartnerAssets[_view]` boş liste dönüyordu. Alttaki "Ben"
/// kartı doğru kaldığı için ekran kendisiyle çelişiyordu.
///
/// Kalıp `home_screen_overflow_test.dart` ile aynı; fark: ortak listesi bir
/// `StateProvider` ile test ortasında değiştirilebilir.

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
  });

  testWidgets('ortak görünümündeyken ortak gizlenince toplam Ben\'e döner',
      (tester) async {
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Başlangıç: Ben görünümü, kendi toplamı.
    expect(find.textContaining('31.240'), findsWidgets);

    // Çipten ortağa geç.
    await tester.tap(find.byType(GorunumCipi).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mehmet Yılmaz').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('10.000'), findsWidgets,
        reason: 'ortak görünümünde ortağın toplamı görünmeli');

    // Profil'deki "Gizle": aktif ortak listesi boşalır.
    container.read(_ortaklarCtl.notifier).state = const [];
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Hata: ₺0. Beklenen: görünüm Ben'e döner, kendi toplamı yazar.
    expect(find.text('₺0'), findsNothing,
        reason: 'gizlenen ortağın görünümü toplamı sıfırlamamalı');
    expect(find.textContaining('31.240'), findsWidgets);
    expect(find.textContaining('10.000'), findsNothing,
        reason: 'gizlenen ortağın rakamı hiçbir yerde kalmamalı');

    // Kaydırma ipucunun (`KaydirmaliGecis._gozKirp`) gecikmeleri bitsin.
    // 2026-09-28'den beri ortak görünümünde de piyasa satırı (tek başına
    // arama büyüteci) var; sliver sayısı görünümle değişmediği için hero
    // kart yeniden KURULMUYOR, ilk açılıştaki ipucu zamanlayıcısı canlı
    // kalıyor. Eskiden görünüm değişimi kartı baştan kurduğu için
    // zamanlayıcı yarıda ölüyordu.
    await tester.pump(const Duration(seconds: 3));
  });
}
