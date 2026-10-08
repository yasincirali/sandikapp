import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/abd_hisseleri.dart';
import '../models/asset.dart';
import '../models/asset_categories.dart';
import '../models/asset_type.dart';
import '../models/eurobond.dart';
import '../models/kripto_fiyat.dart';
import '../services/crash_reporter.dart';
import '../services/fx_rate_migration_service.dart';
import '../services/price_service.dart';
import '../services/remote_config_service.dart';
import '../services/tefas_service.dart';
import '../utils/tr_format.dart';
import 'bulk_cart_provider.dart';

/// Varlık ekleme formunun durum makinesi (Faz 3.10).
///
/// Ekran 2700 satırlık tek `State`'te 37 `setState` ile tür/alt kategori/
/// para birimi/tarih/önizleme/kayıt bayraklarını yönetiyordu; hangi
/// geçişin hangi alanı sıfırladığı yalnızca widget ağacını okuyarak
/// anlaşılıyordu ve hiçbiri Supabase/Yahoo olmadan test edilemiyordu.
///
/// Burada durum değişmez bir değer, geçişler adlandırılmış yöntemler, fiyat
/// erişimi [AddAssetPriceLookup] kapısıdır. `TextEditingController`'lar
/// ekranda kalır: bir geçişin metin alanına yazması gereken değerler
/// [AlanYazimi] olarak DÖNER, ekran uygular — Notifier widget'a dokunmaz.

// ─── Döviz sabitleri ─────────────────────────────────────────────────────────

typedef DovizOpt = ({String label, String ticker, String name, String symbol});

const dovizOptions = <DovizOpt>[
  (label: 'USD', ticker: 'USDTRY=X', name: 'ABD Doları', symbol: '\$'),
  (label: 'EUR', ticker: 'EURTRY=X', name: 'Euro', symbol: '€'),
  (label: 'GBP', ticker: 'GBPTRY=X', name: 'İngiliz Sterlini', symbol: '£'),
  (label: 'TRY', ticker: '', name: 'Türk Lirası', symbol: '₺'),
];

/// Bilinmeyen etikette ilk seçenek (USD) döner — eski ekran davranışı.
DovizOpt dovizOptFor(String? label) => dovizOptions.firstWhere(
      (o) => o.label == label,
      orElse: () => dovizOptions.first,
    );

// ─── Hızlı giriş ─────────────────────────────────────────────────────────────

typedef ParsedEntry = ({
  AssetType type,
  String? subCategory,
  double qty,
  double price,
  String raw,
});

/// Hızlı girişte tanınan kripto adları → kod. Bilerek KISA: serbest
/// metinde her üç harfli kelimeyi coin sanmak ("100 eur" gibi) yanlış tür
/// üretir. Listede olmayan coin tür seçiciyle eklenir.
const _hizliGirisKripto = <String, String>{
  'bitcoin': 'BTC',
  'btc': 'BTC',
  'ethereum': 'ETH',
  'ether': 'ETH',
  'eth': 'ETH',
  'tether': 'USDT',
  'usdt': 'USDT',
  'solana': 'SOL',
  'xrp': 'XRP',
  'ripple': 'XRP',
  'bnb': 'BNB',
  'avax': 'AVAX',
  'dogecoin': 'DOGE',
  'doge': 'DOGE',
  'cardano': 'ADA',
};

/// Hızlı giriş metninde tanınan kripto kodu — tam kelime eşleşmesi.
String? hizliGirisKriptoKodu(String metin) {
  for (final kelime in RegExp(r'[a-zçğıöşü]+').allMatches(metin.toLowerCase())) {
    final kod = _hizliGirisKripto[kelime.group(0)];
    if (kod != null) return kod;
  }
  return null;
}

/// Bir hızlı giriş satırını çözer. Desteklenen biçimler:
///   "100 dolar"                  → 100 USD (fiyatsız)
///   "100 dolar 32 liradan"       → qty=100, price=32, USD
///   "10 gram altın 4500 liradan" → qty=10, price=4500
///   "GARAN 500 adet 105 lira"    → qty=500, price=105
///   "0,05 btc"                   → 0,05 BTC (kripto, fiyatsız)
/// Miktar bulunamazsa `null`.
ParsedEntry? parseQuickEntry(String raw) {
  final text = raw.toLowerCase().trim();
  if (text.isEmpty) return null;

  var detectedType = AssetType.hisse;
  String? detectedSub;

  // Kripto ÖNCE bakılır: "usdt" içinde "usd" geçer ve aşağıdaki döviz
  // kalıbı onu dolar sanıyordu (2026-09-25 kripto envanteri). Kod
  // `subCategory`'de taşınır; kayıt yolu `KRIPTO:<kod>` sembolünü kurar.
  final kripto = hizliGirisKriptoKodu(text);
  if (kripto != null) {
    detectedType = AssetType.kripto;
    detectedSub = kripto;
  } else if (RegExp(r'dolar|usd').hasMatch(text)) {
    detectedType = AssetType.doviz;
    detectedSub = 'USD';
  } else if (RegExp(r'euro|eur').hasMatch(text)) {
    detectedType = AssetType.doviz;
    detectedSub = 'EUR';
  } else if (RegExp(r'sterlin|gbp|pound').hasMatch(text)) {
    detectedType = AssetType.doviz;
    detectedSub = 'GBP';
  } else if (RegExp(r'gram\s*alt[ıi]n|alt[ıi]n').hasMatch(text)) {
    detectedType = AssetType.altin;
  } else if (RegExp(r'fon\b').hasMatch(text)) {
    detectedType = AssetType.fon;
  } else if (RegExp(r'hisse|adet').hasMatch(text)) {
    detectedType = AssetType.hisse;
  }

  // Sayı belirteci tamamen yakalanır ("1.234,56", "41.2345", "0.125") ve
  // formdaki alanlarla AYNI kuralla (`parseTrNumber`) çözülür. Eskiden
  // noktadan sonra 3 hane GELİYORSA nokta atılıyordu: "41.2345" → 412345,
  // "0.125 gram" → 125 (2026-09-23 denetimi F15).
  const sayi = r'(\d+(?:[.,]\d+)*)';
  double oku(String s) => parseTrNumber(s) ?? 0;
  final numMatches = RegExp(sayi).allMatches(text).toList();
  double qty = 0;
  double price = 0;

  if (numMatches.isNotEmpty) {
    qty = oku(numMatches.first.group(1)!);
  }
  final priceHint = RegExp('$sayi\\s*(lira|tl|₺)').firstMatch(text);
  if (priceHint != null) {
    price = oku(priceHint.group(1)!);
  } else if (numMatches.length >= 2) {
    price = oku(numMatches[1].group(1)!);
  }

  if (qty <= 0) return null;
  return (
    type: detectedType,
    subCategory: detectedSub,
    qty: qty,
    price: price,
    raw: raw.trim(),
  );
}

// ─── Fiyat kapısı ────────────────────────────────────────────────────────────

/// Formun ihtiyaç duyduğu üç sorgu. Canlı uygulamada Yahoo + TEFAS; testte
/// sahte. `TEFAS:` ön eki burada çözülür, çağıran tek bir sembol verir.
abstract class AddAssetPriceLookup {
  Future<double?> historicalClose(String ticker, DateTime date);
  Future<double?> spot(String ticker);
  Future<String?> companyName(String ticker);
}

class LivePriceLookup implements AddAssetPriceLookup {
  const LivePriceLookup();

  @override
  Future<double?> historicalClose(String ticker, DateTime date) =>
      PriceService.instance.fetchHistoricalClose(ticker, date);

  @override
  Future<double?> spot(String ticker) async {
    if (ticker.startsWith('TEFAS:')) {
      final code = ticker.replaceFirst('TEFAS:', '');
      final prices = await TefasService.instance.fetchPrices([code]);
      return prices[code];
    }
    final quotes = await PriceService.instance.fetchQuotes([ticker]);
    return quotes[ticker.toUpperCase()]?.regularMarketPrice;
  }

  @override
  Future<String?> companyName(String ticker) async {
    final quotes = await PriceService.instance.fetchQuotes([ticker]);
    return quotes[ticker.toUpperCase()]?.companyName;
  }
}

final addAssetPriceLookupProvider =
    Provider<AddAssetPriceLookup>((_) => const LivePriceLookup());

/// Fiyat çözümü sonucu. [historical]: seçili tarihin kapanışı bulundu;
/// [fallbackToSpot]: tarih geçmişti ama kapanış yoktu, güncel fiyat atandı.
typedef FiyatSonucu = ({double? price, bool historical, bool fallbackToSpot});

/// Önizleme ve kayıt aynı kuralı kullanır: bugünse spot; geçmiş tarihse
/// önce o günün kapanışı, yoksa spot'a düşülür. Ağ hatası fiyatsız döner —
/// çağıran "bulunamadı" gösterir ya da manuel fiyata bırakır.
Future<FiyatSonucu> fiyatBul({
  required AddAssetPriceLookup lookup,
  required String ticker,
  required DateTime date,
  DateTime? now,
}) async {
  final isToday = _ayniGun(date, now ?? DateTime.now());
  double? price;
  var historical = false;
  var fallback = false;
  try {
    if (!isToday) {
      final hist = await lookup.historicalClose(ticker, date);
      if (hist != null && hist > 0) {
        price = hist;
        historical = true;
      }
    }
    if (price == null) {
      final s = await lookup.spot(ticker);
      if (s != null && s > 0) {
        price = s;
        if (!isToday) fallback = true;
      }
    }
  } catch (_) {
    // Fiyat isteğe bağlı: ağ yoksa kullanıcı elle girer; hata yutulur.
  }
  return (price: price, historical: historical, fallbackToSpot: fallback);
}

bool _ayniGun(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Seçilen tarih hafta sonuysa, tarihli kapanışın GERÇEKTE geldiği işlem
/// günü (Cuma); değilse `null`.
///
/// Tarihli fiyat "son geçerli kapanış" kuralıyla çekilir
/// (`PriceService.fetchHistoricalClose`: hedef günde ya da öncesindeki en
/// yeni işlem günü). Pazar seçilince gelen fiyat Cuma'nındır; form ise
/// "1 Mar 2026 kapanışı" yazıyordu — o gün kapanış yok (2026-09-29 emülatör
/// testi #31). Kripto 7/24 işler, hafta sonu kendi kapanışı vardır: `null`.
///
/// Resmî tatiller bilinmiyor (takvim yok): hafta içi bir tatilde metin yine
/// seçilen günü söyler. Uydurma bir gün yazmaktansa bilineni söylemek.
DateTime? haftaSonuKapanisGunu(DateTime secilen, {required bool yediGun}) {
  if (yediGun) return null;
  final gun = dayKey(secilen);
  return switch (gun.weekday) {
    DateTime.saturday => DateTime(gun.year, gun.month, gun.day - 1),
    DateTime.sunday => DateTime(gun.year, gun.month, gun.day - 2),
    _ => null,
  };
}

// ─── TL karşılığı ────────────────────────────────────────────────────────────

/// Dövizli alımın formda gösterilen TL karşılığı için kur (yasin
/// 2026-10-08: "dolar olarak gösteriyor, TL karşılığı da gösterilmeli").
///
/// Kayıttaki kuralın aynısı (`PortfolioNotifier._alisKuru`): bugünkü
/// alımda canlı kur, geriye tarihli alımda ALIM GÜNÜNÜN kuru — portföy
/// toplamına giren maliyet tam olarak bu sayıyla çevrilir, form başka bir
/// sayı söylemesin. [tarihli] o günün kapanış kuru (yüklenmediyse `null`).
/// Kur bilinmiyorsa `null`: TL satırı hiç çizilmez, 1.0 ya da sabit bir
/// kurla uydurma tutar yazılmaz (fiyat kaynağı sözleşmesi (3)).
double? tlKarsiligiKuru({
  required String currency,
  required DateTime tarih,
  required double canliKur,
  required double? tarihli,
  DateTime? now,
}) {
  if (currency.toUpperCase() == 'TRY') return null;
  final geriTarihli = dayKey(tarih).isBefore(dayKey(now ?? DateTime.now()));
  final kur = geriTarihli ? tarihli : canliKur;
  return kur != null && kur > 1.0 ? kur : null;
}

/// Geriye tarihli dövizli alımın kuru — yalnız form önizlemesi için.
/// Bugünkü alımda sorgu atılmaz (canlı kur portföy durumunda hazır).
final alimGunuKuruProvider = FutureProvider.autoDispose
    .family<double?, ({String currency, DateTime gun})>((ref, k) async {
  final sembol = FxRateMigrationService.fxSembolu(k.currency);
  if (sembol == null) return null;
  try {
    return await PriceService.instance.fetchHistoricalFxRate(sembol, k.gun);
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'alimGunuKuruProvider');
    return null;
  }
});

// ─── Durum ───────────────────────────────────────────────────────────────────

/// Bir geçişin metin alanlarına yazması gereken değerler. `null` = dokunma,
/// boş metin = temizle.
class AlanYazimi {
  const AlanYazimi({this.name, this.ticker, this.quantity, this.price});
  final String? name;
  final String? ticker;
  final String? quantity;
  final String? price;
  static const yok = AlanYazimi();
}

class AddAssetFormState {
  const AddAssetFormState({
    required this.type,
    required this.subCategory,
    required this.unitType,
    required this.currency,
    required this.isManualPrice,
    required this.addedDate,
    this.saving = false,
    this.previewPrice,
    this.previewLoading = false,
    this.previewIsHistorical = false,
    this.bist100Ticker,
    this.selectedFund,
    this.notesExpanded = false,
    this.denendi = false,
    this.abdAcik = false,
    this.turIzgarasiAcik = false,
    this.eurobondSozlesmesi,
    this.eurobondFiyati,
  });

  /// Açılış değerleri. Öncelik: düzenlenen kayıt > sepet öğesi > prefill
  /// (karşılaştırma ekranından gelen tür/ticker/ad) > varsayılan.
  factory AddAssetFormState.initial({
    Asset? editingAsset,
    BulkCartItem? cartInitial,
    String? prefillTicker,
    AssetType? prefillType,
    DateTime? prefillDate,
    DateTime? now,
    bool abdAcik = false,
    bool turIzgarasi = false,
  }) {
    final a = editingAsset;
    final c = cartInitial;
    final type = a?.type ?? c?.type ?? prefillType ?? AssetType.hisse;
    final ticker = a?.ticker ?? c?.ticker ?? prefillTicker ?? '';
    // ABD kataloğundan gelen prefill (arama → "Portföye ekle"): pazar ABD,
    // para birimi USD. Kurulmasaydı form TRY açılır ve dolar fiyatı lira
    // diye kaydedilirdi. Yalnız bayrak açıkken ve katalogdaki sembolde.
    final abdPrefill = abdAcik &&
        a == null &&
        c == null &&
        prefillType == AssetType.hisse &&
        abdHisseleri.containsKey(prefillTicker);
    // BIST prefill'inde alt kategori de kurulmalı, yoksa BIST100 seçici boş
    // açılır ve seçili hisse görünmez.
    final subCat = a?.subCategory ??
        c?.subCategory ??
        (abdPrefill
            ? StockSubCategory.abd.name
            : prefillType == AssetType.hisse &&
                    (prefillTicker?.endsWith('.IS') ?? false)
                ? StockSubCategory.bist100.label
                : null);
    final isBist100 =
        type == AssetType.hisse && subCat == StockSubCategory.bist100.label;
    TefasFund? fund;
    if (type == AssetType.fon && ticker.startsWith('TEFAS:')) {
      fund = TefasFund(
        code: ticker.replaceFirst('TEFAS:', ''),
        name: a?.name ?? c?.name ?? '',
        price: a?.currentPrice ?? 0,
        fundType: '',
        managerName: '',
      );
    }
    return AddAssetFormState(
      type: type,
      subCategory: subCat,
      unitType: a?.unitType ?? c?.unitType ?? 'piece',
      currency: a?.currency ??
          c?.currency ??
          (abdPrefill ? 'USD' : type.defaultCurrency),
      isManualPrice: a?.isManualPrice ?? (c != null && c.ticker.isEmpty),
      // Halka arz katılımı (F6) tarihi hazır getirir; null iken eski davranış.
      addedDate:
          a?.addedDate ?? c?.addedDate ?? prefillDate ?? now ?? DateTime.now(),
      bist100Ticker: isBist100 && ticker.isNotEmpty ? ticker : null,
      selectedFund: fund,
      abdAcik: abdAcik,
      // Izgara yalnız türü henüz belli olmayan YENİ kayıtta açık doğar.
      // Düzenleme, sepet öğesi ve ön seçim (arama, karşılaştırma, ilk
      // varlık vitrini) türü zaten söylemiş: tekrar sormak bir adım fazla.
      turIzgarasiAcik:
          turIzgarasi && a == null && c == null && prefillType == null,
    );
  }

  final AssetType type;
  final String? subCategory;
  final String unitType;
  final String currency;
  final bool isManualPrice;
  final DateTime addedDate;
  final bool saving;

  /// Kullanıcı kaydetmeden önce tahmini birim fiyat; kullanıcı fiyatı
  /// kendisi yazdıysa null kalır.
  final double? previewPrice;
  final bool previewLoading;
  final bool previewIsHistorical;

  final String? bist100Ticker;
  final TefasFund? selectedFund;
  final bool notesExpanded;

  /// "Ekle"ye en az bir kez basıldı mı. Bundan sonra form her değişimde
  /// yeniden doğrulanır: uyarı, kullanıcı varlığı seçtiği anda kalkar (bir
  /// sonraki dokunuşu beklemez). Denemeden önce doğrulama yok — boş formu
  /// açar açmaz kırmızı göstermek suçlayıcı olurdu.
  final bool denendi;

  /// `abd_hisse` bayrağı form açılırken açık mıydı. Durumda taşınır ki
  /// geçişler ve kimlik kuralı Remote Config'e değil değere baksın (test
  /// edilebilir; form açıkken bayrak yenilense de form tutarlı kalır).
  final bool abdAcik;

  /// Tür ızgarası açık mı (bayrak `tur_secici_izgara`). Açıkken ekran formun
  /// gövdesini çizmez: önce "ne ekliyorsun", sonra ayrıntı. Seçimden sonra
  /// ızgara tek satıra katlanır, "Değiştir" yeniden açar. Bayrak kapalıyken
  /// hep `false` ve hiçbir yerde okunmaz (çip satırı birebir eski).
  /// `notesExpanded` gibi görünüm durumu burada: ekran `setState` taşımaz
  /// (Faz 3.10 ratchet).
  final bool turIzgarasiAcik;

  /// Seçili eurobondun sözleşmesi (katalogdan). Temiz → kirli çevirisi ve
  /// işlemiş faiz satırı buna bakar; kupon/vade kullanıcıdan alınmaz
  /// (yanlış girilirse işlemiş faiz sessizce yanlış çıkar). Düzenlemede
  /// ekran açılışta katalogdan yükler; yüklenene kadar null.
  final EurobondSozlesmesi? eurobondSozlesmesi;

  /// Seçili eurobondun son fiyatı — yalnız temiz fiyat ön doldurması için.
  final EurobondFiyati? eurobondFiyati;

  bool get isEurobond => type == AssetType.eurobond;

  /// Formdaki temiz fiyattan (% nominal) kayıtlı birim değer (kirli/100).
  /// Sözleşme yoksa ya da fiyat geçersizse null — çevrilemeyen fiyat
  /// kaydedilmez (bkz. [kimlikEksigi]).
  double? eurobondBirimFiyati(double? temizYuzde) {
    final s = eurobondSozlesmesi;
    if (s == null || temizYuzde == null || temizYuzde <= 0) return null;
    return eurobondBirimDegeri(s, temizYuzde, addedDate);
  }

  bool get isBist100 =>
      type == AssetType.hisse && subCategory == StockSubCategory.bist100.label;

  /// Hisse formu ABD pazarında mı. Bayrak kapalıyken HER ZAMAN `false`:
  /// eski sürümün ya da bayrağın kapatıldığı bir anda düzenlenen ABD lot'u
  /// eski serbest sembol yolundan geçer (kural birebir eski).
  bool get isAbd =>
      abdAcik &&
      type == AssetType.hisse &&
      subCategory == StockSubCategory.abd.name;
  bool get isFon => type == AssetType.fon;
  bool get isDoviz => type == AssetType.doviz;
  bool get isAltin => type == AssetType.altin;

  /// Miktar alanının ve hızlı miktar çiplerinin birimi.
  ///
  /// Kanonik [birimEtiketi]'nden (bulgu #22, 2026-09-29): eskiden
  /// `UnitType.label` okunuyordu ve hisse/fon formda "Adet", kaydedilince
  /// portföyde "lot" yazıyordu; altın formda "Gram", portföyde "gr". Aynı
  /// varlık iki ekranda iki birim — `bulk_add`'de 2026-09-12'de kapatılan
  /// ayrışmanın form tarafındaki kopyası. Döviz alt kategorisini (para
  /// birimi) yazmaya devam eder.
  String get quantitySuffix {
    if (isDoviz) return subCategory ?? 'Adet';
    return birimEtiketi(type: type, unitType: unitType, currency: currency);
  }

  List<String> get quantityPresets {
    // Altın alt türleri birimi 'gr' kısaltmasıyla taşır (`GoldSubCategory`),
    // birim seçici ise 'gram' — ikisi de gram demektir.
    if (unitType == 'gram' || unitType == 'gr') {
      return const ['1', '5', '10', '50', '100'];
    }
    if (unitType == 'ounce') return const ['0.1', '0.5', '1', '5', '10'];
    // Kripto: tam sayı adet nadirdir; BTC'de 0,001 bile anlamlı tutar.
    if (type == AssetType.kripto) return const ['0,001', '0,01', '0,1', '1', '10'];
    // Eurobond miktarı NOMİNALDİR; bankalar 1.000'lik katlarla işlem açar
    // (ihraç asgarisi çoğunlukla 200.000, ama ikincil piyasada banka 1.000
    // nominalden satar). "1" nominal bir dolarlık tahvil demek, anlamsız.
    if (type == AssetType.eurobond) {
      return const ['1.000', '5.000', '10.000', '50.000'];
    }
    if (type == AssetType.fon) return const ['1', '10', '100', '1000'];
    if (type == AssetType.hisse) return const ['1', '5', '10', '100', '1000'];
    return const ['1', '5', '10', '100'];
  }

  /// Önizleme/kayıt için sembol. Serbest metin alanı yalnızca hisse-diğer,
  /// emtia ve "diğer" türlerinde anlamlıdır; ötekiler seçimden türer.
  String? resolveTicker(String tickerText) {
    if (isBist100) return bist100Ticker;
    // Eurobondda tarihli önizleme yok: kotasyon birim değerdir (kirli/100),
    // form ise temiz % ister — "0,99 USD / birim" kartı kullanıcıyı
    // yanıltırdı. Temiz fiyat seçimde katalogdan ön doldurulur.
    if (isEurobond) return null;
    if (isAbd) {
      final t = abdSembolu(tickerText);
      return t.isEmpty ? null : t;
    }
    if (isFon && selectedFund != null) return 'TEFAS:${selectedFund!.code}';
    if (isAltin && subCategory != null) return goldTickerMap[subCategory!];
    if (isDoviz && subCategory != null) return dovizOptFor(subCategory).ticker;
    final t = tickerText.trim().toUpperCase();
    return t.isEmpty ? null : t;
  }

  /// Kayıt kimliği: sembol, ad ve "fiyat elle mi" bayrağı — eski `_save`
  /// başındaki dallanma. Fon ve sembollü altın asla manuel değildir;
  /// döviz yalnızca TRY seçilince (sembolsüz) manueldir.
  ({String ticker, String name, bool manual}) resolveIdentity({
    required String nameText,
    required String tickerText,
  }) {
    var ticker = '';
    var name = nameText.trim();
    if (isBist100) {
      ticker = bist100Ticker ?? '';
      name = bist100StocksMap[ticker] ?? ticker.replaceAll('.IS', '');
    } else if (isEurobond) {
      // Sembol yalnız katalogdaki sözleşmeden kurulur: serbest ISIN
      // sunucunun fiyatlamadığı bir tahvile bağlanıp fiyatsız lot üretirdi.
      final s = eurobondSozlesmesi;
      ticker = s == null ? '' : eurobondSembolu(s.isin);
      if (s != null) name = s.ad;
    } else if (isAbd) {
      // Sembol Yahoo biçiminde (`BRK.B` → `BRK-B`); ad boşsa katalogdaki
      // ad, o da yoksa sembol — adsız lot portföyde boş satır olurdu.
      ticker = isManualPrice ? '' : abdSembolu(tickerText);
      if (name.isEmpty) name = abdHisseleri[ticker] ?? ticker;
    } else if (isFon && selectedFund != null) {
      ticker = 'TEFAS:${selectedFund!.code}';
      name = selectedFund!.name;
    } else if (isAltin && subCategory != null) {
      ticker = goldTickerMap[subCategory!] ?? '';
      if (name.isEmpty) name = subCategory!;
    } else if (isDoviz && subCategory != null) {
      final opt = dovizOptFor(subCategory);
      ticker = opt.ticker;
      if (name.isEmpty) name = opt.name;
    } else if (!isAltin && !isFon && !isDoviz) {
      ticker = isManualPrice ? '' : tickerText.trim().toUpperCase();
    }
    final manual = isFon || isEurobond
        ? false
        : isAltin
            ? ticker.isEmpty
            : isDoviz
                ? ticker.isEmpty
                : isManualPrice || ticker.isEmpty;
    return (ticker: ticker, name: name, manual: manual);
  }

  /// Seçim gerektiren türde varlık seçilmemişse hangi uyarı; seçildiyse
  /// (ya da tür serbest adlıysa) null.
  ///
  /// **Kullanıcı bildirimi 2026-09-29:** hisse seçmeden "Ekle" adsız,
  /// sembolsüz bir lot kaydediyordu; altında da aynısı. Hisse/kripto için
  /// ölçü, kaydın gerçekten alacağı semboldür ([resolveIdentity]) —
  /// ekrandaki seçim değil: ikisi ayrışırsa (ör. elle fiyat bayrağı açık
  /// kalmış) seçim görünür ama boş sembol yazılırdı.
  ///
  /// Emtia / diğer serbest adla eklenir; onların kuralı ad alanında
  /// (`nameRequired`). [muaf]: var olan bir kaydı düzenlemek. Eski kayıtlar
  /// sembolsüz ya da elle fiyat bayraklı olabilir; tutarı/tarihi düzeltmek
  /// varlığı yeniden seçmeye zorlamamalı. Kural YENİ kayıt içindir.
  KimlikEksigi? kimlikEksigi({required String tickerText, bool muaf = false}) {
    // Eurobond düzenlemede de MUAF DEĞİL: fiyat alanı temiz % gösterir ve
    // kayıtta sözleşmeyle kirli birim değere çevrilir. Sözleşme yüklenemediyse
    // çeviri yapılamaz; muaf tutmak "98,75"i birim değer diye (100 kat
    // büyük) yazardı.
    if (isEurobond && eurobondSozlesmesi == null) return KimlikEksigi.eurobond;
    if (muaf) return null;
    switch (type) {
      case AssetType.hisse:
      case AssetType.kripto:
        final ticker =
            resolveIdentity(nameText: '', tickerText: tickerText).ticker;
        if (ticker.isNotEmpty) return null;
        return type == AssetType.hisse
            ? KimlikEksigi.hisse
            : KimlikEksigi.kripto;
      case AssetType.fon:
        return selectedFund == null ? KimlikEksigi.fon : null;
      case AssetType.altin:
        return (subCategory ?? '').isEmpty ? KimlikEksigi.altin : null;
      case AssetType.doviz:
        return (subCategory ?? '').isEmpty ? KimlikEksigi.doviz : null;
      default:
        return null;
    }
  }

  AddAssetFormState copyWith({
    AssetType? type,
    Object? subCategory = _keep,
    String? unitType,
    String? currency,
    bool? isManualPrice,
    DateTime? addedDate,
    bool? saving,
    Object? previewPrice = _keep,
    bool? previewLoading,
    bool? previewIsHistorical,
    Object? bist100Ticker = _keep,
    Object? selectedFund = _keep,
    bool? notesExpanded,
    bool? denendi,
    bool? abdAcik,
    bool? turIzgarasiAcik,
    Object? eurobondSozlesmesi = _keep,
    Object? eurobondFiyati = _keep,
  }) =>
      AddAssetFormState(
        type: type ?? this.type,
        subCategory: identical(subCategory, _keep)
            ? this.subCategory
            : subCategory as String?,
        unitType: unitType ?? this.unitType,
        currency: currency ?? this.currency,
        isManualPrice: isManualPrice ?? this.isManualPrice,
        addedDate: addedDate ?? this.addedDate,
        saving: saving ?? this.saving,
        previewPrice: identical(previewPrice, _keep)
            ? this.previewPrice
            : previewPrice as double?,
        previewLoading: previewLoading ?? this.previewLoading,
        previewIsHistorical: previewIsHistorical ?? this.previewIsHistorical,
        bist100Ticker: identical(bist100Ticker, _keep)
            ? this.bist100Ticker
            : bist100Ticker as String?,
        selectedFund: identical(selectedFund, _keep)
            ? this.selectedFund
            : selectedFund as TefasFund?,
        notesExpanded: notesExpanded ?? this.notesExpanded,
        denendi: denendi ?? this.denendi,
        abdAcik: abdAcik ?? this.abdAcik,
        turIzgarasiAcik: turIzgarasiAcik ?? this.turIzgarasiAcik,
        eurobondSozlesmesi: identical(eurobondSozlesmesi, _keep)
            ? this.eurobondSozlesmesi
            : eurobondSozlesmesi as EurobondSozlesmesi?,
        eurobondFiyati: identical(eurobondFiyati, _keep)
            ? this.eurobondFiyati
            : eurobondFiyati as EurobondFiyati?,
      );
}

const _keep = Object();

/// Kaydı engelleyen eksik seçim — ekran uyarı metnini buna göre seçer.
enum KimlikEksigi { hisse, fon, altin, doviz, kripto, eurobond }

// ─── Notifier ────────────────────────────────────────────────────────────────

/// Ekranın açılış argümanları. Eşitlik kimliktir: her ekran örneği kendi
/// nesnesini üretir, böylece sepetten düzenleme için arka arkaya açılan iki
/// form aynı provider'ı paylaşmaz.
class AddAssetFormArgs {
  AddAssetFormArgs({
    this.editingAsset,
    this.cartInitial,
    this.prefillTicker,
    this.prefillType,
    this.prefillDate,
  });
  final Asset? editingAsset;
  final BulkCartItem? cartInitial;
  final String? prefillTicker;
  final AssetType? prefillType;

  /// İsteğe bağlı açılış tarihi (halka arz katılımı); null → bugün.
  final DateTime? prefillDate;
}

class AddAssetFormNotifier
    extends AutoDisposeFamilyNotifier<AddAssetFormState, AddAssetFormArgs> {
  Timer? _previewDebounce;
  int _previewSeq = 0;
  bool _disposed = false;

  @override
  AddAssetFormState build(AddAssetFormArgs arg) {
    ref.onDispose(() {
      _disposed = true;
      _previewDebounce?.cancel();
    });
    return AddAssetFormState.initial(
      editingAsset: arg.editingAsset,
      cartInitial: arg.cartInitial,
      prefillTicker: arg.prefillTicker,
      prefillType: arg.prefillType,
      prefillDate: arg.prefillDate,
      abdAcik: RemoteConfigService.instance.abdHisse,
      turIzgarasi: RemoteConfigService.instance.turSeciciIzgara,
    );
  }

  // Bu sayı kayıt/önizleme yarışlarında "canlı mıyım" sorusunun cevabıdır;
  // dispose sonrası state ataması Riverpod'da hata fırlatır.
  void _set(AddAssetFormState s) {
    if (!_disposed) state = s;
  }

  // ── Basit alanlar ──────────────────────────────────────────────────────

  void setSaving(bool v) => _set(state.copyWith(saving: v));
  void kayitDenendi() {
    if (!state.denendi) _set(state.copyWith(denendi: true));
  }
  /// ABD hissesinde para birimi USD'ye kilitli: kotasyon dolardır, başka
  /// para birimiyle kayıt fiyatı yanlış ölçekte çevirirdi.
  void setCurrency(String v) {
    if (state.isAbd && v != 'USD') return;
    // Eurobond tahvilin kendi para birimine kilitli (aynı gerekçe).
    if (state.isEurobond) return;
    _set(state.copyWith(currency: v));
  }
  void setDate(DateTime v) => _set(state.copyWith(addedDate: v));
  void setManualPrice(bool v) => _set(state.copyWith(isManualPrice: v));
  void toggleNotes() =>
      _set(state.copyWith(notesExpanded: !state.notesExpanded));

  /// Tür ızgarasını açar/katlar (bayrak `tur_secici_izgara`). Tür seçimi
  /// bunu KENDİLİĞİNDEN değiştirmez: hızlı giriş ve sepet geçişleri de
  /// `selectType` çağırıyor; katlamayı seçiciyi çizen ekran söyler.
  void turIzgarasi({required bool acik}) {
    if (state.turIzgarasiAcik != acik) {
      _set(state.copyWith(turIzgarasiAcik: acik));
    }
  }

  // ── Geçişler ───────────────────────────────────────────────────────────

  /// Tür değişince alt seçimler ve sembol/ad temizlenir; para birimi türün
  /// varsayılanına döner.
  AlanYazimi selectType(AssetType t) {
    _set(state.copyWith(
      type: t,
      subCategory: null,
      unitType: 'piece',
      currency: t.defaultCurrency,
      bist100Ticker: null,
      selectedFund: null,
      eurobondSozlesmesi: null,
      eurobondFiyati: null,
      // Eurobond birimi nominal (`birimEtiketi`); `unitType` 'piece' kalır,
      // etiket türden türer.
    ));
    return const AlanYazimi(ticker: '', name: '');
  }

  /// Serbest sembol alanına yazıldı: BIST100 seçimi düşer, alt kategori
  /// "Diğer Hisseler" olur. Alan boşaldıysa fiyat elle girilecek demektir.
  void tickerTyped(String v) {
    if (state.isAbd) {
      // ABD pazarında serbest sembol pazarı değiştirmez; alt kategori
      // `'abd'`, para birimi USD kalır.
      _set(state.copyWith(isManualPrice: v.isEmpty));
      return;
    }
    if (v.isNotEmpty) {
      _set(state.copyWith(
        bist100Ticker: null,
        subCategory: StockSubCategory.other.label,
        isManualPrice: false,
      ));
    } else {
      _set(state.copyWith(isManualPrice: true));
    }
  }

  AlanYazimi selectGold(GoldSubCategory g) {
    _set(state.copyWith(subCategory: g.label, unitType: g.unitType));
    return AlanYazimi(name: g.label);
  }

  /// Döviz her zaman TRY karşılığıyla kaydedilir; TRY'nin kendisi sembolsüz
  /// olduğundan manuel fiyata düşer.
  AlanYazimi selectDoviz(DovizOpt opt) {
    _set(state.copyWith(
      subCategory: opt.label,
      currency: 'TRY',
      isManualPrice: opt.ticker.isEmpty,
    ));
    return AlanYazimi(ticker: opt.ticker, name: opt.name);
  }

  /// Elle fiyat bayrağı da iner: sembol alanı yazılıp silindiyse bayrak
  /// açık kalıyor ve [resolveIdentity] seçilen hisseyi boş sembolle
  /// kaydediyordu.
  AlanYazimi selectBist100(String ticker) {
    _set(state.copyWith(bist100Ticker: ticker, isManualPrice: false));
    return AlanYazimi(
      ticker: ticker,
      name: bist100StocksMap[ticker] ?? ticker.replaceAll('.IS', ''),
    );
  }

  /// Hisse pazarı seçimi (bayrak `abd_hisse`): BIST ↔ ABD. Seçili hisse,
  /// sembol ve ad temizlenir — BIST sembolü ABD pazarında (ya da tersi)
  /// fiyatsız/yanlış ölçekli lot üretirdi. ABD: alt kategori `'abd'`, para
  /// birimi USD. BIST: hisse türünün açılış hâli (alt kategori yok, TRY).
  AlanYazimi selectHisseBorsasi({required bool abd}) {
    // Bayrak kapalıyken segment hiç çizilmez; yine de çağrılırsa durum
    // değişmez (eski form ABD bilmez).
    if (!state.abdAcik || abd == state.isAbd) return AlanYazimi.yok;
    _set(state.copyWith(
      subCategory: abd ? StockSubCategory.abd.name : null,
      currency: abd ? 'USD' : AssetType.hisse.defaultCurrency,
      bist100Ticker: null,
      isManualPrice: false,
      previewPrice: null,
    ));
    return const AlanYazimi(ticker: '', name: '');
  }

  /// ABD kataloğundan seçim. Sembol alana yazılır ([resolveIdentity] onu
  /// okur); elle fiyat bayrağı [selectBist100]'deki gerekçeyle iner.
  AlanYazimi selectAbdHisse(String ticker) {
    _set(state.copyWith(isManualPrice: false));
    return AlanYazimi(ticker: ticker, name: abdHisseleri[ticker] ?? ticker);
  }

  /// Eurobond katalogdan seçildi (ya da düzenlemede sözleşme yüklendi).
  ///
  /// Para birimi tahvilinkine kilitlenir. Temiz fiyat yalnız alan boşsa ve
  /// piyasa fiyatı biliniyorsa önerilir (fondaki kural: kullanıcının yazdığı
  /// ezilmez). [duzenlemeBirimDegeri]: düzenlenen lotun kayıtlı birim değeri
  /// (kirli/100) — alana TEMİZ % olarak geri çevrilip yazılır.
  AlanYazimi selectEurobond(
    EurobondSozlesmesi s,
    EurobondFiyati? f, {
    required bool priceEmpty,
    double? duzenlemeBirimDegeri,
  }) {
    _set(state.copyWith(
      eurobondSozlesmesi: s,
      eurobondFiyati: f,
      currency: s.paraBirimi,
      isManualPrice: false,
    ));
    String? fiyat;
    if (duzenlemeBirimDegeri != null && duzenlemeBirimDegeri > 0) {
      fiyat = fmtInputTr(
          eurobondTemizYuzde(s, duzenlemeBirimDegeri, state.addedDate),
          maxDigits: 4);
    } else if (priceEmpty && f?.temizFiyat != null) {
      fiyat = fmtInputTr(f!.temizFiyat!, maxDigits: 4);
    }
    return AlanYazimi(
      ticker: eurobondSembolu(s.isin),
      name: s.ad,
      price: fiyat,
    );
  }

  /// [priceEmpty]: fon fiyatı yalnızca alış fiyatı boşsa doldurulur —
  /// kullanıcının yazdığı değer ezilmez.
  AlanYazimi selectFund(TefasFund fund, {required bool priceEmpty}) {
    _set(state.copyWith(selectedFund: fund));
    return AlanYazimi(
      ticker: 'TEFAS:${fund.code}',
      name: fund.name,
      price: fund.price > 0 && priceEmpty ? fmtInput(fund.price) : null,
    );
  }

  /// Kripto katalogdan seçildi. Sembol her zaman katalogdaki koddan kurulur
  /// (serbest metin sunucunun tanımadığı sembol üretirdi → fiyatsız lot).
  /// Fiyat, fondaki gibi yalnızca alış fiyatı boşsa önerilir.
  AlanYazimi selectKripto(KriptoKatalogOgesi o, {required bool priceEmpty}) {
    _set(state.copyWith(isManualPrice: false));
    final fiyat = o.fiyat?.fiyatTry;
    return AlanYazimi(
      ticker: kriptoSembolu(o.kod),
      name: o.gorunenAd,
      price: fiyat != null && priceEmpty ? fmtInput(fiyat) : null,
    );
  }

  /// Hızlı girişten tek satır: tür ve (varsa) döviz alt kategorisi kurulur,
  /// miktar/fiyat alanları doldurulur.
  AlanYazimi applyParsedEntry(ParsedEntry entry) {
    var next = state.copyWith(
      type: entry.type,
      currency: entry.type.defaultCurrency,
    );
    String? ticker;
    String? name;
    if (entry.type == AssetType.kripto && entry.subCategory != null) {
      // Kod alt kategori DEĞİL, sembolün kendisi (`KRIPTO:BTC`).
      ticker = kriptoSembolu(entry.subCategory!);
      name = entry.subCategory;
    } else if (entry.subCategory != null) {
      next = next.copyWith(subCategory: entry.subCategory);
      if (entry.type == AssetType.doviz) {
        final opt = dovizOptFor(entry.subCategory);
        ticker = opt.ticker;
        name = opt.name;
        next = next.copyWith(currency: 'TRY');
      }
    }
    _set(next);
    return AlanYazimi(
      ticker: ticker,
      name: name,
      quantity: fmtInput(entry.qty),
      price: entry.price > 0 ? fmtInput(entry.price) : null,
    );
  }

  /// Sayıyı giriş alanına yazılacak biçimde verir: tam sayı ise ondalıksız,
  /// ondalık `,` ile (`fmtInputTr` — `parseTrNumber` ile gidiş-dönüş).
  static String fmtInput(double v) => fmtInputTr(v);

  // ── Önizleme ───────────────────────────────────────────────────────────
  //
  // Sembol/tarih değişince 400 ms debounce ile çalışır; sıra sayacı eski
  // isteğin sonucunu yutar. Kullanıcı fiyatı kendisi yazdıysa gösterilmez.

  void schedulePreview({
    required double? userPrice,
    required String tickerText,
  }) {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(
      const Duration(milliseconds: 400),
      () => refreshPreview(userPrice: userPrice, tickerText: tickerText),
    );
  }

  Future<void> refreshPreview({
    required double? userPrice,
    required String tickerText,
    DateTime? now,
  }) async {
    if (_disposed) return;
    final ticker = state.resolveTicker(tickerText);
    final gereksiz = (userPrice != null && userPrice > 0) ||
        ticker == null ||
        ticker.isEmpty;
    if (gereksiz) {
      if (state.previewPrice != null || state.previewLoading) {
        _set(state.copyWith(previewPrice: null, previewLoading: false));
      }
      return;
    }

    final seq = ++_previewSeq;
    _set(state.copyWith(previewLoading: true));
    final sonuc = await fiyatBul(
      lookup: ref.read(addAssetPriceLookupProvider),
      ticker: ticker,
      date: state.addedDate,
      now: now,
    );
    if (seq != _previewSeq || _disposed) return;
    _set(state.copyWith(
      previewPrice: sonuc.price,
      previewIsHistorical: sonuc.historical,
      previewLoading: false,
    ));
  }

  /// Kayıt için fiyat: aynı kural, ama `saving` bayrağı açılır ki buton
  /// kilitlensin.
  Future<FiyatSonucu> fiyatCoz(String ticker) async {
    setSaving(true);
    try {
      return await fiyatBul(
        lookup: ref.read(addAssetPriceLookupProvider),
        ticker: ticker,
        date: state.addedDate,
      );
    } finally {
      setSaving(false);
    }
  }
}

final addAssetFormProvider = NotifierProvider.autoDispose
    .family<AddAssetFormNotifier, AddAssetFormState, AddAssetFormArgs>(
  AddAssetFormNotifier.new,
);
