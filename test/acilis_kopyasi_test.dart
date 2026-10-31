import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/portfolio_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Açılışta son bilinen portföy (müşteri raporu 30 Eki 21:15 #1, yasin
/// "yap"): kopya anında çizilir, günün hükmü ilk fiyat turuna kadar
/// söylenmez, dövizli varlık uydurma kurla çizilmez.
const _uid = 'u1';

Asset _lot(String id, String ticker, AssetType tur,
        {String para = 'TRY', double fiyat = 100}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ticker,
      ticker: ticker,
      type: tur,
      quantity: 10,
      purchasePrice: 90,
      currency: para,
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 10, 1),
      createdAt: DateTime(2026, 10, 1),
    );

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

Future<PortfolioState> _ac() async {
  final c =
      ProviderContainer(overrides: [authProvider.overrideWith(_Auth.new)]);
  addTearDown(c.dispose);
  await c.read(authProvider.future);
  return c.read(portfolioProvider.future);
}

void main() {
  setUpAll(() => DbLogger.silentInTests = true);
  tearDownAll(() => DbLogger.silentInTests = false);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  test('kur yaz → oku; bilinmeyen kur (≤1) yazılmaz; clear siler', () async {
    await PortfolioCache.kurYaz(_uid, usd: 1, eur: 46, gbp: 54, altin: 0);
    expect(await PortfolioCache.kurOku(_uid), isNull);
    await PortfolioCache.kurYaz(_uid, usd: 42, eur: 46, gbp: 54, altin: 4100);
    final k = await PortfolioCache.kurOku(_uid);
    expect(k?.usd, 42);
    expect(k?.altin, 4100);
    expect(await PortfolioCache.kurOku('u2'), isNull);
    await PortfolioCache.clear(_uid);
    expect(await PortfolioCache.kurOku(_uid), isNull);
  });

  test('TL defter: açılış kopyası anında, bayraklı, sunucu beklenmeden',
      () async {
    await PortfolioCache.write(_uid, [_lot('a', 'THYAO.IS', AssetType.hisse)]);
    final s = await _ac();
    expect(s.onbellekKopyasi, isTrue);
    expect(s.assets.single.ticker, 'THYAO.IS');
    expect(s.ownerId, _uid);
    // Kopya bir "çevrimdışı" hatası değildir: şerit yok.
    expect(s.errorMessage, isNull);
  });

  test('dövizli varlık + son kur var: kopya o kurla', () async {
    await PortfolioCache.write(
        _uid, [_lot('a', 'AAPL', AssetType.hisse, para: 'USD')]);
    await PortfolioCache.kurYaz(_uid, usd: 42, eur: 46, gbp: 54, altin: 0);
    final s = await _ac();
    expect(s.onbellekKopyasi, isTrue);
    expect(s.usdTry, 42);
  });

  test('dövizli varlık + kur yok: kopya YOK (×1 kurla toplam uydurulmaz)',
      () async {
    await PortfolioCache.write(
        _uid, [_lot('a', 'AAPL', AssetType.hisse, para: 'USD')]);
    // Sunucu bu testte yok → eski çevrimdışı yol: kopya bayrağı yok.
    final s = await _ac();
    expect(s.onbellekKopyasi, isFalse);
    expect(s.errorMessage, isNotNull);
  });

  test('kopya yoksa (yeni kullanıcı) eski yol', () async {
    // Ne sunucu ne kopya: hata yukarı çıkar (eski davranış).
    await expectLater(_ac(), throwsA(anything));
  });

  test('Bugün kartı kopyada iskelette; BES otomatik katkı kopyada çalışmaz',
      () {
    final kart = ekranKaynagiSync('lib/widgets/bugun_karti.dart');
    expect(kart, contains('widget.state.onbellekKopyasi'));
    final ana = ekranKaynagiSync('lib/main.dart');
    expect(ana, contains('next.valueOrNull?.onbellekKopyasi ?? false'));
  });

  test('ilk fiyat turu bitince bayrak düşer (başarı ve hata yolu)', () {
    final p = ekranKaynagiSync('lib/providers/portfolio_provider.dart');
    expect(
        'onbellekKopyasi: false'.allMatches(p).length, greaterThanOrEqualTo(2));
  });
}
