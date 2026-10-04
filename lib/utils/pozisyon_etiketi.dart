import '../l10n/generated/app_localizations.dart';
import '../models/asset_type.dart';
import '../models/position.dart';

/// `positionKey` insan-okunur etikete çevrilir.
///
/// Anahtar `type|core|currency` biçimindedir (bkz. `positionKey`); `core`
/// altında `sub:` öneki altın/döviz alt kategorisini, `name:` öneki
/// ticker'sız varlığın adını taşır. Ham anahtarı ekrana basmak
/// "altin|sub:çeyrek|TRY" gibi bir şey gösterirdi.
///
/// **Neden ortak dosyada (2026-10-04):** eskiden Performans ekranının part'ında
/// (`_positionLabel`) yaşıyordu; tür dökümü kartı ve Özet'in en iyi/en zayıf
/// satırları okuyordu. Bugün kartının "en çok oynayan"ı da aynı adı yazmalı
/// (Özet GÜNLÜK'te "THYAO" diyen, kartta "THYAO.IS" demesin). Kopyalamak bu
/// projede ons→gram formülünü beş yere dağıtan sınıf hatanın aynısıydı.
String pozisyonEtiketi(String key, AssetType type, AppLocalizations l) {
  final parts = key.split('|');
  var core = parts.length > 1 ? parts[1] : key;
  if (core.startsWith('sub:')) {
    core = core.substring(4);
  } else if (core.startsWith('name:')) {
    core = core.substring(5);
  } else {
    // Sembol çekirdeği: `ARDYZ.IS` / `TEFAS:AFT` / `KRIPTO:BTC` → kod
    // (`pozisyonKodu`; 2026-09-29 emülatör testinde GÜNLÜK'ün "en çok
    // hareket eden"i ham `ARDYZ.IS` yazıyordu).
    core = pozisyonKodu(core);
  }
  if (core.isEmpty) return type.labelOf(l);
  // Döviz: ham Yahoo sembolü ("EURTRY=X") müşteriye sızıyordu (emülatör
  // testi 2026-10-01, GÜNLÜK "en çok hareket eden"). Piyasa şeridiyle aynı
  // adlar (`piyasa_seridi`: Dolar / Euro), sterlin de eklendi.
  if (type == AssetType.doviz) {
    final kod = core.toUpperCase().replaceAll('TRY=X', '');
    final ad = switch (kod) {
      'USD' => l.marketDollar,
      'EUR' => l.marketEuro,
      'GBP' => l.marketPound,
      _ => null,
    };
    if (ad != null) return ad;
  }
  // Alt kategoriler küçük harfle saklanır (`positionKey`), ticker'lar büyük.
  // İlk harfi büyüterek "çeyrek" → "Çeyrek" yapıyoruz; ticker'a dokunmaz.
  return core.length > 1
      ? core[0].toUpperCase() + core.substring(1)
      : core.toUpperCase();
}
