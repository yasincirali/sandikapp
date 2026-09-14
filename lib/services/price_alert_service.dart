import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/price_alert.dart';

/// `price_alerts` tablosuna giden ham kapı.
///
/// Servisin test edilebilmesi için satır düzeyindeki dört işlem buradan
/// geçer; üretimde [SupabasePriceAlertStore], testte sahte bir kapı.
/// Servisin kendi işi (satır ↔ model eşlemesi, "yeniden kur" yamasının
/// şekli) böylece Supabase istemcisi olmadan doğrulanabilir (Faz 3.17).
abstract class PriceAlertStore {
  Future<List<Map<String, dynamic>>> select(String userId);
  Future<Map<String, dynamic>> insert(Map<String, dynamic> row);
  Future<void> delete(String id);
  Future<void> update(String id, Map<String, dynamic> patch);
}

class SupabasePriceAlertStore implements PriceAlertStore {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<List<Map<String, dynamic>>> select(String userId) async {
    final rows = await _db
        .from('price_alerts')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> row) =>
      _db.from('price_alerts').insert(row).select().single();

  @override
  Future<void> delete(String id) =>
      _db.from('price_alerts').delete().eq('id', id);

  @override
  Future<void> update(String id, Map<String, dynamic> patch) =>
      _db.from('price_alerts').update(patch).eq('id', id);
}

/// Fiyat alarmlarının CRUD katmanı.
///
/// Değerlendirme SUNUCUDA yapılır (`check-price-alerts` edge function);
/// burada yalnızca kullanıcının kurduğu kayıtlar yönetilir. Uygulama
/// açıkken çalışan bir alarm geri getirme kanalı olmazdı — asıl değer,
/// uygulama kapalıyken çalmasında.
class PriceAlertService {
  PriceAlertService(this._store);
  static final PriceAlertService instance =
      PriceAlertService(SupabasePriceAlertStore());

  final PriceAlertStore _store;

  /// "Yeniden kur" yaması — tek yerde, test edilebilir.
  static const Map<String, dynamic> rearmPatch = {
    'enabled': true,
    'triggered_at': null,
  };

  Future<List<PriceAlert>> fetchAll(String userId) async {
    final rows = await _store.select(userId);
    return rows.map(PriceAlert.fromMap).toList();
  }

  Future<PriceAlert> create(PriceAlert alert) async {
    final row = await _store.insert(alert.toInsertMap());
    return PriceAlert.fromMap(row);
  }

  Future<void> delete(String id) => _store.delete(id);

  /// Tetiklenmiş bir alarmı yeniden kurar.
  ///
  /// Yeni kayıt açmak yerine damgayı temizler: kullanıcı aynı hedefi yeniden
  /// yazmak zorunda kalmasın.
  Future<void> rearm(String id) => _store.update(id, rearmPatch);
}
