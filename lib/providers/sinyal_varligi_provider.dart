import '../models/asset.dart';
import '../models/asset_type.dart';

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
