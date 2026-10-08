import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';

enum AssetType {
  // Kategori renkleri — Sandık marka ailesine sadık, canlı ama karakteri
  // bozmayan sıcak/nötr tonlar. Her kategori grafikte ve etikette birbirinden
  // kolay ayırt edilebilir olmalı; gain/loss (yeşil/kırmızı) semantik
  // renkleriyle çakışmamalı.
  hisse('Hisse', Icons.show_chart_rounded, Sandik.amber, 'TRY'),      // Amber — marka CTA
  fon('Fon', Icons.pie_chart_rounded, Sandik.info, 'TRY'),           // Sky blue — nötr/finansal
  doviz('Döviz', Icons.attach_money_rounded, Color(0xFF7EC8A9), 'USD'),     // Soft mint — gain'den ayrık
  altin('Altın', Icons.star_rounded, Sandik.gold, 'TRY'),            // Gold — altın karakteri
  emtia('Emtia', Icons.inventory_2_rounded, Color(0xFFC97B4F), 'USD'),      // Copper — emtia sıcaklığı
  // Orkide — mevcut altı renge ve gain/loss'a uzak (2026-09-25 kripto planı).
  // Varsayılan para birimi TRY: fiyat sunucuda TL paritesinden (ya da
  // USDT × USDTTRY) hesaplanır, maliyet de TL girilir (Türkiye'de alımların
  // çoğu TL paritesinden). Sıra `diger`'in ÖNÜNDE: `values` döngüleri
  // (filtre çipi, tür dökümü) "Diğer"i hep sonda gösteriyor.
  kripto('Kripto', Icons.currency_bitcoin_rounded, Color(0xFFD47FC4), 'TRY'),
  // Sözleşmeli türler (2026-09-30, çalışma seçenek M2 + B3). Sıra `diger`in
  // ÖNÜNDE (bkz. kripto notu). İkisi de TL: v1'de döviz mevduatı yok.
  // Fiyatlama: [fiyatlamaTuru].
  mevduat('Mevduat', Icons.account_balance_rounded, Sandik.mevduat, 'TRY'),
  bes('BES', Icons.savings_rounded, Sandik.bes, 'TRY'),
  // Eurobond (2026-10-08, `eurobond` bayrağı). Çivit — fon mavisinden ve
  // diğer menekşesinden ayrık. Varsayılan USD: Hazine eurobondlarının
  // çoğu dolar; miktar NOMİNALDİR, fiyat nominalin yüzdesi/100 (bkz.
  // `lib/models/eurobond.dart`). Sıra `diger`in ÖNÜNDE (kripto notu).
  eurobond('Eurobond', Icons.receipt_long_rounded, Color(0xFF6C7FD8), 'USD'),
  diger('Diğer', Icons.more_horiz_rounded, Color(0xFF8D7BE0), 'TRY');      // Soft violet — nötr, ayrık

  const AssetType(
      this.label, this.icon, this.color, this.defaultCurrency);

  final String label;
  final IconData icon;

  /// Kategori rengi — DOLGU ve nokta/şerit için. Metin ya da ikon olarak
  /// kullanılacaksa [onSurface].
  final Color color;
  final String defaultCurrency;

  /// Light zeminde ikon/metin olarak okunabilen ton.
  ///
  /// Kategori renkleri koyu marka zemini için seçildi; light zeminde yedisi
  /// de AA altında kalıyordu (ölçüm 2026-08-09: altın 1,52:1). Arkasında
  /// %12-15 alfa dolgu olan rozetlerde bu sorun değil, ama çıplak ikon ve
  /// tür etiketi metninde okunmuyordu. Ton aynı, yalnızca açıklık kısılır —
  /// kategori kimliği (amber = hisse, mavi = fon) korunur.
  /// `asset_type_light_contrast_test` her türü light `surface1` üstünde
  /// ≥ 4,5:1'e bağlar.
  Color onSurface(BuildContext context) =>
      context.isLight ? onLightSurface : color;

  /// [onSurface]'in light dalı — test edilebilsin diye `BuildContext`'siz.
  Color get onLightSurface {
    // 0,28: amber/gold gibi sıcak, parlak tonların light zeminde 4,5:1'e
    // ulaştığı en yüksek açıklık (0,32'de altın 4,03:1 kalıyordu).
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(hsl.lightness > 0.28 ? 0.28 : hsl.lightness)
        .toColor();
  }

  /// Ekranda görünen tür adı — dile göre (3.20).
  ///
  /// [label] TÜRKÇE kalır ve DEĞİŞMEZ: bildirim/özet metinleri, paylaşım
  /// kartı ve sunucu tarafı onu kullanıyor; ayrıca alt kategori
  /// karşılaştırmalarında (`_subCategory == g.label`) veri değeri gibi
  /// davranıyor. Görüntüleme yüzeyleri bunu çağırır.
  String labelOf(AppLocalizations l) => switch (this) {
        AssetType.hisse => l.assetTypeStock,
        AssetType.fon => l.assetTypeFund,
        AssetType.doviz => l.assetTypeFx,
        AssetType.altin => l.assetTypeGold,
        AssetType.emtia => l.assetTypeCommodity,
        AssetType.kripto => l.assetTypeCrypto,
        AssetType.mevduat => l.assetTypeDeposit,
        AssetType.bes => l.assetTypePension,
        AssetType.eurobond => l.assetTypeEurobond,
        AssetType.diger => l.assetTypeOther,
      };

  /// Sembol alanının ipucu — dile göre.
  String tickerHintOf(AppLocalizations l) => switch (this) {
        AssetType.hisse => l.tickerHintStock,
        AssetType.fon => l.tickerHintFund,
        AssetType.doviz => l.tickerHintFx,
        AssetType.altin => l.tickerHintGold,
        AssetType.emtia => l.tickerHintCommodity,
        AssetType.kripto => l.tickerHintCrypto,
        AssetType.mevduat => l.tickerHintDeposit,
        AssetType.bes => l.tickerHintPension,
        AssetType.eurobond => l.tickerHintEurobond,
        AssetType.diger => l.tickerHintOther,
      };

  /// Fiyat ve seri motorları bu türü hangi tür GİBİ fiyatlar.
  ///
  /// ## Neden (2026-09-30, 0058 dersi)
  /// Mevduat ilk sürümünde her motora "mevduat hariç" dalı eklemişti ve
  /// silinme sebebi buydu. Mevduat ve BES yeni bir fiyatlama biçimi DEĞİL:
  /// ikisi de **birim değerli** (NAV) varlıktır — miktar pay, fiyat pay
  /// başına TL. Fonla aynı yoldan fiyatlanırlar; hangi kaynaktan
  /// beslendiklerine sembol öneki karar verir (`TEFAS:` → TEFAS emeklilik
  /// fonu, `MEVDUAT:` → sözleşmeden hesaplanan birim değer; bkz.
  /// `FiyatKaynagi`).
  ///
  /// Kural: fiyat/seri/kotasyon yolundaki tür soruları [type] yerine bunu
  /// sorar; görünüm (dağılım, filtre, etiket, renk) [type]'ı sorar.
  AssetType get fiyatlamaTuru => switch (this) {
        AssetType.mevduat || AssetType.bes => AssetType.fon,
        _ => this,
      };

  /// Sözleşmeden yönetilen tür mü (faiz/vade ya da katkı planı)?
  ///
  /// Bu türler genel Varlık Ekle formundan (miktar × fiyat) girilmez; kendi
  /// formları ve varlık sayfasındaki sözleşme kartı vardır.
  bool get sozlesmeli => this == AssetType.mevduat || this == AssetType.bes;

  /// Varlık Ekle tür çiplerinin sırası (kullanıcı kararı 2026-09-25):
  /// Hisse, Döviz, Altın, Fon, Kripto, Emtia, Diğer.
  ///
  /// Enum sırasından AYRI tutuldu: `values` filtre çiplerini, tür
  /// dökümlerini ve sinyal ayarlarını sıralıyor; istek yalnız ekleme
  /// sayfasıydı. Yeni tür eklenirse buraya da yazılmalı — unutulursa
  /// seçicide hiç görünmez (`asset_type_ekleme_sirasi_test` yakalar).
  static const List<AssetType> eklemeSirasi = [
    hisse,
    doviz,
    altin,
    fon,
    // Mevduat ve BES fonun yanında (2026-09-30): "param nerede duruyor"
    // sorusunun birikim ayağı; kripto/emtia/diğer daha seyrek seçilir.
    mevduat,
    bes,
    // Eurobond (2026-10-08): döviz birikiminin sabit getirili ayağı;
    // `eurobond` bayrağı kapalıyken ekleme sayfası bunu süzer.
    eurobond,
    kripto,
    emtia,
    diger,
  ];

  /// Bilinmeyen tür → `diger`. Kaldırılan 'mevduat' (2026-09-14) da buraya
  /// düşer; 0058 migrasyonu eski satırları sunucuda zaten 'diger' yapar.
  static AssetType fromString(String value) => AssetType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => AssetType.diger,
      );
}

/// Kripto sembol öneki — `assets.ticker` = `KRIPTO:BTC`.
///
/// `TEFAS:` gibi: kaynak sembolden okunur ve Yahoo'ya DÜŞMEZ. Fiyatı sunucu
/// çeker (`kripto_fiyat`, 0074); sunucudaki karşılığı
/// `supabase/functions/_shared/kripto.ts` `KRIPTO_ONEKI`.
const String kriptoOneki = 'KRIPTO:';

final RegExp _kriptoKodDeseni = RegExp(r'^[A-Z0-9]{2,15}$');

/// `KRIPTO:btc` → `BTC`; kripto sembolü değilse `null`.
String? kriptoKodu(String ticker) {
  final s = ticker.trim().toUpperCase();
  if (!s.startsWith(kriptoOneki)) return null;
  final kod = s.substring(kriptoOneki.length);
  return _kriptoKodDeseni.hasMatch(kod) ? kod : null;
}

/// `BTC` → `KRIPTO:BTC`.
String kriptoSembolu(String kod) => '$kriptoOneki${kod.trim().toUpperCase()}';

/// Mevduat sembol öneki — `assets.ticker` = `MEVDUAT:<sözleşme id>`.
///
/// Mevduatın piyasa fiyatı yoktur: birim değeri sözleşmenin dönemlerinden
/// hesaplanır (`mevduat_hesabi.dart`). Önek, `PriceService`'in kotasyon ve
/// seri kapılarında bu sembolü Yahoo'ya göndermeden sözleşmeye yönlendirir;
/// tıpkı `TEFAS:` ve `KRIPTO:` gibi. Sunucu eşi
/// `leaderboard-snapshot` › `MEVDUAT_ONEKI`.
const String mevduatOneki = 'MEVDUAT:';

/// `MEVDUAT:<id>` → sözleşme id'si; mevduat sembolü değilse `null`.
String? mevduatSozlesmeId(String ticker) {
  final s = ticker.trim();
  if (!s.toUpperCase().startsWith(mevduatOneki)) return null;
  final id = s.substring(mevduatOneki.length).trim().toLowerCase();
  return id.isEmpty ? null : id;
}

/// Sözleşme id'si → `MEVDUAT:<id>`.
String mevduatSembolu(String sozlesmeId) =>
    '$mevduatOneki${sozlesmeId.trim().toLowerCase()}';

/// TEFAS fon sembol öneki — `assets.ticker` = `TEFAS:AFT`.
///
/// Fiyat servisi fonu YALNIZCA bu önekten tanır (`PriceService.fetchQuotes`
/// `tefasList`); öneksiz kod Yahoo'ya düşer.
const String tefasOneki = 'TEFAS:';

/// TEFAS fon kodu: üç büyük harf/rakam (AFT, TTE, IPB…). Sunucu eşi
/// `leaderboard-snapshot` › `TEFAS_KODU`.
final RegExp _tefasKodDeseni = RegExp(r'^[A-Z0-9]{3}$');

/// Varlığın KANONİK sembolü — fiyat, seri ve kimlik (`positionKey`,
/// "Portföyünde" rozeti) hep bu biçimle çalışır.
///
/// ## Neden (emülatör bulgusu #2, 2026-09-29)
/// Eski fon kayıtları kodu öneksiz taşıyor (`AFT`; CSV içe aktarma da
/// 2026-09-29'a kadar öyle yazıyordu), yeni kayıtlar `TEFAS:AFT`. Öneksiz
/// kod fiyat servisinde Yahoo'ya gidiyor ve fiyat DÖNMÜYORDU: 70.000 paylık
/// fon eski `current_price` ile kaldı, portföy ~₺24.500 eksikti ve bunu
/// hiçbir şey söylemiyordu. Aynı kod aramada `TEFAS:AFT` kimliğiyle
/// eşleşmediği için "Portföyünde" rozeti de çıkmıyordu. Daha kötüsü: bir
/// fon kodu tesadüfen bir ABD sembolüyle çakışsa Yahoo o hissenin USD
/// fiyatını döndürür ve fona yazılırdı — uydurma sayı (sözleşme madde 3).
///
/// ## Kural
/// Tür `fon` + elle fiyatlı DEĞİL + önek yok + kod TEFAS biçiminde (3 harf/
/// rakam) → `TEFAS:KOD`. Başka her şey olduğu gibi döner (idempotent).
///
///   * Elle fiyatlı fon dışarıda: kod orada fiyat kaynağı değil, etikettir;
///     yayımlanmış NAV'la birleştirilirse iki fiyat rejimi tek pozisyonda
///     karışırdı.
///   * 3 harf şartı sunucudan (`seriSembolu`) bilerek DAR: `.IS`'li ya da
///     uzun kodlu eski bir "fon" kaydı bugün Yahoo'dan fiyat alıyor olabilir;
///     onu TEFAS'a çevirmek çalışanı bozmaktır. TEFAS kodu olmayan şey TEFAS'a
///     yönlendirilmez.
///
/// Veri DEĞİŞTİRİLMEZ (okuma tarafı): `Asset.fromSupabase` bu biçime
/// çevirir, `toSupabase` satırın kayıtlı biçimini geri yazar. Sunucu
/// tarafının eşi `leaderboard-snapshot` › `seriSembolu`.
String kanonikTicker({
  required AssetType type,
  required String ticker,
  required bool isManualPrice,
}) {
  // Fon YOLUNDAN fiyatlanan her tür (BES dahil; `fiyatlamaTuru`). Mevduat
  // sembolü `MEVDUAT:` önekli olduğu için aşağıdaki desen onu değiştirmez.
  if (type.fiyatlamaTuru != AssetType.fon || isManualPrice) return ticker;
  final t = ticker.trim().toUpperCase();
  if (t.startsWith(tefasOneki) || !_tefasKodDeseni.hasMatch(t)) return ticker;
  return '$tefasOneki$t';
}

// Döviz kodu → para sembolü
const _currencySymbols = <String, String>{
  'USD': '\$', 'EUR': '€', 'GBP': '£', 'JPY': '¥',
  'CHF': '₣', 'CAD': 'C\$', 'AUD': 'A\$', 'CNY': '¥',
  'RUB': '₽', 'SAR': '﷼', 'AED': 'د', 'TRY': '₺',
  'SEK': 'kr', 'NOK': 'kr', 'DKK': 'kr', 'PLN': 'zł',
  'HUF': 'Ft', 'CZK': 'Kč', 'RON': 'lei', 'INR': '₹',
  'KRW': '₩', 'BRL': 'R\$', 'MXN': 'M\$', 'ZAR': 'R',
  'SGD': 'S\$', 'HKD': 'HK\$', 'NZD': 'NZ\$',
};

/// Ticker'dan döviz kodunu çıkarır.
/// "USDTRY=X" → "USD", "EURTRY=X" → "EUR"
String? _extractCurrencyCode(String ticker, String currency) {
  final clean = ticker.replaceAll('=X', '').replaceAll('.IS', '').trim().toUpperCase();
  if (clean.length >= 3) {
    final code = clean.substring(0, 3);
    if (code != 'TRY' && _currencySymbols.containsKey(code)) return code;
  }
  final cur = currency.toUpperCase();
  if (cur != 'TRY' && _currencySymbols.containsKey(cur)) return cur;
  return null;
}

/// Döviz varlığı için para sembolü döndürür.
/// Ticker öncelikli: "USDTRY=X" → "\$", "EURTRY=X" → "€"
String? currencySymbolFor(String ticker, String currency) {
  final code = _extractCurrencyCode(ticker, currency);
  return code != null ? _currencySymbols[code] : null;
}

/// Bir KOTASYONUN (birim fiyatın) para sembolü — [currencySymbolFor]'un
/// fiyat karşılığı.
///
/// [currencySymbolFor] döviz varlığının MİKTAR birimini verir ("$100"
/// tutan dolar). Fiyat ise paritenin KARŞI para birimindedir: `USDTRY=X`
/// kotasyonu 1 doların TL karşılığıdır, "₺49,00". Aramada ve varlık
/// sayfasında fiyat miktar sembolüyle yazılıyor, dolar "$49,00" görünüyordu
/// (2026-09-29 emülatör testi #13).
///
/// Kural: `XXXYYY=X` paritesinde sembol YYY'nin; diğerlerinde kotasyonun
/// kendi para birimi ([currency], emtia vadelisi `$`); bilinmiyorsa ₺.
String kotasyonSembolu(String ticker, String currency) {
  final t = ticker.trim().toUpperCase();
  if (t.endsWith('=X')) {
    final cift = t.substring(0, t.length - 2);
    if (cift.length == 6) {
      final karsi = _currencySymbols[cift.substring(3)];
      if (karsi != null) return karsi;
    }
  }
  return _currencySymbols[currency.trim().toUpperCase()] ?? '₺';
}

/// SEMBOL SERİSİNDEN okunan fiyatın simgesi — her zaman ₺.
///
/// ## Neden ayrı (seri denetimi, 2026-10-08)
/// Takip listesi satırı ve varlık sayfası fiyatı canlı kotasyondan değil
/// `HistoryService.getSymbolHistory` serisinin SON noktasından okur (aynı
/// sayı grafiğin ucudur — fiyat kaynağı sözleşmesi madde 2). O seri HER
/// sembolde TL'dir: TRY kote olanlar olduğu gibi, kalanlar (ABD hissesi,
/// eurobond, emtia, ons) o günün USD/TRY kuruyla çevrilir. Simge ise
/// [kotasyonSembolu] ile varlığın kotasyon para biriminden seçiliyordu:
/// AAPL satırı TL sayıyı "$" ile yazıyordu (kodu okuyarak bulundu: 255
/// dolarlık hisse TL karşılığıyla "$10.506,00" gibi). ABD hissesi ve eurobond takibe açılınca bu her USD
/// satırında görünürdü. Sayı ile simge aynı kaynaktan: seri TL ise ₺.
///
/// [kotasyonSembolu] CANLI kotasyon gösteren yerde (arama satırı,
/// `aramaFiyatMetni`) doğru kalır — orada sayı kotasyonun kendi birimidir.
const String sembolSerisiSimgesi = '₺';

/// BIST endeksi mi (`XU100.IS`, `XU030.IS`, `XUSIN.IS`)?
///
/// Endeks PUANDIR, fiyat değil: para simgesi ve kuruş anlamsız ("BIST 100
/// ₺12.290,58" yazıyordu — 2026-09-29 emülatör testi #17). Kural önceden
/// yalnızca arama satırında (`aramaFiyatMetni`) yaşıyordu; takip listesi
/// kendi biçimleyicisini kurup ₺ basıyordu. Tek tanım burada, gösteren her
/// yüzey buna sorar. Kayıtlar `.IS` son ekiyle gelir; son eksiz yazım da
/// (eski kayıt, test verisi) aynı endeksi anlatır.
bool bistEndeksiMi(String ticker) {
  final t = ticker.trim().toUpperCase();
  if (!t.startsWith('XU')) return false;
  if (t.endsWith('.IS')) return true;
  return t.length == 5 && !t.contains(RegExp(r'[.:=\-]'));
}
