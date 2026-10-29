import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/seviye_alarmi.dart';
import 'crash_reporter.dart';
import 'alarm_onbellegi.dart';

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
        for (final r in await AlarmOnbellegi.secOnbellekli(gostergeTablosu,
            userId, () => _store.select(gostergeTablosu, userId)))
          if (GostergeAlarmi.fromMap(r) case final a?) a,
      ];

  /// Cihazdaki son kopya (açılışta önce bu çizilir); yoksa `null`.
  Future<List<GostergeAlarmi>?> gostergeleriOnbellektenGetir(
      String userId) async {
    final k = await AlarmOnbellegi.oku(gostergeTablosu, userId);
    return k == null
        ? null
        : [
            for (final r in k)
              if (GostergeAlarmi.fromMap(r) case final a?) a,
          ];
  }

  Future<GostergeAlarmi> gostergeKur(GostergeAlarmi a) async {
    final satir = await _store.insert(gostergeTablosu, a.toInsertMap());
    final kayit = GostergeAlarmi.fromMap(satir);
    if (kayit == null) throw StateError('gosterge_alarmlari: bilinmeyen satır');
    await AlarmOnbellegi.satirYaz(gostergeTablosu, satir);
    return kayit;
  }

  Future<void> gostergeSil(String id) async {
    await _store.delete(gostergeTablosu, id);
    await AlarmOnbellegi.satirSil(gostergeTablosu, id);
  }

  Future<List<CizimAlarmi>> cizimleriGetir(String userId) async => [
        for (final r in await AlarmOnbellegi.secOnbellekli(cizimTablosu,
            userId, () => _store.select(cizimTablosu, userId)))
          if (CizimAlarmi.fromMap(r) case final a?) a,
      ];

  /// Cihazdaki son kopya (açılışta önce bu çizilir); yoksa `null`.
  Future<List<CizimAlarmi>?> cizimleriOnbellektenGetir(String userId) async {
    final k = await AlarmOnbellegi.oku(cizimTablosu, userId);
    return k == null
        ? null
        : [
            for (final r in k)
              if (CizimAlarmi.fromMap(r) case final a?) a,
          ];
  }

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
    await AlarmOnbellegi.satirYaz(cizimTablosu, satir);
    return kayit;
  }

  /// Çizim taşındı: doğru alanları güncellenir (tetikleyici tarafı sıfırlar).
  Future<CizimAlarmi> cizimTasi(String id, CizimAlarmi yeni) async {
    final satir = await _store.update(cizimTablosu, id, yeni.dogruMap());
    final kayit = CizimAlarmi.fromMap(satir);
    if (kayit == null) {
      final e = StateError('cizim_alarmlari: bozuk satır');
      CrashReporter.report(e, StackTrace.current, reason: 'cizimAlarmi.tasi');
      throw e;
    }
    await AlarmOnbellegi.satirYaz(cizimTablosu, satir);
    return kayit;
  }

  /// Çizgi alarmının okunan adı (yasin 2026-10-29). Yalnız `label`:
  /// nöbet durumu (taraf, damga) değişmez. 0170 güncelleme ilkesi Premium
  /// ister — abonelik bitmişse sunucu reddeder, hata kullanıcıya söylenir.
  Future<CizimAlarmi> cizimEtiketi(String id, String label) async {
    final satir = await _store.update(cizimTablosu, id, {'label': label});
    final kayit = CizimAlarmi.fromMap(satir);
    if (kayit == null) throw StateError('cizim_alarmlari: bozuk satır');
    await AlarmOnbellegi.satirYaz(cizimTablosu, satir);
    return kayit;
  }

  Future<void> cizimSil(String id) async {
    await _store.delete(cizimTablosu, id);
    await AlarmOnbellegi.satirSil(cizimTablosu, id);
  }
}
