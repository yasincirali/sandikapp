import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/saatli_bildirim.dart';

/// `saatli_bildirimler` (0188) ham kapısı — `YuzdeAlarmiStore` kalıbı:
/// satır ↔ model işi Supabase istemcisi olmadan test edilir.
abstract class SaatliBildirimStore {
  Future<List<Map<String, dynamic>>> select(String userId);
  Future<Map<String, dynamic>> insert(Map<String, dynamic> row);
  Future<Map<String, dynamic>> updateSaatler(String id, List<int> saatler);
  Future<void> delete(String id);

  /// Tablo bu sunucuda var mı: tek satırlık boş okuma. Yoksa PostgREST
  /// `PGRST205` (ya da Postgres `42P01`) döner.
  Future<void> yoklama();
}

class SupabaseSaatliBildirimStore implements SaatliBildirimStore {
  SupabaseClient get _db => Supabase.instance.client;
  static const _tablo = 'saatli_bildirimler';

  @override
  Future<List<Map<String, dynamic>>> select(String userId) async {
    final rows = await _db
        .from(_tablo)
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: true);
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<Map<String, dynamic>> insert(Map<String, dynamic> row) =>
      _db.from(_tablo).insert(row).select().single();

  @override
  Future<Map<String, dynamic>> updateSaatler(String id, List<int> saatler) =>
      _db.from(_tablo).update({'saatler': saatler}).eq('id', id).select().single();

  @override
  Future<void> delete(String id) => _db.from(_tablo).delete().eq('id', id);

  @override
  Future<void> yoklama() => _db.from(_tablo).select('id').limit(1);
}

/// Sunucu tetikleyicisinin (0188) hata mesajındaki sabit işaret.
const saatliSiniriSunucuKodu = 'saatli_siniri';

/// [e] 0188 tetikleyicisinin reddi mi (Premium yok ya da sınır). 0181
/// `alarmSiniriHatasiMi` deseni: SQLSTATE 54000 başka sınırlarla ortak,
/// tanıma mesajdaki işaretle.
bool saatliSiniriHatasiMi(Object e) =>
    e is PostgrestException && e.message.contains(saatliSiniriSunucuKodu);

/// [e] "tablo yok" mu: migration bu sunucuya henüz gitmedi. PostgREST
/// şema önbelleğinde olmayan tablo `PGRST205`, doğrudan Postgres `42P01`.
bool tabloYokHatasiMi(Object e) =>
    e is PostgrestException && (e.code == 'PGRST205' || e.code == '42P01');

/// Saatli bildirimlerin CRUD katmanı. Gönderim SUNUCUDA
/// (`saatli-bildirim`); burada yalnız kullanıcının kurduğu kayıtlar.
class SaatliBildirimService {
  SaatliBildirimService(this._store);
  static final SaatliBildirimService instance =
      SaatliBildirimService(SupabaseSaatliBildirimStore());

  final SaatliBildirimStore _store;

  /// Tablo var mı. Yalnız "tablo yok" hatası `false`; başka hata yukarı
  /// atılır (çağıran raporlar ve yine gizler).
  Future<bool> tabloVarMi() async {
    try {
      await _store.yoklama();
      return true;
    } catch (e) {
      if (tabloYokHatasiMi(e)) return false;
      rethrow;
    }
  }

  Future<List<SaatliBildirim>> fetchAll(String userId) async =>
      (await _store.select(userId)).map(SaatliBildirim.fromMap).toList();

  Future<SaatliBildirim> create(SaatliBildirim b) async =>
      SaatliBildirim.fromMap(await _store.insert(b.toInsertMap()));

  Future<SaatliBildirim> saatleriGuncelle(String id, List<int> saatler) async =>
      SaatliBildirim.fromMap(await _store.updateSaatler(id, saatler));

  Future<void> delete(String id) => _store.delete(id);
}
