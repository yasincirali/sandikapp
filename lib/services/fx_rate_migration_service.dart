import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'price_service.dart';

/// purchase_fx_rate = 1.0 olan non-TRY varlıklar için alım tarihindeki
/// tarihsel kuru Yahoo Finance'ten çekip Supabase'e yazar.
///
/// Her kullanıcı girişinde arka planda bir kez çalışır;
/// zaten düzeltilmiş satırları tekrar işlemez.
class FxRateMigrationService {
  static final FxRateMigrationService instance = FxRateMigrationService._();
  FxRateMigrationService._();

  static const _fxSymbolFor = {
    'USD': 'USDTRY=X',
    'EUR': 'EURTRY=X',
    'GBP': 'GBPTRY=X',
  };

  /// [userId] için migration'ı çalıştırır.
  /// Hata olursa sessizce geçer — varlıklar purchase_fx_rate=1.0 ile
  /// düzgün çalışmaya devam eder, bir sonraki girişte tekrar denenilir.
  Future<void> runFor(String userId) async {
    try {
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
