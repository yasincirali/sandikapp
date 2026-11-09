import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/services/alarm_onbellegi.dart';
import 'package:portfoy_takip/services/price_alert_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Alarm listelerinin cihaz kopyası (Ar-Ge 29 Eki 20:45 #3): ağ hatasında
/// son bilinen, açılışta önce kopya, yatay çizgi eşitlemesi yalnız sunucu
/// listesine güvenir.
class _Store implements PriceAlertStore {
  List<Map<String, dynamic>> satirlar = [];
  bool hata = false;
  int sayac = 0;

  @override
  Future<List<Map<String, dynamic>>> select(String userId) async {
    if (hata) throw Exception('ağ yok');
    return [for (final r in satirlar) {...r}];
  }

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> row) async {
    final r = {
      ...row,
      'id': 'n${sayac++}',
      'enabled': true,
      'created_at': '2026-10-29T10:00:00Z'
    };
    satirlar.insert(0, r);
    return r;
  }

  @override
  Future<void> delete(String id) async =>
      satirlar.removeWhere((r) => r['id'] == id);

  @override
  Future<void> update(String id, Map<String, dynamic> patch) async {}
}

Map<String, dynamic> _satir(String id) => {
      'id': id,
      'user_id': 'u1',
      'symbol': 'ALTIN_GRAM',
      'label': 'Gram altın',
      'target_price': 4300,
      'direction': 'above',
      'enabled': true,
      'created_at': '2026-10-01T10:00:00Z',
    };

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 't@example.com',
        displayName: 'T',
        createdAt: DateTime(2026, 1, 1),
      );
}

void main() {
  late _Store store;
  late PriceAlertService svc;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AlarmOnbellegi.bayat.value = false;
    store = _Store();
    svc = PriceAlertService(store);
  });

  test('ağ hatasında son bilinen liste döner ve bayat yanar', () async {
    store.satirlar = [_satir('a')];
    expect((await svc.fetchAll('u1')).single.id, 'a');
    expect(AlarmOnbellegi.bayat.value, isFalse);
    store.hata = true;
    expect((await svc.fetchAll('u1')).single.id, 'a');
    expect(AlarmOnbellegi.bayat.value, isTrue);
  });

  test('kopya yoksa hata eskisi gibi fırlar', () async {
    store.hata = true;
    expect(() => svc.fetchAll('u1'), throwsException);
  });

  test('kurma ve silme kopyayı da günceller; çıkışta temizlenir', () async {
    store.satirlar = [_satir('a')];
    await svc.fetchAll('u1');
    final yeni = await svc.create((await svc.fetchAll('u1')).single);
    await svc.delete('a');
    final kopya = await svc.onbellektenGetir('u1');
    expect(kopya!.map((a) => a.id), [yeni.id]);
    await AlarmOnbellegi.temizle();
    expect(await svc.onbellektenGetir('u1'), isNull);
  });

  test('sağlayıcı önce kopyayı verir, sunucu gelince değiştirir; '
      'yuklendi yalnız sunucu listesinde', () async {
    store.satirlar = [_satir('eski')];
    await svc.fetchAll('u1');
    store.satirlar = [_satir('taze')];
    final c = ProviderContainer(overrides: [
      authProvider.overrideWith(_Auth.new),
      priceAlertServiceProvider.overrideWithValue(svc),
    ]);
    addTearDown(c.dispose);
    await c.read(authProvider.future);
    final ilk = await c.read(priceAlertsProvider.future);
    expect(ilk.single.id, 'eski');
    expect(c.read(priceAlertsProvider.notifier).yuklendi, isFalse);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(priceAlertsProvider).value!.single.id, 'taze');
    expect(c.read(priceAlertsProvider.notifier).yuklendi, isTrue);
  });
}
