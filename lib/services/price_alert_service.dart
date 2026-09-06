import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/price_alert.dart';

/// Fiyat alarmlarının CRUD katmanı.
///
/// Değerlendirme SUNUCUDA yapılır (`check-price-alerts` edge function);
/// burada yalnızca kullanıcının kurduğu kayıtlar yönetilir. Uygulama
/// açıkken çalışan bir alarm geri getirme kanalı olmazdı — asıl değer,
/// uygulama kapalıyken çalmasında.
class PriceAlertService {
  PriceAlertService._();
  static final PriceAlertService instance = PriceAlertService._();

  SupabaseClient get _db => Supabase.instance.client;

  Future<List<PriceAlert>> fetchAll(String userId) async {
    final rows = await _db
        .from('price_alerts')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => PriceAlert.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<PriceAlert> create(PriceAlert alert) async {
    final row = await _db
        .from('price_alerts')
        .insert(alert.toInsertMap())
        .select()
        .single();
    return PriceAlert.fromMap(row);
  }

  Future<void> delete(String id) async {
    await _db.from('price_alerts').delete().eq('id', id);
  }

  /// Tetiklenmiş bir alarmı yeniden kurar.
  ///
  /// Yeni kayıt açmak yerine damgayı temizler: kullanıcı aynı hedefi yeniden
  /// yazmak zorunda kalmasın.
  Future<void> rearm(String id) async {
    await _db
        .from('price_alerts')
        .update({'enabled': true, 'triggered_at': null}).eq('id', id);
  }
}
