import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/services/price_alert_service.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart' show alarmSembolu;

/// `priceAlertsProvider` — üç yüzeyin (alarm listesi, varlık şeridi,
/// Portföy rozeti) okuduğu tek kaynak. Yazmalar sunucuya gider, state
/// yerinde güncellenir; yeniden çekme yok.
class _SahteKapi implements PriceAlertStore {
  final rows = <Map<String, dynamic>>[
    {
      'id': 'a1', 'user_id': 'u1', 'symbol': 'THYAO.IS', 'label': 'THY',
      'target_price': 300, 'direction': 'above', 'enabled': true,
    },
    {
      'id': 'a2', 'user_id': 'u1', 'symbol': 'THYAO.IS', 'label': 'THY',
      'target_price': 250, 'direction': 'below', 'enabled': true,
      'triggered_at': '2026-09-01T00:00:00Z',
    },
    {
      'id': 'a3', 'user_id': 'u1', 'symbol': 'ALTIN_GRAM', 'label': 'Altın',
      'target_price': 5000, 'direction': 'above', 'enabled': true,
    },
  ];
  int selectSayisi = 0;

  @override
  Future<List<Map<String, dynamic>>> select(String userId) async {
    selectSayisi++;
    return rows.where((r) => r['user_id'] == userId).toList();
  }

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> row) async {
    final full = {...row, 'id': 'a${rows.length + 1}', 'enabled': true};
    rows.add(full);
    return full;
  }

  @override
  Future<void> delete(String id) async => rows.removeWhere((r) => r['id'] == id);

  @override
  Future<void> update(String id, Map<String, dynamic> patch) async {
    final r = rows.firstWhere((r) => r['id'] == id);
    r.addAll(patch);
  }
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

void main() {
  late _SahteKapi kapi;
  late ProviderContainer c;

  setUp(() {
    kapi = _SahteKapi();
    c = ProviderContainer(overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      priceAlertServiceProvider.overrideWithValue(PriceAlertService(kapi)),
    ]);
    addTearDown(c.dispose);
  });

  Future<List<PriceAlert>> yukle() async {
    // Auth çözülene kadar bekle.
    await c.read(authProvider.future);
    return c.read(priceAlertsProvider.future);
  }

  test('kullanıcının alarmlarını yükler; sembol filtresi ayrışır', () async {
    final liste = await yukle();
    expect(liste.length, 3);
    expect(c.read(symbolAlertsProvider('THYAO.IS')).length, 2);
    expect(c.read(symbolAlertsProvider('ALTIN_GRAM')).length, 1);
    expect(c.read(symbolAlertsProvider('YOK')), isEmpty);
  });

  test('create listeye ekler, sunucuya tek istek', () async {
    await yukle();
    final n = c.read(priceAlertsProvider.notifier);
    await n.create(PriceAlert(
      id: '',
      userId: 'u1',
      symbol: 'GARAN.IS',
      label: 'Garanti',
      targetPrice: 120,
      direction: 'above',
      enabled: true,
      createdAt: DateTime(2026),
    ));
    expect(c.read(priceAlertsProvider).valueOrNull!.length, 4);
    expect(c.read(symbolAlertsProvider('GARAN.IS')).single.id, 'a4');
    expect(kapi.selectSayisi, 1, reason: 'yeniden çekme yok');
  });

  test('delete ve rearm state\'i yerinde günceller', () async {
    await yukle();
    final n = c.read(priceAlertsProvider.notifier);
    await n.delete('a1');
    expect(c.read(symbolAlertsProvider('THYAO.IS')).map((a) => a.id), ['a2']);
    expect(c.read(symbolAlertsProvider('THYAO.IS')).single.isActive, isFalse);
    await n.rearm('a2');
    expect(c.read(symbolAlertsProvider('THYAO.IS')).single.isActive, isTrue);
    expect(kapi.rows.firstWhere((r) => r['id'] == 'a2')['triggered_at'],
        isNull);
    expect(kapi.selectSayisi, 1);
  });

  test('alarmSembolu: altın alt kategori, hisse ticker, manuel yok', () {
    expect(alarmSembolu('THYAO.IS', null), 'THYAO.IS');
    expect(alarmSembolu('', 'ALTIN_GRAM'), 'ALTIN_GRAM');
    expect(alarmSembolu('  ', null), isNull);
  });
}
