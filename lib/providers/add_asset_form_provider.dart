import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../models/asset_categories.dart';
import '../models/asset_type.dart';
import '../services/price_service.dart';
import '../services/tefas_service.dart';
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

/// Bir hızlı giriş satırını çözer. Desteklenen biçimler:
///   "100 dolar"                  → 100 USD (fiyatsız)
///   "100 dolar 32 liradan"       → qty=100, price=32, USD
///   "10 gram altın 4500 liradan" → qty=10, price=4500
///   "GARAN 500 adet 105 lira"    → qty=500, price=105
/// Miktar bulunamazsa `null`.
ParsedEntry? parseQuickEntry(String raw) {
  final text = raw.toLowerCase().trim();
  if (text.isEmpty) return null;

  var detectedType = AssetType.hisse;
  String? detectedSub;

  if (RegExp(r'dolar|usd').hasMatch(text)) {
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

  // "1.000" binlik ayracı: noktayı yalnızca üç haneli grup önündeyse at.
  final normalized = text.replaceAll(RegExp(r'(?<=\d)\.(?=\d{3})'), '');
  final numMatches = RegExp(r'(\d+([.,]\d+)?)').allMatches(normalized).toList();
  double qty = 0;
  double price = 0;

  if (numMatches.isNotEmpty) {
    qty = double.tryParse(numMatches.first.group(1)!.replaceAll(',', '.')) ?? 0;
  }
  final priceHint =
      RegExp(r'(\d+([.,]\d+)?)\s*(lira|tl|₺)').firstMatch(normalized);
  if (priceHint != null) {
    price = double.tryParse(priceHint.group(1)!.replaceAll(',', '.')) ?? 0;
  } else if (numMatches.length >= 2) {
    price = double.tryParse(numMatches[1].group(1)!.replaceAll(',', '.')) ?? 0;
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
  });

  /// Açılış değerleri. Öncelik: düzenlenen kayıt > sepet öğesi > prefill
  /// (karşılaştırma ekranından gelen tür/ticker/ad) > varsayılan.
  factory AddAssetFormState.initial({
    Asset? editingAsset,
    BulkCartItem? cartInitial,
    String? prefillTicker,
    AssetType? prefillType,
    DateTime? now,
  }) {
    final a = editingAsset;
    final c = cartInitial;
    final type = a?.type ?? c?.type ?? prefillType ?? AssetType.hisse;
    final ticker = a?.ticker ?? c?.ticker ?? prefillTicker ?? '';
    // BIST prefill'inde alt kategori de kurulmalı, yoksa BIST100 seçici boş
    // açılır ve seçili hisse görünmez.
    final subCat = a?.subCategory ??
        c?.subCategory ??
        (prefillType == AssetType.hisse && (prefillTicker?.endsWith('.IS') ?? false)
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
      currency: a?.currency ?? c?.currency ?? type.defaultCurrency,
      isManualPrice: a?.isManualPrice ?? (c != null && c.ticker.isEmpty),
      addedDate: a?.addedDate ?? c?.addedDate ?? now ?? DateTime.now(),
      bist100Ticker: isBist100 && ticker.isNotEmpty ? ticker : null,
      selectedFund: fund,
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

  bool get isBist100 =>
      type == AssetType.hisse && subCategory == StockSubCategory.bist100.label;
  bool get isFon => type == AssetType.fon;
  bool get isDoviz => type == AssetType.doviz;
  bool get isAltin => type == AssetType.altin;

  String get quantitySuffix {
    if (isDoviz) return subCategory ?? 'Adet';
    return unitLabel(unitType);
  }

  static String unitLabel(String unitType) {
    for (final u in UnitType.values) {
      if (u.name == unitType || u.shortcode == unitType) return u.label;
    }
    return 'Adet';
  }

  List<String> get quantityPresets {
    if (unitType == 'gram') return const ['1', '5', '10', '50', '100'];
    if (unitType == 'ounce') return const ['0.1', '0.5', '1', '5', '10'];
    if (type == AssetType.fon) return const ['1', '10', '100', '1000'];
    if (type == AssetType.hisse) return const ['1', '5', '10', '100', '1000'];
    return const ['1', '5', '10', '100'];
  }

  /// Önizleme/kayıt için sembol. Serbest metin alanı yalnızca hisse-diğer,
  /// emtia ve "diğer" türlerinde anlamlıdır; ötekiler seçimden türer.
  String? resolveTicker(String tickerText) {
    if (isBist100) return bist100Ticker;
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
    final manual = isFon
        ? false
        : isAltin
            ? ticker.isEmpty
            : isDoviz
                ? ticker.isEmpty
                : isManualPrice || ticker.isEmpty;
    return (ticker: ticker, name: name, manual: manual);
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
      );
}

const _keep = Object();

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
  });
  final Asset? editingAsset;
  final BulkCartItem? cartInitial;
  final String? prefillTicker;
  final AssetType? prefillType;
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
    );
  }

  // Bu sayı kayıt/önizleme yarışlarında "canlı mıyım" sorusunun cevabıdır;
  // dispose sonrası state ataması Riverpod'da hata fırlatır.
  void _set(AddAssetFormState s) {
    if (!_disposed) state = s;
  }

  // ── Basit alanlar ──────────────────────────────────────────────────────

  void setSaving(bool v) => _set(state.copyWith(saving: v));
  void setCurrency(String v) => _set(state.copyWith(currency: v));
  void setDate(DateTime v) => _set(state.copyWith(addedDate: v));
  void setManualPrice(bool v) => _set(state.copyWith(isManualPrice: v));
  void toggleNotes() =>
      _set(state.copyWith(notesExpanded: !state.notesExpanded));

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
    ));
    return const AlanYazimi(ticker: '', name: '');
  }

  /// Serbest sembol alanına yazıldı: BIST100 seçimi düşer, alt kategori
  /// "Diğer Hisseler" olur. Alan boşaldıysa fiyat elle girilecek demektir.
  void tickerTyped(String v) {
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

  AlanYazimi selectBist100(String ticker) {
    _set(state.copyWith(bist100Ticker: ticker));
    return AlanYazimi(
      ticker: ticker,
      name: bist100StocksMap[ticker] ?? ticker.replaceAll('.IS', ''),
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

  /// Hızlı girişten tek satır: tür ve (varsa) döviz alt kategorisi kurulur,
  /// miktar/fiyat alanları doldurulur.
  AlanYazimi applyParsedEntry(ParsedEntry entry) {
    var next = state.copyWith(
      type: entry.type,
      currency: entry.type.defaultCurrency,
    );
    String? ticker;
    String? name;
    if (entry.subCategory != null) {
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

  /// Sayıyı giriş alanına yazılacak biçimde verir: tam sayı ise ondalıksız.
  static String fmtInput(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

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
