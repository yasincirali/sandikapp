import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/services/price_alert_service.dart';

/// `PriceAlertService` — Supabase istemcisi olmadan (Faz 3.17).
///
/// Servisin işi satırla model arasındaki eşleme ve "yeniden kur" yamasının
/// şekli; kapı ([PriceAlertStore]) sahtelenir. Değerlendirme sunucuda
/// olduğu için burada tetikleme mantığı yoktur — yalnızca kayıt yönetimi.
class _SahteKapi implements PriceAlertStore {
  final rows = <Map<String, dynamic>>[];
  final silinen = <String>[];
  final yamalar = <(String, Map<String, dynamic>)>[];

  @override
  Future<List<Map<String, dynamic>>> select(String userId) async =>
      rows.where((r) => r['user_id'] == userId).toList();

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> row) async {
    final full = {
      ...row,
      'id': 'a${rows.length + 1}',
      'enabled': true,
      'created_at': '2026-09-14T10:00:00Z',
    };
    rows.add(full);
    return full;
  }

  @override
  Future<void> delete(String id) async => silinen.add(id);

  @override
  Future<void> update(String id, Map<String, dynamic> patch) async =>
      yamalar.add((id, patch));
}

void main() {
  late _SahteKapi kapi;
  late PriceAlertService servis;

  setUp(() {
    kapi = _SahteKapi();
    servis = PriceAlertService(kapi);
  });

  test('create yalnızca ekleme alanlarını gönderir, dönen satırı modele çevirir',
      () async {
    final a = await servis.create(PriceAlert(
      id: '',
      userId: 'u1',
      symbol: 'THYAO.IS',
      label: 'THY',
      targetPrice: 320.5,
      direction: 'above',
      enabled: true,
      createdAt: _sabit,
    ));
    // Sunucu üretir: id, enabled, created_at, triggered_at.
    expect(kapi.rows.single.keys,
        containsAll(['user_id', 'symbol', 'label', 'target_price', 'direction']));
    expect(kapi.rows.single.containsKey('triggered_at'), isFalse);
    expect(a.id, 'a1');
    expect(a.isActive, isTrue);
    expect(a.targetPrice, 320.5);
  });

  test('fetchAll yalnızca kullanıcının satırlarını modele çevirir', () async {
    kapi.rows.addAll([
      {'id': '1', 'user_id': 'u1', 'symbol': 'X', 'target_price': 1, 'enabled': true},
      {'id': '2', 'user_id': 'u2', 'symbol': 'Y', 'target_price': 2, 'enabled': true},
    ]);
    final liste = await servis.fetchAll('u1');
    expect(liste.map((a) => a.id), ['1']);
  });

  test('rearm damgayı temizler ve alarmı açar — yeni kayıt açmaz', () async {
    await servis.rearm('a9');
    expect(kapi.yamalar.single.$1, 'a9');
    expect(kapi.yamalar.single.$2, {'enabled': true, 'triggered_at': null});
    expect(kapi.rows, isEmpty);
  });

  test('delete kimliği kapıya iletir', () async {
    await servis.delete('a3');
    expect(kapi.silinen, ['a3']);
  });

  group('PriceAlert.fromMap dayanıklılığı', () {
    test('bilinmeyen yön "above" sayılır, eksik alanlar çökertmez', () {
      final a = PriceAlert.fromMap({'id': 1, 'user_id': 'u', 'direction': 'sideways'});
      expect(a.isAbove, isTrue);
      expect(a.symbol, '');
      expect(a.targetPrice, 0);
      expect(a.enabled, isFalse);
    });

    test('tetiklenmiş alarm aktif değildir', () {
      final a = PriceAlert.fromMap({
        'id': 1,
        'user_id': 'u',
        'enabled': true,
        'triggered_at': '2026-09-14T09:00:00Z',
      });
      expect(a.isActive, isFalse);
      expect(a.triggeredAt, isNotNull);
    });
  });
}

final _sabit = DateTime.utc(2026, 9, 14);
