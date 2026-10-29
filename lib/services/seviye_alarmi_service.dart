import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/seviye_alarmi.dart';
import 'crash_reporter.dart';

/// `gosterge_alarmlari` ve `cizim_alarmlari` (0170) ham kapısı —
/// [YuzdeAlarmiStore] ile aynı kalıp: satır ↔ model işi Supabase istemcisi
/// olmadan test edilir (`seviye_alarmi_test`). [tablo] iki tablodan biri.
abstract class SeviyeAlarmiStore {
  Future<List<Map<String, dynamic>>> select(String tablo, String userId);
  Future<Map<String, dynamic>> insert(String tablo, Map<String, dynamic> row);
  Future<Map<String, dynamic>> update(
      String tablo, String id, Map<String, dynamic> alanlar);
  Future<void> delete(String tablo, String id);
}

class SupabaseSeviyeAlarmiStore implements SeviyeAlarmiStore {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<List<Map<String, dynamic>>> select(String tablo, String userId) async {
    final rows = await _db
        .from(tablo)
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<Map<String, dynamic>> insert(String tablo, Map<String, dynamic> row) =>
      _db.from(tablo).insert(row).select().single();

  @override
  Future<Map<String, dynamic>> update(
          String tablo, String id, Map<String, dynamic> alanlar) =>
      _db.from(tablo).update(alanlar).eq('id', id).select().single();

  @override
  Future<void> delete(String tablo, String id) =>
      _db.from(tablo).delete().eq('id', id);
}

/// Gösterge ve çizgi alarmlarının CRUD katmanı. Değerlendirme SUNUCUDA
/// (`check-price-alerts` → `_shared/seviye_alarmi.ts`).
class SeviyeAlarmiService {
  SeviyeAlarmiService(this._store);
  static final SeviyeAlarmiService instance =
      SeviyeAlarmiService(SupabaseSeviyeAlarmiStore());

  static const gostergeTablosu = 'gosterge_alarmlari';
  static const cizimTablosu = 'cizim_alarmlari';

  final SeviyeAlarmiStore _store;

  Future<List<GostergeAlarmi>> gostergeleriGetir(String userId) async => [
        for (final r in await _store.select(gostergeTablosu, userId))
          if (GostergeAlarmi.fromMap(r) case final a?) a,
      ];

  Future<GostergeAlarmi> gostergeKur(GostergeAlarmi a) async {
    final kayit = GostergeAlarmi.fromMap(
        await _store.insert(gostergeTablosu, a.toInsertMap()));
    if (kayit == null) throw StateError('gosterge_alarmlari: bilinmeyen satır');
    return kayit;
  }

  Future<void> gostergeSil(String id) => _store.delete(gostergeTablosu, id);

  Future<List<CizimAlarmi>> cizimleriGetir(String userId) async => [
        for (final r in await _store.select(cizimTablosu, userId))
          if (CizimAlarmi.fromMap(r) case final a?) a,
      ];

  /// Yeni çizgi alarmı; aynı çizimin (çalmış) eski satırı [eski] verilirse
  /// o satır YENİDEN KURULUR (sunucuda çizim başına tek satır, 0170 benzersiz
  /// indeksi). Yeniden kurmada taraf sıfırlanır: ilk tur yalnız yazar.
  Future<CizimAlarmi> cizimKur(CizimAlarmi a, {CizimAlarmi? eski}) async {
    final Map<String, dynamic> satir;
    if (eski != null) {
      satir = await _store.update(cizimTablosu, eski.id, {
        ...a.dogruMap(),
        'label': a.label,
        'enabled': true,
        'triggered_at': null,
        'son_taraf': null,
        'tetik_fiyat': null,
        'tetik_seviye': null,
      });
    } else {
      satir = await _store.insert(cizimTablosu, a.toInsertMap());
    }
    final kayit = CizimAlarmi.fromMap(satir);
    if (kayit == null) throw StateError('cizim_alarmlari: bozuk satır');
    return kayit;
  }

  /// Çizim taşındı: doğru alanları güncellenir (tetikleyici tarafı sıfırlar).
  Future<CizimAlarmi> cizimTasi(String id, CizimAlarmi yeni) async {
    final kayit =
        CizimAlarmi.fromMap(await _store.update(cizimTablosu, id, yeni.dogruMap()));
    if (kayit == null) {
      final e = StateError('cizim_alarmlari: bozuk satır');
      CrashReporter.report(e, StackTrace.current, reason: 'cizimAlarmi.tasi');
      throw e;
    }
    return kayit;
  }

  /// Çizgi alarmının okunan adı (yasin 2026-10-29). Yalnız `label`:
  /// nöbet durumu (taraf, damga) değişmez. 0170 güncelleme ilkesi Premium
  /// ister — abonelik bitmişse sunucu reddeder, hata kullanıcıya söylenir.
  Future<CizimAlarmi> cizimEtiketi(String id, String label) async {
    final kayit = CizimAlarmi.fromMap(
        await _store.update(cizimTablosu, id, {'label': label}));
    if (kayit == null) throw StateError('cizim_alarmlari: bozuk satır');
    return kayit;
  }

  Future<void> cizimSil(String id) => _store.delete(cizimTablosu, id);
}
