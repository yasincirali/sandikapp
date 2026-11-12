import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/fon_xray_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/db_logger.dart';

/// X-Ray fiyat turunda yeniden YÜKLENMEZ (Ar-Ge 12 Kas #6 ölçümü).
///
/// Temettü tahmininde bulunan hata (liste kimliğini izleyen FutureProvider
/// her fiyat turunda yükleniyor durumuna düşüyordu) X-Ray'de yok: sunucu
/// okuması (`xrayFonVerisiProvider`) fon KODLARI metnini izler, fiyat turu
/// aynı metni üretir ve Riverpod eşit değerde uyandırmaz. Ekranın okuduğu
/// `portfoyXrayProvider` senkron yeniden HESAPLAR (TL değer fiyata bağlı,
/// bilinçli) ama yükleniyor durumu üretmez. Bu test o ölçümü kilitler.
const _uid = 'u1';

Asset _fon({double miktar = 100, double fiyat = 1.5, String kod = 'TTE'}) =>
    Asset(
      id: 'f-$kod',
      userId: _uid,
      name: kod,
      ticker: kod,
      type: AssetType.fon,
      quantity: miktar,
      purchasePrice: 1,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      lastUpdated: DateTime(2026, 11, 12, 10),
      addedDate: DateTime(2026, 1, 5),
    );

class _Portfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: [_fon()], usdTry: 42, eurTry: 46, gbpTry: 54);

  void yaz(List<Asset> lotlar) =>
      state = AsyncData(state.requireValue.copyWith(assets: lotlar));
}

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _Sayac extends ProviderObserver {
  int sunucuOkuma = 0;
  int ekranYukleniyor = 0;

  @override
  void didAddProvider(ProviderBase<Object?> provider, Object? value,
      ProviderContainer container) {
    if (provider == xrayFonVerisiProvider) sunucuOkuma++;
  }

  @override
  void didUpdateProvider(ProviderBase<Object?> provider, Object? previousValue,
      Object? newValue, ProviderContainer container) {
    if (provider == xrayFonVerisiProvider &&
        newValue is AsyncValue &&
        newValue.isLoading) {
      sunucuOkuma++;
    }
    if (provider == portfoyXrayProvider &&
        newValue is AsyncValue &&
        newValue.isLoading) {
      ekranYukleniyor++;
    }
  }
}

void main() {
  setUpAll(() => DbLogger.silentInTests = true);
  tearDownAll(() => DbLogger.silentInTests = false);

  Future<(ProviderContainer, _Sayac)> ac() async {
    final sayac = _Sayac();
    final c = ProviderContainer(
      overrides: [
        portfolioProvider.overrideWith(_Portfoy.new),
        authProvider.overrideWith(_Auth.new),
      ],
      observers: [sayac],
    );
    addTearDown(c.dispose);
    await c.read(portfolioProvider.future);
    await c.read(authProvider.future);
    final dinle = c.listen(portfoyXrayProvider, (_, __) {});
    addTearDown(dinle.close);
    // Sunucu okuması (testte Supabase yok → hata) yerleşsin.
    await c.read(xrayFonVerisiProvider.future).then((_) {}, onError: (_) {});
    return (c, sayac);
  }

  test('fiyat turu: sunucu yeniden okunmaz, ekran yükleniyor görmez',
      () async {
    final (c, sayac) = await ac();
    final okuma = sayac.sunucuOkuma;
    (c.read(portfolioProvider.notifier) as _Portfoy).yaz([_fon(fiyat: 1.6)]);
    c.read(portfoyXrayProvider);
    await Future<void>.delayed(Duration.zero);
    expect(sayac.sunucuOkuma, okuma);
    expect(sayac.ekranYukleniyor, 0);
  });

  test('yeni fon kodu: sunucu yeniden okunur', () async {
    final (c, sayac) = await ac();
    final okuma = sayac.sunucuOkuma;
    (c.read(portfolioProvider.notifier) as _Portfoy)
        .yaz([_fon(), _fon(kod: 'AFT')]);
    c.read(portfoyXrayProvider);
    await Future<void>.delayed(Duration.zero);
    expect(sayac.sunucuOkuma, greaterThan(okuma));
  });
}
