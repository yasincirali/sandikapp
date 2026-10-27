import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/yuzde_alarmi.dart';

/// `yuzde_alarmlari` tablosuna (0169) giden ham kapı — [PriceAlertStore]
/// ile aynı kalıp: servisin satır ↔ model işi Supabase istemcisi olmadan
/// test edilir (`yuzde_alarmi_test`).
abstract class YuzdeAlarmiStore {
  Future<List<Map<String, dynamic>>> select(String userId);
  Future<Map<String, dynamic>> insert(Map<String, dynamic> row);
  Future<void> delete(String id);
}

class SupabaseYuzdeAlarmiStore implements YuzdeAlarmiStore {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<List<Map<String, dynamic>>> select(String userId) async {
    final rows = await _db
        .from('yuzde_alarmlari')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> row) =>
      _db.from('yuzde_alarmlari').insert(row).select().single();

  @override
  Future<void> delete(String id) =>
      _db.from('yuzde_alarmlari').delete().eq('id', id);
}

/// Yüzde alarmlarının CRUD katmanı. Değerlendirme SUNUCUDA
/// (`check-price-alerts` → `_shared/yuzde_alarmi.ts`); burada yalnız
/// kullanıcının kurduğu kayıtlar. "Yeniden kur" yok: alarm ertesi gün
/// kendiliğinden nöbete döner.
class YuzdeAlarmiService {
  YuzdeAlarmiService(this._store);
  static final YuzdeAlarmiService instance =
      YuzdeAlarmiService(SupabaseYuzdeAlarmiStore());

  final YuzdeAlarmiStore _store;

  Future<List<YuzdeAlarmi>> fetchAll(String userId) async {
    final rows = await _store.select(userId);
    return rows.map(YuzdeAlarmi.fromMap).toList();
  }

  Future<YuzdeAlarmi> create(YuzdeAlarmi alarm) async =>
      YuzdeAlarmi.fromMap(await _store.insert(alarm.toInsertMap()));

  Future<void> delete(String id) => _store.delete(id);
}
