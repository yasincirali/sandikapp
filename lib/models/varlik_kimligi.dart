import '../services/symbol_search_service.dart';
import 'asset_categories.dart';
import 'asset_type.dart';
import 'eurobond.dart';
import 'watchlist_item.dart';

/// Bir varlığın KİMLİĞİ — sahiplik ve takip bilgisinden bağımsız.
///
/// ## Neden ayrı tip
/// Varlık sayfası ([showVarlikSayfasi]) dört yerden açılır: takip listesi,
/// takibe alma araması, Karşılaştır ve varlık ekleme seçicileri. Her birinin
/// elindeki nesne farklı (`WatchlistItem`, `SymbolHit`, `GoldSubCategory`,
/// `TefasFund`…). Sayfa bunların hiçbirine bağlanmaz; yalnızca "hangi
/// varlık" sorusunun cevabını ister.
///
/// **Bir `Asset` DEĞİLDİR ve olamaz.** Miktar/maliyet taşımaz; sahte bir
/// `Asset` üretip toplama sızdırma yolu yapısal olarak kapalıdır (bkz.
/// `watchlist_isolation_test`).
///
/// Sembol → tür/alt kategori/para birimi kuralı eskiden
/// `AddWatchlistScreen._toCandidate` içindeydi. Aynı kural artık dört giriş
/// noktasında gerekiyor; kopyalanırsa "zaten takipte" tespiti ekranlar
/// arasında ayrışır. Tek yer burası.
class VarlikKimligi {
  /// Fiyat servislerine verilen sembol — `THYAO.IS`, `TEFAS:AFA`,
  /// `ALTIN_CEYREK`, `USDTRY=X`…
  final String ticker;
  final String name;
  final AssetType type;

  /// Altın/döviz alt kategorisi. `WatchlistItem.subCategory` ile aynı anlam.
  final String? subCategory;

  /// Kotasyonun para birimi (`assets.currency` ile aynı anlam).
  final String currency;

  const VarlikKimligi({
    required this.ticker,
    required this.name,
    required this.type,
    required this.currency,
    this.subCategory,
  });

  /// `WatchlistItem.key` ve portföy anahtarıyla AYNI kural — ayrışırsa sayfa
  /// "takipte" ya da "portföyünde" durumunu yanlış gösterir.
  String get key => varlikAnahtari(
      type: type, ticker: ticker, subCategory: subCategory);

  /// Kullanıcıya gösterilen kısa etiket: kaynak önekleri (`TEFAS:`, `.IS`)
  /// bir şey ifade etmez.
  String get kisaEtiket {
    final t = ticker.trim();
    // Mevduatın sembolü sözleşme id'sidir (`MEVDUAT:<uuid>`) — kullanıcıya
    // bir şey söylemez; varlık sayfasının başlığında uuid yazıyordu
    // (2026-10-01 emülatör testi). Adı ("Enpara · Vadeli") gösterilir.
    if (mevduatSozlesmeId(t) != null) return name;
    if (t.isNotEmpty) {
      final sade =
          t.contains(':') ? t.split(':').last : t.replaceAll('.IS', '');
      if (sade.length >= 2 && !sade.startsWith('ALTIN_')) return sade;
    }
    final sub = subCategory?.trim();
    if (sub != null && sub.isNotEmpty) return sub;
    return name;
  }

  factory VarlikKimligi.fromWatchlistItem(WatchlistItem w) => VarlikKimligi(
        ticker: w.ticker,
        name: w.name,
        type: w.type,
        subCategory: w.subCategory,
        currency: w.currency,
      );

  /// Arama sonucunu kimliğe çevirir. Portföy serileri (`PORTFOLIO:*`) ve
  /// TÜFE birer varlık değildir; `null` döner.
  ///
  /// Tür ve para birimi ticker biçiminden çıkarılır — `SymbolHit` bunları
  /// taşımaz çünkü karşılaştırma ekranının ihtiyacı yok.
  static VarlikKimligi? fromSymbolHit(SymbolHit h) {
    if (PortfolioSeries.isPortfolio(h.ticker)) return null;
    if (TufeSeries.isTufe(h.ticker)) return null;

    final t = h.ticker;

    if (t.startsWith('TEFAS:')) {
      return VarlikKimligi(
          ticker: t, name: h.name, type: AssetType.fon, currency: 'TRY');
    }
    if (t.startsWith(kriptoOneki)) {
      // Fiyat sunucuda TL (kripto_fiyat) — TRY kote.
      return VarlikKimligi(
          ticker: t, name: h.name, type: AssetType.kripto, currency: 'TRY');
    }
    if (eurobondIsin(t) != null) {
      // Eurobond (bayrak `eurobond`, seri denetimi 2026-10-08). Aşağıdaki
      // BIST düşüşüne bırakılsaydı TRY kote hisse sayılır, birim değeri
      // (kirli/100, USD) lira gibi gösterilir ve takip anahtarı portföydeki
      // tahvilinkiyle (`eurobond|…`) tutmazdı. Aramada yalnız USD tahvil
      // listelenir (`eklenebilirEurobondlar`).
      return eurobond(t, h.name);
    }
    if (t.startsWith('ALTIN_')) {
      return VarlikKimligi(
        ticker: t,
        name: h.name,
        type: AssetType.altin,
        subCategory: h.name,
        currency: 'TRY',
      );
    }
    if (t == 'XAUUSD=X') {
      // Ons altın Yahoo'dan USD gelir.
      return VarlikKimligi(
        ticker: t,
        name: h.name,
        type: AssetType.altin,
        subCategory: h.name,
        currency: 'USD',
      );
    }
    if (t.endsWith('TRY=X')) {
      // Kur çiftinin fiyatı TRY cinsindendir (USDTRY=X → ₺).
      return VarlikKimligi(
        ticker: t,
        name: h.name,
        type: AssetType.doviz,
        subCategory: t.replaceAll('TRY=X', ''), // USD / EUR / GBP
        currency: 'TRY',
      );
    }
    if (t.endsWith('=F')) {
      // Emtia vadelileri USD kote; `getSymbolHistory` günün kuruyla çevirir.
      return VarlikKimligi(
          ticker: t, name: h.name, type: AssetType.emtia, currency: 'USD');
    }
    if (h.source == SymbolSearchService.abdKaynagi) {
      // ABD hissesi (bayrak `abd_hisse`): sembol Yahoo'nunki, kotasyon USD.
      // Aşağıdaki BIST düşüşüne bırakılsaydı TRY sayılır, dolar fiyatı lira
      // gibi gösterilirdi.
      return abdHisse(t, h.name);
    }
    // Kalanlar BIST: hisseler ve endeksler (`XU100.IS`).
    return VarlikKimligi(
        ticker: t, name: h.name, type: AssetType.hisse, currency: 'TRY');
  }

  /// Varlık ekleme seçicisindeki altın türü. Arama servisindeki yerleşik
  /// altın kaydıyla AYNI kimliği üretir (ad = `goldTickerMap` anahtarı), yoksa
  /// seçiciden takibe alınan altın, aramadan alınanla iki ayrı kayıt olurdu.
  static VarlikKimligi? fromGold(GoldSubCategory g) {
    final t = goldTickerMap[g.label];
    if (t == null) return null;
    return fromSymbolHit(SymbolHit(ticker: t, name: g.label, source: 'Altın'));
  }

  /// Varlık ekleme seçicilerinin kimlikleri — formun yazdığı sembolle AYNI
  /// biçim (`AddAssetFormNotifier.selectBist100/selectFund/selectKripto`),
  /// yoksa seçiciden takibe alınan varlık aramadan alınanla iki ayrı kayıt
  /// olurdu.
  static VarlikKimligi hisse(String ticker, String ad) => VarlikKimligi(
      ticker: ticker, name: ad, type: AssetType.hisse, currency: 'TRY');

  /// ABD hissesi. Alt kategori kimliğe YAZILMAZ: `'abd'` pazar etiketidir
  /// (bkz. `anahtarAltKategorisi`); takip kaydı sembolle tanınır.
  static VarlikKimligi abdHisse(String ticker, String ad) => VarlikKimligi(
      ticker: ticker, name: ad, type: AssetType.hisse, currency: 'USD');

  /// Eurobond — sembol `EUROBOND:<ISIN>`, kotasyon USD (tahvilin para
  /// birimi; ekleme ve arama yalnız USD tahvil sunar). Portföy lotu da
  /// alt kategorisizdir, anahtarlar aynı çıkar.
  static VarlikKimligi eurobond(String sembol, String ad) => VarlikKimligi(
      ticker: sembol.trim().toUpperCase(),
      name: ad,
      type: AssetType.eurobond,
      currency: 'USD');

  static VarlikKimligi fon(String kod, String ad) => VarlikKimligi(
      ticker: 'TEFAS:$kod', name: ad, type: AssetType.fon, currency: 'TRY');

  static VarlikKimligi kripto(String kod, String ad) => VarlikKimligi(
      ticker: kriptoSembolu(kod),
      name: ad,
      type: AssetType.kripto,
      currency: 'TRY');

  /// Takip kaydı. `id` sunucuda üretilir.
  WatchlistItem toWatchlistItem({required String userId}) => WatchlistItem(
        id: '',
        userId: userId,
        ticker: ticker,
        name: name,
        type: type,
        subCategory: subCategory,
        currency: currency,
        addedAt: DateTime.now(),
      );
}

/// Tür + sembol + alt kategori anahtarı. `WatchlistItem.key` ve
/// `AddWatchlistScreen`'in portföy anahtarı aynı kuralı kullanır; sunucudaki
/// unique index (`watchlist_user_asset_uidx`) bunun karşılığıdır.
String varlikAnahtari({
  required AssetType type,
  required String ticker,
  String? subCategory,
}) {
  final sub = anahtarAltKategorisi(subCategory);
  final core = (sub?.trim().isNotEmpty ?? false)
      ? 'sub:${sub!.trim().toUpperCase()}'
      : ticker.trim().toUpperCase();
  return '${type.name}|$core';
}
