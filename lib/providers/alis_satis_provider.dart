import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/crash_reporter.dart';
import '../services/fiyat_kaynagi.dart' show FiyatKaynagi;
import 'add_asset_form_provider.dart';

/// Bir sembolün güncel alış + satış çifti — varlık sayfası ve varlık
/// detayındaki "Bozdurursan · Alırsan · fark" satırı için (2026-10-25).
///
/// ## Neden formun kapısı
/// Satış, alışla AYNI truncgil kaydından gelmeli (fiyat kaynağı madde 1).
/// Ekleme formu bunu [SatisFiyatiOkuyucu.alisSatis] ile zaten yapıyor
/// (`PriceService.fetchQuotes`, aynı önbellek); ikinci bir okuma yolu
/// kurulsaydı iki ekran iki ayrı anın fiyatını yazabilirdi. Kapı
/// [addAssetPriceLookupProvider]'dan okunur, testte o geçersiz kılınır.
///
/// ## Ağ
/// Yurt içi kotasyonu olmayan sembol (hisse, fon, kripto, USD-kote emtia)
/// ağa hiç çıkmaz: satırı zaten gösterilmez. Olanlarda `fetchQuotes`'un
/// önbelleği ekranın kendi fiyat çağrısıyla paylaşılır; ikinci istek yok.
///
/// `null` = satır çizilmez. Hata sessiz değil (Crashlytics non-fatal) ama
/// kullanıcıya gösterilmez: satır ek bilgidir, fiyatı etkilemez.
final alisSatisProvider =
    FutureProvider.autoDispose.family<AlisSatis?, String>((ref, ticker) async {
  if (!FiyatKaynagi.yurtIciKayitli(ticker)) return null;
  final kapi = ref.watch(addAssetPriceLookupProvider);
  if (kapi is! SatisFiyatiOkuyucu) return null;
  try {
    return await (kapi as SatisFiyatiOkuyucu).alisSatis(ticker);
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'alisSatisProvider');
    return null;
  }
});
