import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/pref_keys.dart';
import 'price_service.dart';
import 'fiyat_kaynagi.dart';

/// purchase_fx_rate = 1.0 olan non-TRY varlıklar için alım tarihindeki
/// tarihsel kuru Yahoo Finance'ten çekip Supabase'e yazar.
///
/// Arka planda çalışır; zaten düzeltilmiş satırları tekrar işlemez.
///
/// 2026-09: her açılışta değil, kullanıcı başına GÜNDE BİR kez koşar
/// (`PrefKeys.fxMigrationLastRunMs`). Sorgu ucuz ama her soğuk başlangıçta
/// bir Supabase turu atmak, sıfır satır döneceğini bildiğimiz bir iş için
/// gereksizdi. Günlük tekrar, tarihsel kur bulunamayan varlıklar için
/// yeniden deneme davranışını korur.
class FxRateMigrationService {
  static final FxRateMigrationService instance = FxRateMigrationService._();
  FxRateMigrationService._();

  static const _fxSymbolFor = {
    'USD': FiyatKaynagi.usdTry,
    'EUR': 'EURTRY=X',
    'GBP': 'GBPTRY=X',
  };

  /// [userId] için migration'ı çalıştırır.
  /// Hata olursa sessizce geçer — varlıklar purchase_fx_rate=1.0 ile
  /// düzgün çalışmaya devam eder, bir sonraki girişte tekrar denenilir.
  static const _throttle = Duration(hours: 24);

  Future<void> runFor(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${PrefKeys.fxMigrationLastRunMs}_$userId';
      final last = prefs.getInt(key) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < _throttle.inMilliseconds) return;
      await prefs.setInt(key, now);

      final db = Supabase.instance.client;

      // purchase_fx_rate = 1.0 olan non-TRY varlıkları çek
      final rows = await db
          .from('assets')
          .select('id, currency, added_date, purchase_fx_rate')
          .eq('user_id', userId)
          .neq('currency', 'TRY')
          .eq('purchase_fx_rate', 1.0);

      if (rows.isEmpty) return;

      if (kDebugMode) {
        debugPrint('[FxMigration] ${rows.length} varlık güncelleniyor...');
      }

      // Tarih → kur önbelleği (aynı gün/para birimi için tek istek)
      final cache = <String, double>{};

      for (final row in rows) {
        final id = row['id'] as String;
        final currency = (row['currency'] as String).toUpperCase();
        final addedDateStr = row['added_date'] as String?;
        if (addedDateStr == null) continue;

        final fxSymbol = _fxSymbolFor[currency];
        if (fxSymbol == null) continue; // Desteklenmeyen para birimi

        final addedDate = DateTime.parse(addedDateStr);
        final cacheKey = '$fxSymbol-${addedDate.year}-${addedDate.month}-${addedDate.day}';

        double? rate = cache[cacheKey];
        if (rate == null) {
          rate = await PriceService.instance.fetchHistoricalFxRate(fxSymbol, addedDate);
          if (rate != null && rate > 1.0) {
            cache[cacheKey] = rate;
          }
        }

        if (rate == null || rate <= 1.0) {
          // Tarihsel veri bulunamadı — bu varlığı atla, sonraki girişte tekrar dene
          if (kDebugMode) debugPrint('[FxMigration] $id için kur bulunamadı ($fxSymbol $addedDate)');
          continue;
        }

        await db
            .from('assets')
            .update({'purchase_fx_rate': rate})
            .eq('id', id);

        if (kDebugMode) {
          debugPrint('[FxMigration] $id → purchase_fx_rate=$rate ($currency @ $addedDate)');
        }
      }

      if (kDebugMode) debugPrint('[FxMigration] Tamamlandı.');
    } catch (e) {
      if (kDebugMode) debugPrint('[FxMigration] Hata (sessizce geçildi): $e');
    }
  }
}
