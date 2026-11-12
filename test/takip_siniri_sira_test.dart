import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';

import 'helpers/kaynak.dart';

/// Takip sınırı art arda / liste yüklenmeden eklemede de tutar
/// (yasin 2026-11-12: "6. eklenmeye çalıştığında takip sayfası uyarıyor ama
/// aramadan ve detaydan ekleyebiliyorum"). Önceden `add` eski
/// `state.valueOrNull`'u sayıyordu: iki hızlı dokunuş aynı "4 kayıt"ı görüp
/// ikisi de geçiyordu; liste hiç yüklenmemişse boş sayılıyordu.
class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

/// Bellekte "sunucu": `build` oradan okur, `sunucuyaEkle` oraya yazar.
/// İkisi de bir mikro görev geciktirilir ki gerçek ağ sırası taklit edilsin.
class _Liste extends WatchlistNotifier {
  _Liste(this.sunucu, {this.yuklemeGecikmesi = Duration.zero});
  final List<WatchlistItem> sunucu;
  final Duration yuklemeGecikmesi;

  @override
  Future<List<WatchlistItem>> build() async {
    await Future<void>.delayed(yuklemeGecikmesi);
    return List.of(sunucu);
  }

  @override
  Future<void> sunucuyaEkle(WatchlistItem item) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    sunucu.add(item);
  }
}

WatchlistItem _oge(int i) => WatchlistItem(
      id: 'w$i',
      userId: 'u1',
      ticker: 'HISSE$i',
      name: 'Hisse $i',
      type: AssetType.hisse,
      currency: 'TRY',
      addedAt: DateTime(2026, 9, 1),
    );

ProviderContainer _kap(_Liste Function() liste) {
  final kap = ProviderContainer(overrides: [
    authProvider.overrideWith(_Auth.new),
    watchlistProvider.overrideWith(liste),
    watchlistLimitProvider.overrideWithValue(5),
  ]);
  addTearDown(kap.dispose);
  return kap;
}

void main() {
  test('art arda iki ekleme sınırı aşamaz', () async {
    final sunucu = [for (var i = 0; i < 4; i++) _oge(i)];
    final kap = _kap(() => _Liste(sunucu));
    await kap.read(authProvider.future);
    await kap.read(watchlistProvider.future);
    final n = kap.read(watchlistProvider.notifier);

    final sonuclar = await Future.wait([
      n.add(_oge(10)).then<Object>((_) => 'eklendi', onError: (Object e) => e),
      n.add(_oge(11)).then<Object>((_) => 'eklendi', onError: (Object e) => e),
    ]);

    expect(sonuclar.whereType<String>(), hasLength(1));
    expect(sonuclar.whereType<WatchlistLimitException>(), hasLength(1));
    expect(sunucu, hasLength(5));
  });

  test('liste yüklenmeden gelen ekleme dolu listeyi görür', () async {
    final sunucu = [for (var i = 0; i < 5; i++) _oge(i)];
    final kap = _kap(() => _Liste(sunucu,
        yuklemeGecikmesi: const Duration(milliseconds: 20)));
    await kap.read(authProvider.future);
    // Takip sekmesi hiç açılmadı: liste yükleniyor, değer yok.
    kap.read(watchlistProvider);

    await expectLater(kap.read(watchlistProvider.notifier).add(_oge(10)),
        throwsA(isA<WatchlistLimitException>()));
    expect(sunucu, hasLength(5));
  });

  test('sınırdan sonra sıra kilitlenmez: zaten takipteki varlık geçer',
      () async {
    final sunucu = [for (var i = 0; i < 5; i++) _oge(i)];
    final kap = _kap(() => _Liste(sunucu));
    await kap.read(authProvider.future);
    await kap.read(watchlistProvider.future);
    final n = kap.read(watchlistProvider.notifier);

    await expectLater(
        n.add(_oge(10)), throwsA(isA<WatchlistLimitException>()));
    await n.add(_oge(2)); // kotayı artırmaz → atmaz
  });

  test('paywall açıkken sınır uyarısı paywall\'u doğrudan açar', () {
    final src = ekranKaynagiSync('lib/widgets/sinir_uyarisi.dart');
    expect(src.contains('PaywallScreen.show(context, source: kaynak)'), isTrue);
    expect(src.contains('SnackBarAction'), isFalse,
        reason: 'Kaybolan "Premium" düğmesi yerine paywall açılır.');
    final takip = ekranKaynagiSync('lib/screens/watchlist_screen.dart');
    expect(takip.contains('takipSiniriUyarisi(context, ref, limit)'), isTrue,
        reason: 'Dolu kapasite kartı da aynı kuralı kullanır.');
  });
}
