import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart' show aktifLotlar;
import '../services/technical_analysis_service.dart'
    show TechnicalAnalysisService;
import 'portfolio_provider.dart';
import 'preferences_provider.dart';

// NOT (2026-10-10, Premium netleştirmesi): bu dosya eskiden ücretsiz planın
// "tek sinyal varlığı" kapısını taşıyordu (yasin 2026-10-08: "sinyal 1
// varlıkta ücretsiz"; seçim sunucuda `sinyal_varlik_secimi`, 0126). Yeni
// modelde (yasin 2026-10-10) sinyal BİLDİRİMİ paywall açıkken bütünüyle
// Premium, kapalıyken herkese; "tek varlık" kapısının konusu kalmadı ve
// seçim/şerit/taşı yolu söküldü. Tablo sunucuda kalır (eski build'ler
// yazabilir; sunucu artık okumaz). Burada yalnız iki tarafın ortak tür
// listesi yaşar.

/// Sunucunun sinyal ürettiği türler (`analyze-signals` → `ANALYZABLE`).
const kSinyalTurleri = {
  AssetType.hisse,
  AssetType.fon,
  AssetType.bes,
  AssetType.altin,
  AssetType.doviz,
  AssetType.emtia,
  AssetType.kripto,
  AssetType.eurobond,
};

bool sinyalUretilir(Asset a) =>
    kSinyalTurleri.contains(a.type) &&
    !a.isManualPrice &&
    a.ticker.trim().isNotEmpty;

/// Sinyal bildirimi kaç VARLIK için geliyor (Ar-Ge 14 Kas 02:03 #3):
/// Alarmlarım'ın sonundaki "Sinyal bildirimleri · N varlık" satırı.
///
/// Sunucunun gerçekten analiz ettiği küme: bugün sahip olunan
/// ([aktifLotlar]; satılmış pozisyon elenir, sunucu da `acikPozisyonLotlari`
/// ile eler), türü sinyal üreten ([sinyalUretilir]) ve o türde en az bir
/// gösterge seçili varlıklar. Aynı varlığın lot'ları bir sayılır (tür +
/// sembol). Saf hesap (test edilir).
int sinyalBildirimliVarlikSayisi(
    Iterable<Asset> lotlar, Set<String> Function(AssetType) gostergeler) {
  final anahtar = <String>{};
  for (final a in aktifLotlar(lotlar)) {
    if (!a.isBuy || !sinyalUretilir(a)) continue;
    if (gostergeler(a.type).isEmpty) continue;
    anahtar.add('${a.type.name}|${a.ticker.trim().toUpperCase()}');
  }
  return anahtar.length;
}

/// [sinyalBildirimliVarlikSayisi]'nın bu kullanıcıdaki değeri; satır
/// çizilmeyecekse 0. Satır yalnız Premium erişimi olana
/// ([premiumErisimProvider]; sinyal push'u paywall açıkken Premium'a
/// gider) ve sinyal bildirimleri açıkken ([signalNotificationsProvider])
/// anlamlı: kapalıysa ya da ücretsizse Alarmlarım'da bu satır çıkmaz.
final sinyalBildirimliVarlikSayisiProvider = Provider<int>((ref) {
  if (!ref.watch(premiumErisimProvider)) return 0;
  if (!ref.watch(signalNotificationsProvider)) return 0;
  final lotlar = ref.watch(portfolioProvider).valueOrNull?.assets;
  if (lotlar == null) return 0;
  final secim = ref.watch(indicatorPrefsProvider);
  return sinyalBildirimliVarlikSayisi(lotlar,
      (t) => secim[t] ?? TechnicalAnalysisService.defaultEnabledFor(t));
});
