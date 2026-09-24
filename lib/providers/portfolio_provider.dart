import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../services/analytics_service.dart';
import '../services/supabase_service.dart';
import '../services/price_service.dart';
import '../services/retention_tracker.dart';
import '../services/sparkline_service.dart';
import 'auth_provider.dart';
import 'preferences_provider.dart';
import '../utils/friendly_error.dart';
import '../utils/money_format.dart';
import '../utils/tr_format.dart';
import '../services/crash_reporter.dart';
import '../services/daily_summary.dart';
import '../services/fx_rate_migration_service.dart';
import '../services/portfolio_cache.dart';
import '../services/tazelik_ritmi.dart';

const _uuid = Uuid();

/// Free tier varlık limiti aşıldığında `addAsset` bunu fırlatır. UI yakalayıp
/// paywall gösterir + `premium_gate_shown` event log'lar.
class AssetLimitExceededException implements Exception {
  final int currentCount;
  final int limit;
  const AssetLimitExceededException(this.currentCount, this.limit);
  @override
  String toString() =>
      'AssetLimitExceededException(current: $currentCount, limit: $limit)';
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class PortfolioState {
  final List<Asset> assets;
  final bool isLoading;
  final String? errorMessage;
  final DateTime? lastUpdated;
  final double usdTry;
  final double eurTry;
  final double gbpTry;

  /// 22 ayar gram altının TRY fiyatı — yalnızca baz para birimi "gram altın"
  /// seçiliyken çekilir (Faz 3.2); 0 = bilinmiyor, gösterim ₺'ye düşer.
  final double goldGramTry;

  /// Defterin SAHİBİ (auth kullanıcı id'si); `''` = henüz bilinmiyor.
  ///
  /// Neden var (2026-09-21): uygulama dışı yüzeyler (kilit ekranı, ana
  /// ekran widget'ı) süreç ömrü boyunca yaşayan singleton'lar ve ortak bir
  /// gün içi seri önbelleğiyle beslenir. Kullanıcı değişince o önbellek
  /// "kime ait" bilmiyordu; çıkan kullanıcının serisi 5 dakika boyunca
  /// yeni kullanıcının toplamıyla birleştirilip kâr/zarar diye
  /// gösteriliyordu. Sahip damgası state'in kendisinde taşınır ki veri
  /// katmanı "bu seri bu deftere mi ait" sorusunu kendisi sorabilsin;
  /// `copyWith` korur, görünüm türevleri (ortak/Birlikte) de aynı sahibi
  /// taşır — onlar hiçbir yüzeye itilmez.
  final String ownerId;

  const PortfolioState({
    this.assets = const [],
    this.isLoading = false,
    this.errorMessage,
    this.lastUpdated,
    this.usdTry = 1.0,
    this.eurTry = 1.0,
    this.gbpTry = 1.0,
    this.goldGramTry = 0,
    this.ownerId = '',
  });

  PortfolioState copyWith({
    List<Asset>? assets,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    DateTime? lastUpdated,
    double? usdTry,
    double? eurTry,
    double? gbpTry,
    double? goldGramTry,
    String? ownerId,
  }) =>
      PortfolioState(
        assets: assets ?? this.assets,
        isLoading: isLoading ?? this.isLoading,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        usdTry: usdTry ?? this.usdTry,
        eurTry: eurTry ?? this.eurTry,
        gbpTry: gbpTry ?? this.gbpTry,
        goldGramTry: goldGramTry ?? this.goldGramTry,
        ownerId: ownerId ?? this.ownerId,
      );

  double toTRY(double amount, String currency) {
    switch (currency.toUpperCase()) {
      case 'USD':
        return amount * usdTry;
      case 'EUR':
        return amount * eurTry;
      case 'GBP':
        return amount * gbpTry;
      default:
        return amount;
    }
  }

  /// Hesaplara giren kayıtlar: yumuşak silinmemiş VE mezar taşı olmayan.
  ///
  /// [assets] HAM LEDGER'dır — hareket listesi onu olduğu gibi gösterir
  /// (silinmiş bir varlığın Alım/Satım/Temettü geçmişi de görünsün diye).
  /// Toplam/maliyet/getiri hesaplayan HER ŞEY bunun yerine bu görünümü
  /// kullanmalı; aksi halde silinen varlık portföy değerine geri sızar.
  List<Asset> get activeAssets =>
      assets.where((a) => a.isActive).toList(growable: false);

  /// Portföyün güncel TRY değeri — NET pozisyondan.
  ///
  /// ## Neden ham `activeAssets` toplanamaz
  /// `Asset.totalValue` = `quantity * currentPrice`, yani İŞARETSİZ.
  /// Satış lot'u da pozitif miktar taşıdığı için ham toplama EKLENİYORDU;
  /// oysa satış pozisyonu azaltır. Ölçüldü: 10 alıp 4 satan kullanıcıda
  /// net 6 lot = 600 TL beklenirken 1.400 TL çıkıyordu.
  ///
  /// Kullanıcı bildirimi (2026-09-12): ana ekran 2.519.470 TL, performans
  /// ekranı 2.517.574 TL gösteriyordu. Performans ekranı zaten
  /// `aggregatePositions` kullandığı için DOĞRU olan oydu.
  ///
  /// `aggregatePositions` ayrıca temettü (`quantity: 0`) ve mezar taşı
  /// satırlarını da eler — tek kaynak, tek kural.
  ///
  /// **Sahip sınırı (denetim 2026-09-22):** `aggregatePositions` düz liste
  /// üzerinde çalışıyordu ve `positionKey` sahip taşımaz — Birlikte
  /// defterinde iki kişinin aynı hissesi tek pozisyona düşüyor, birinin
  /// satışı diğerinin lot'unu düşürüyordu. `totalCost`/`capitalGainLoss`
  /// ile AYNI kaynağa bağlandı; üç sayı tek kümeden beslenmezse
  /// "Σ parça == bütün" değişmezi kırılır.
  double get totalValue =>
      ownerScopedTotalValue(lotlarSahibeGore(assets), toTRY: toTRY);

  /// Maliyet tabanı (TRY) — AÇIK pozisyonların maliyeti, temettü hariç.
  ///
  /// ## İki hata birden düzeltildi (denetim, 2026-09-22)
  ///
  /// **1. Satış lot'ları maliyete sayılıyordu.** Eski hâli ham
  /// `activeAssets` üzerinden topluyordu; satış lot'unun `currentPrice`'ı
  /// dolu olduğu için filtreyi geçiyor ve maliyete giriyordu. Ölçüldü:
  /// 10 al @100 + 4 sat @130 defterinde taban ₺1.400 çıkıyordu (gerçek:
  /// ₺600, çünkü elde 6 lot var). Yalnızca satış lot'u olan defterde ise
  /// taban ₺400, kâr +₺80, yüzde %20 görünüyordu — elde HİÇBİR ŞEY yokken.
  ///
  /// **2. Sahip sınırı yoktu.** `positionKey` sahip taşımaz; Birlikte
  /// görünümünde iki kişinin aynı hissesi tek pozisyona düşüyor ve birinin
  /// satışı diğerinin lot'unu düşürüyordu (bkz. `aggregatePositionsByOwner`
  /// — aynı hata sınıfı toplam değerde daha önce kapatılmıştı, kâr/zararda
  /// açık kalmıştı).
  ///
  /// `totalValue` zaten `aggregatePositions` kullanıyordu; bu alan da aynı
  /// kaynağa bağlandı. Üç sayı (değer, maliyet, kâr) artık TEK kümeden
  /// besleniyor — Σ parça == bütün yapısal olarak korunuyor.
  double get totalCost =>
      ownerScopedCostBasis(lotlarSahibeGore(assets), toTRY: toTRY);

  /// Tahsil edilen nakit temettü toplamı (TRY).
  ///
  /// Fiyat filtresine TABİ DEĞİL: temettü zaten cebe girmiş realize gelirdir,
  /// varlığın güncel fiyatının bilinip bilinmemesiyle ilgisi yoktur.
  double get totalDividend => totalDividendTRY(assets);

  /// Sermaye kazancı — temettü HARİÇ (yalnızca fiyat hareketi).
  ///
  /// [totalCost] ile AYNI pozisyon kümesinden gelir; ayrışırlarsa yüzde,
  /// payı olmayan bir paydaya bölünür.
  double get capitalGainLoss =>
      ownerScopedCapitalGainLoss(lotlarSahibeGore(assets), toTRY: toTRY);

  /// Toplam getiri — sermaye kazancı + tahsil edilen temettü.
  ///
  /// Temettü eklenmezse uygulama getiriyi olduğundan DÜŞÜK gösterir; BIST'te
  /// temettü getirinin büyük parçasıdır.
  double get gainLoss => capitalGainLoss + totalDividend;

  /// Getiri yüzdesi — [gainLoss] (temettü dahil) / yatırılan sermaye.
  ///
  /// ## Payda neden yalnızca [totalCost] değil (denetim, 2026-09-22)
  /// Pay temettüyü İÇERİR ([gainLoss]) ve temettü ham defterden gelir,
  /// yani KAPANMIŞ pozisyonlarınkini de sayar. Payda ise yalnızca AÇIK
  /// pozisyonların maliyetiydi. İki taraf aynı kümeyi ölçmediği için
  /// yüzde, payı olmayan bir paydaya bölünüyordu.
  ///
  /// En net belirti: her şeyini satmış ama temettü almış kullanıcıda
  /// `totalCost == 0` → yüzde **%0** yazıyor, hemen yanındaki tutar ise
  /// **₺50 kâr** diyordu. İki rakam yan yana duruyor ve birbiriyle
  /// çelişiyordu.
  ///
  /// Çözüm payı daraltmak DEĞİL paydaya kapanmış pozisyonların
  /// maliyetini eklemek: üst kartta ₺ ile % YAN YANA çizilir
  /// (`portfolio_summary_widget`), ikisi aynı şeyi ölçmek zorunda.
  /// Payı `capitalGainLoss` yapmak yüzdeyi tutardı ama tutarı bozardı.
  ///
  /// Payda = açık pozisyonların maliyeti + kapanmış pozisyonlara bağlanan
  /// sermaye. İkincisi ancak temettü/realize varken devreye girer, yani
  /// olağan portföyde davranış DEĞİŞMEZ.
  double get gainLossPercentage {
    final payda = totalCost > 0 ? totalCost : kapanmisSermaye;
    return payda > 0 ? gainLoss / payda * 100 : 0;
  }

  /// Tamamen satılmış pozisyonlara bağlanmış olan alım sermayesi (TRY).
  ///
  /// [gainLossPercentage] paydasının ikinci parçası: elde bir şey
  /// kalmamış olsa bile o para bir zaman yatırılmıştı ve temettü/realize
  /// getirisi ona göre ölçülür. Açık pozisyonların maliyeti burada
  /// SAYILMAZ — çift sayma olurdu.
  double get kapanmisSermaye {
    final acik = <String>{
      for (final p in aggregatePositionsByOwner(lotlarSahibeGore(activeAssets)))
        '${p.lots.first.userId}|${p.key}',
    };
    double t = 0;
    for (final a in activeAssets) {
      if (!a.isBuy) continue;
      if (acik.contains('${a.userId}|${positionKey(a)}')) continue;
      t += a.totalCostTRY;
    }
    return t;
  }

  /// Satışlardan GERÇEKLEŞEN kâr/zarar (TRY), temettü HARİÇ.
  ///
  /// Değerlendirme (2026-09) §5.5: satış fiyatı `sell_price`'ta saklanıyor,
  /// satış satırı alım maliyetini (`purchasePrice`, ağırlıklı ortalama) ve
  /// alım kurunu taşıyor — ama hiçbir ekran "sattıklarımdan ne kazandım"
  /// demiyordu. Hesap: Σ (satış fiyatı − maliyet) × miktar × alım kuru.
  /// `sell_price` olmayan eski satış satırları atlanır — uydurmak yerine
  /// eksik bırakılır.
  /// **Komisyon (denetim, 2026-09-22):** satış komisyonu buradan DÜŞER.
  /// Eskiden `aggregatePositions` onu AÇIK pozisyonun maliyetine ekliyordu
  /// (yanlış yer: satılan lot'un masrafı elde kalan lot'un alım maliyeti
  /// değildir) ve burada hiç düşülmüyordu. Tamamen satılmış pozisyonda
  /// ise komisyon tamamen kayboluyordu — pozisyon aggregate sonucundan
  /// düştüğü için. Ham defterden okunuyor: kapanmış pozisyonun
  /// masrafı da cepten çıkmıştır.
  double get realizedGainLoss {
    double t = 0;
    for (final a in activeAssets) {
      if (!a.isSell || a.sellPrice == null) continue;
      t += (a.sellPrice! - a.purchasePrice) * a.quantity * a.purchaseFxRate;
      t -= a.commission * a.purchaseFxRate;
    }
    return t;
  }

  /// Gerçekleşmiş bir şey var mı — özet kartı satırı yalnızca o zaman çıkar.
  bool get hasRealized =>
      activeAssets.any((a) => a.isSell && a.sellPrice != null);
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class PortfolioNotifier extends AsyncNotifier<PortfolioState> {
  @override
  Future<PortfolioState> build() async {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const PortfolioState();

    final List<Asset> assets;
    try {
      assets = await SupabaseService.instance.fetchByUser(user.id);
      // Başarılı çekim → son bilinen defteri diske yaz (PortfolioCache).
      CrashReporter.arkaPlan(PortfolioCache.write(user.id, assets), reason: 'portfolio_provider.PortfolioCache.write');
    } catch (e, st) {
      // Ağ yok / sunucu yok: son bilinen defterle aç. Eskiden burada hata
      // fırlıyor ve uçak modunda uygulama boş ekran + "Tekrar dene" ile
      // açılıyordu; kullanıcının dün gördüğü portföy dün gecenin
      // fiyatlarıyla bile bir şey ifade eder. Önbellek yoksa hata yukarı
      // çıkar — eski davranış.
      final cached = await PortfolioCache.read(user.id);
      if (cached == null) rethrow;
      CrashReporter.report(e, st,
          reason: 'PortfolioNotifier.build (önbellekten açıldı)');
      return PortfolioState(
        assets: cached,
        errorMessage: 'Çevrimdışı — son bilinen veriler gösteriliyor.',
        ownerId: user.id,
      );
    }
    return PortfolioState(
      assets: assets,
      ownerId: user.id,
    );
  }

  // ---- CRUD ----------------------------------------------------------------

  /// Yeni lot'un `purchaseFxRate`'i — ALIM GÜNÜNÜN kuru.
  ///
  /// Eskiden her zaman BUGÜNÜN canlı kuru yazılıyordu: geriye tarihli
  /// dövizli alımın maliyeti kalıcı olarak yanlış kalıyordu. Kurlar henüz
  /// yüklenmemişken (yeni kullanıcının ilk açılışı, çevrimdışı) de 1.0
  /// yazılıyor ve varlık saatlerce ~%4000 kâr gösteriyordu (2026-09-23
  /// denetimi F4). Sıra: bugünkü alımda canlı kur; değilse alım gününün
  /// kapanış kuru. İkisi de bilinmiyorsa 1.0 YER TUTUCU kalır — uydurma bir
  /// kur değil, `FxRateMigrationService`'in tanıdığı "henüz bilinmiyor"
  /// işaretidir ve ilk fırsatta alım günü kuruyla onarılır.
  Future<double> _alisKuru(
      String currency, DateTime? addedDate, PortfolioState s) async {
    final canli = _fxRateForCurrency(currency, s);
    final sembol = FxRateMigrationService.fxSembolu(currency);
    if (sembol == null) return canli;
    final simdi = DateTime.now();
    final gun = addedDate ?? simdi;
    final geriTarihli = dayKey(gun).isBefore(dayKey(simdi));
    if (!geriTarihli && canli > 1.0) return canli;
    try {
      final r = await PriceService.instance.fetchHistoricalFxRate(sembol, gun);
      if (r != null && r > 1.0) return r;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'PortfolioNotifier._alisKuru');
    }
    return 1.0;
  }

  double _fxRateForCurrency(String currency, PortfolioState s) {
    switch (currency.toUpperCase()) {
      case 'USD':
        return s.usdTry > 1.0 ? s.usdTry : 1.0;
      case 'EUR':
        return s.eurTry > 1.0 ? s.eurTry : 1.0;
      case 'GBP':
        return s.gbpTry > 1.0 ? s.gbpTry : 1.0;
      default:
        return 1.0;
    }
  }

  /// Defter DEĞİŞTİ: gün içi seri önbelleğini düşür.
  ///
  /// ## Neden (denetim, 2026-09-22) — sahte günlük kâr
  /// Günlük kâr/zarar `(son − gün başı) − nakit akışı` formülüyle
  /// hesaplanır. `son` CANLI toplamdır (yeni lot dahil), `gün başı` ise
  /// önbellekteki seriden gelir ve yeni lot'tan HABERSİZDİR. Seri
  /// tazelenmediği sürece işlem, serinin içine yayılmak yerine yalnızca
  /// ucuna yapışıyor — yani `inflowOnDay` çıkarılacak bir şey bulamadan
  /// fark önce "hareket" olarak sayılıyor.
  ///
  /// Ölçüldü: sabah 10 lot (₺1.000) olan kullanıcı fiyat HIÇ oynamadan
  /// ₺120'den 5 lot daha aldığında **+₺200 / +%12,5** sahte kâr
  /// görüyordu. Satışta ters yönde aynısı: 4 lot satınca **+₺240 / +%24**.
  ///
  /// Dört yüzey bu önbelleği paylaşıyor (Bugün kartı, Performans › Özet
  /// günlük, ana ekran widget'ı, Live Activity) ve hiçbir mutasyon yolu
  /// onu düşürmüyordu — önbellek yalnızca çıkışta temizleniyordu.
  ///
  /// `clear()` veriyi SİLER ve bir sonraki çağrı yeniden çeker; bu doğru
  /// davranışın kendisidir çünkü eldeki seri artık YANLIŞ bir deftere
  /// ait. (Tazelik bayrağı yetmezdi: eski seri fetch bitene kadar
  /// gösterilmeye devam eder ve sahte kâr o pencerede sürerdi.)
  void _gunIciSeriyiDusur() => IntradaySeriesCache.instance.clear();

  Future<void> addAsset({
    required String name,
    required String ticker,
    required AssetType type,
    required double quantity,
    required double purchasePrice,
    required String currency,
    required String notes,
    required bool isManualPrice,
    String? subCategory,
    String unitType = 'piece',
    DateTime? addedDate,
    double? initialCurrentPrice,
    double commission = 0,
  }) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    final currentState = state.valueOrNull ?? const PortfolioState();

    // ── Free tier gate: distinct pozisyon (buy lot) sayısını kontrol et ─────
    // Position aggregation'a göre count ediyoruz: aynı ticker'a ek lot ekleme
    // yeni "varlık" sayılmasın (kullanıcı zaten sahip olduğuna ekliyor).
    final limit = ref.read(assetLimitProvider);
    if (limit < (1 << 30)) {
      final existingKeys = <String>{};
      for (final a in currentState.assets) {
        // Silinmiş varlık kotayı işgal etmemeli — kullanıcı sildiği halde
        // limite takılırdı.
        if (a.isBuy && a.isActive) {
          existingKeys.add('${a.type.name}|${a.ticker}|${a.currency}');
        }
      }
      final newKey = '${type.name}|$ticker|$currency';
      if (!existingKeys.contains(newKey) && existingKeys.length >= limit) {
        unawaited(AnalyticsService.instance
            .logPremiumGateShown(feature: 'asset_limit'));
        throw AssetLimitExceededException(existingKeys.length, limit);
      }
    }

    final fxRate = await _alisKuru(currency, addedDate, currentState);

    final asset = Asset(
      id: _uuid.v4(),
      userId: user.id,
      name: name,
      ticker: ticker,
      type: type,
      quantity: quantity,
      purchasePrice: purchasePrice,
      currency: currency,
      notes: notes,
      isManualPrice: isManualPrice,
      subCategory: subCategory,
      unitType: unitType,
      purchaseFxRate: fxRate,
      kind: AssetKind.buy,
      addedDate: addedDate,
      currentPrice: initialCurrentPrice,
      commission: commission,
    );
    if (asset.purchasePrice == 0 && asset.currentPrice > 0) {
      asset.purchasePrice = asset.currentPrice;
    }

    await SupabaseService.instance.insertAsset(asset);

    unawaited(AnalyticsService.instance.logAssetAdded(
      type: type.name,
      subCategory: subCategory,
    ));

    // Aktivasyon eşikleri: ilk varlık ve üçüncü varlık D30 tutunmanın en
    // güçlü tahmincileri. Servis tekrarı kendi eler, buradan koşulsuz
    // çağrılır. Silinmiş lot sayılmaz — kullanıcı silip yeniden eklediğinde
    // eşik zaten bir kez işaretlenmiş olur.
    // Lot değil DISTINCT pozisyon sayılır: aynı hisseye üç kez ekleme yapan
    // kullanıcı "üç varlık" eşiğini geçmiş sayılmamalı — limit kapısıyla
    // (yukarıda) aynı anahtar formülü kullanılır.
    final pozisyonlar = <String>{'${type.name}|$ticker|$currency'};
    for (final a in currentState.assets) {
      if (a.isBuy && a.isActive) {
        pozisyonlar.add('${a.type.name}|${a.ticker}|${a.currency}');
      }
    }
    CrashReporter.arkaPlan(RetentionTracker.instance.recordAssetCount(pozisyonlar.length), reason: 'portfolio_provider.RetentionTracker.recordAssetCount');

    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(assets: [asset, ...current.assets]));
      _gunIciSeriyiDusur();
    } else {
      final assets = await SupabaseService.instance.fetchByUser(user.id);
      state = AsyncData(PortfolioState(
        assets: assets,
        ownerId: user.id,
      ));
    }
  }

  Future<void> addSellTransaction({
    required Asset asset,
    required double quantity,
    double? sellPrice,
  }) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    final transaction = Asset(
      id: _uuid.v4(),
      userId: user.id,
      name: asset.name,
      ticker: asset.ticker,
      type: asset.type,
      quantity: quantity,
      purchasePrice: asset.purchasePrice,
      currency: asset.currency,
      notes: asset.notes,
      isManualPrice: asset.isManualPrice,
      subCategory: asset.subCategory,
      unitType: asset.unitType,
      purchaseFxRate: asset.purchaseFxRate,
      currentPrice: asset.currentPrice,
      lastUpdated: asset.lastUpdated,
      kind: AssetKind.sell,
      refAssetId: asset.id.startsWith('pos:') ? null : asset.id,
      sellPrice: sellPrice,
    );

    await SupabaseService.instance.insertAsset(transaction);

    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(assets: [transaction, ...current.assets]));
      _gunIciSeriyiDusur();
    }
  }

  /// Nakit temettü kaydı ekler.
  ///
  /// Temettü satırı miktarı DEĞİŞTİRMEZ — `quantity: 0` ile yazılır ve
  /// `dividendAmount` alanında ele geçen net tutarı taşır. `purchaseFxRate`
  /// burada ÖDEME GÜNÜ kurunu tutar (alım kurunu değil), böylece TRY karşılığı
  /// temettünün alındığı günün kuruyla sabitlenir.
  Future<void> addDividend({
    required Asset asset,
    required double amount,
    DateTime? paidAt,
  }) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    if (amount <= 0) return;
    // Yalnızca hisse temettü dağıtır — UI zaten butonu gizliyor, bu ikinci
    // savunma başka bir giriş noktası eklendiğinde kuralı korur.
    if (!asset.supportsDividend) return;

    final currentState = state.valueOrNull ?? const PortfolioState();
    // Ödeme günü kuru — alımdaki kuralın aynısı (bkz. [_alisKuru]).
    final fxRate = await _alisKuru(asset.currency, paidAt, currentState);

    final transaction = Asset(
      id: _uuid.v4(),
      userId: user.id,
      name: asset.name,
      ticker: asset.ticker,
      type: asset.type,
      // Miktar 0 — temettü pozisyona dokunmaz.
      quantity: 0,
      purchasePrice: 0,
      currency: asset.currency,
      notes: '',
      isManualPrice: asset.isManualPrice,
      subCategory: asset.subCategory,
      unitType: asset.unitType,
      purchaseFxRate: fxRate,
      currentPrice: asset.currentPrice,
      kind: AssetKind.dividend,
      refAssetId: asset.id.startsWith('pos:') ? null : asset.id,
      addedDate: paidAt,
      dividendAmount: amount,
    );

    await SupabaseService.instance.insertAsset(transaction);

    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(
          current.copyWith(assets: [transaction, ...current.assets]));
      _gunIciSeriyiDusur();
    }
  }

  Future<void> updateAsset(Asset asset) async {
    await SupabaseService.instance.updateAsset(asset);
    unawaited(AnalyticsService.instance.logAssetUpdated(type: asset.type.name));
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(
        assets:
            current.assets.map((a) => a.id == asset.id ? asset : a).toList(),
      ));
      _gunIciSeriyiDusur();
    }
  }

  Future<void> deleteAsset(String id) async {
    final current = state.valueOrNull;
    Asset? deleted;
    if (current != null) {
      for (final asset in current.assets) {
        if (asset.id == id) {
          deleted = asset;
          break;
        }
      }
    }
    Asset? transaction;
    if (deleted != null) {
      transaction = Asset(
        id: _uuid.v4(),
        userId: deleted.userId,
        name: deleted.name,
        ticker: deleted.ticker,
        type: deleted.type,
        quantity: deleted.quantity,
        purchasePrice: deleted.purchasePrice,
        currency: deleted.currency,
        notes: deleted.notes,
        isManualPrice: deleted.isManualPrice,
        subCategory: deleted.subCategory,
        unitType: deleted.unitType,
        purchaseFxRate: deleted.purchaseFxRate,
        currentPrice: deleted.currentPrice,
        lastUpdated: deleted.lastUpdated,
        kind: AssetKind.deleteLog,
        refAssetId: deleted.id,
      );
      await SupabaseService.instance.insertAsset(transaction);
      unawaited(AnalyticsService.instance.logAssetDeleted(type: deleted.type.name));
    }
    await SupabaseService.instance.deleteAsset(id);
    if (current != null) {
      state = AsyncData(current.copyWith(
        assets: [
          if (transaction != null) transaction,
          ...current.assets.where((a) => a.id != id),
        ],
      ));
      _gunIciSeriyiDusur();
    }
  }

  /// Bir pozisyonun TÜM lot'larını siler (alım + satım + temettü).
  ///
  /// Parça parça eklenmiş bir varlıkta UI'daki satır tek bir kayıt değil,
  /// aynı `positionKey`'e düşen birkaç lot'tur. Kaydırıp "Sil" dendiğinde
  /// eskiden yalnızca `representative` (= en son eklenen alım) siliniyordu;
  /// geri kalan lot'lar kaldığı için satır azalmış miktarla yeniden
  /// beliriyordu. Silme, kullanıcının gördüğü satırın tamamını kaldırmalı.
  ///
  /// Silme işlemi başına TEK deleteLog kaydı yazılır — lot başına değil.
  ///
  /// Eskiden her lot için ayrı bir mezar taşı yazılıyordu; hareket listesi
  /// ham ledger'a bağlanınca üç lot'lu bir varlığı silmek listeye üç ayrı
  /// "Silindi" satırı bırakıyordu. Artık tek satır yazılır ve kaç kaydın
  /// gittiği [Asset.deletedCount] içinde taşınır → "Silindi · 3 kayıt".
  ///
  /// Kaydın miktarı ve tutarı silinen POZİSYONUN neti üzerinden yazılır
  /// (alımlar − satışlar), böylece hareket satırı "ne kadarlık varlık
  /// gitti" sorusunu yanıtlar. Grafik ve toplamlar deleteLog'u zaten yok
  /// sayar; bu alanlar yalnızca gösterim içindir.
  Future<SilinenPozisyon?> deletePositionLots(List<Asset> lots) async {
    final ids = lots.map((l) => l.id).toSet();
    if (ids.isEmpty) return null;

    final current = state.valueOrNull;

    // Mezar taşları yeniden silinmez ve sayıma girmez.
    final removed = lots.where((l) => !l.isDeleteLog).toList();
    Asset? log;
    if (removed.isNotEmpty) {
      // Temsilci: en yeni ALIM (yoksa ilk kayıt) — isim/ticker/tür meta'sı
      // buradan gelir.
      final buys = removed.where((l) => l.isBuy).toList()
        ..sort((a, b) => b.addedDate.compareTo(a.addedDate));
      final rep = buys.isNotEmpty ? buys.first : removed.first;

      // Net miktar ve net maliyet — satışlar düşülür, temettü miktara
      // girmez (nakit hareketidir).
      double netQty = 0;
      double netCost = 0;
      for (final l in removed) {
        if (l.isDividend) continue;
        if (l.isSell) {
          netQty -= l.quantity;
          netCost -= l.quantity * (l.sellPrice ?? l.purchasePrice);
          continue;
        }
        netQty += l.quantity;
        netCost += l.quantity * l.purchasePrice;
      }
      final unitPrice = netQty > 0 ? netCost / netQty : rep.purchasePrice;

      log = Asset(
        id: _uuid.v4(),
        userId: rep.userId,
        name: rep.name,
        ticker: rep.ticker,
        type: rep.type,
        quantity: netQty > 0 ? netQty : 0,
        purchasePrice: unitPrice,
        currency: rep.currency,
        notes: rep.notes,
        isManualPrice: rep.isManualPrice,
        subCategory: rep.subCategory,
        unitType: rep.unitType,
        purchaseFxRate: rep.purchaseFxRate,
        currentPrice: rep.currentPrice,
        lastUpdated: rep.lastUpdated,
        kind: AssetKind.deleteLog,
        // Tek satır artık birden çok lot'u temsil ediyor; tek bir lot'a
        // referans vermek yanıltıcı olurdu.
        refAssetId: removed.length == 1 ? removed.first.id : null,
        deletedCount: removed.length,
      );

      await SupabaseService.instance.insertAsset(log);
      unawaited(AnalyticsService.instance.logAssetDeleted(type: rep.type.name));
    }

    // YUMUŞAK silme: lot'lar yerinde kalır, damgalanır. Fiziksel DELETE
    // kullanılsaydı bu varlığın Alım/Satım/Temettü satırları hareket
    // geçmişinden de silinirdi ve geriye yalnızca "Silindi" mezar taşı
    // kalırdı — kullanıcı ne aldığını/sattığını okuyamazdı.
    final stampedAt = DateTime.now();
    await SupabaseService.instance
        .softDeleteAssets(ids.toList(), stampedAt);

    if (current != null) {
      state = AsyncData(current.copyWith(
        assets: [
          if (log != null) log,
          for (final a in current.assets)
            if (ids.contains(a.id)) a.copyWithDeletedAt(stampedAt) else a,
        ],
      ));
      _gunIciSeriyiDusur();
    }
    return SilinenPozisyon(lotIds: ids.toList(), logId: log?.id);
  }

  /// [deletePositionLots]'u geri alır: damga temizlenir, mezar taşı silinir.
  ///
  /// HIG: yıkıcı eylem geri alma sunmalı. Silme yumuşak olduğu için lot'lar
  /// sunucuda duruyor; geri alma yalnızca damgayı kaldırır. Mezar taşı
  /// fiziksel silinir — o kayıt "silindi" olayının kendisidir, olay
  /// olmamışsa hareket listesinde durmamalı.
  Future<void> restorePositionLots(SilinenPozisyon kayit) async {
    await SupabaseService.instance.restoreAssets(kayit.lotIds);
    if (kayit.logId case final logId?) {
      await SupabaseService.instance.deleteAsset(logId);
    }
    final current = state.valueOrNull;
    if (current == null) return;
    final ids = kayit.lotIds.toSet();
    state = AsyncData(current.copyWith(
      assets: [
        for (final a in current.assets)
          if (a.id == kayit.logId)
            // mezar taşı düşer
            ...<Asset>[]
          else if (ids.contains(a.id))
            a.copyWithDeletedAt(null)
          else
            a,
      ],
    ));
    _gunIciSeriyiDusur();
  }

  Future<void> updateManualPrice(Asset asset, double price) async {
    asset.currentPrice = price;
    asset.lastUpdated = DateTime.now();
    await SupabaseService.instance.updateAsset(asset);
    final s = state.valueOrNull;
    if (s == null) return;
    state = AsyncData(s.copyWith(
      assets: s.assets.map((a) => a.id == asset.id ? asset : a).toList(),
    ));
  }

  // ---- Price refresh -------------------------------------------------------

  /// Süren fiyat turu — aynı anda gelen ikinci istek buna KATILIR.
  ///
  /// ## Neden (2026-09-24)
  /// `seriler.dart`'taki yorum "PortfolioNotifier in-flight tekilleştirme
  /// yapıyor" diyordu; yapmıyordu. Aynı nabızda iki yüzey çağırınca iki
  /// ağ turu atılıyor ve GEÇ dönen tur, erken dönenin yazdığı daha taze
  /// fiyatın üstüne kendi (daha eski) kotasyonunu yazabiliyordu —
  /// `IntradaySeriesCache._surenFetch`'in kapattığı yarışın aynısı.
  Future<void>? _surenTur;

  /// Süren tur kotasyon önbelleğini atlıyor mu? Zorlamalı istek (pull-to-
  /// refresh) önbellekten beslenen bir tura katılırsa bayat fiyat görür.
  bool _surenTurZorla = false;

  /// Nabız turlarında sunucuya en son ne zaman yazıldı (bkz. [_fiyatTuru]).
  DateTime? _sonSunucuYazimi;

  /// [force] true iken fiyat önbelleği atlanır. Kullanıcı pull-to-refresh
  /// yaptığında bayat fiyat görmemeli; ekran açılışlarında ise kotasyon
  /// önbelleği gereksiz ağ trafiğini keser.
  ///
  /// [nabiz] true ise tur ortak nabızdan (`TazelikRitmi.nabiz`) gelir:
  /// önbellek atlanır (bkz. `TazelikNabzi.fiyatTuruBagla`), sunucu yazımı
  /// seyreltilir ve sparkline önbelleği korunur.
  Future<void> refreshPrices({bool force = false, bool nabiz = false}) async {
    final zorla = force || nabiz;
    final suren = _surenTur;
    if (suren != null) {
      if (!zorla || _surenTurZorla) return suren;
      // Önbellekten beslenen tura katılmak zorlamalı isteği boşa
      // çıkarırdı: bitmesini bekle, sonra kendi turunu at.
      try {
        await suren;
      } catch (_) {
        // Süren turun hatası onu çağıranındır; bu istek kendi turunu atar.
      }
      return refreshPrices(force: force, nabiz: nabiz);
    }
    final tur = _fiyatTuru(force: zorla, nabiz: nabiz);
    _surenTur = tur;
    _surenTurZorla = zorla;
    try {
      await tur;
    } finally {
      if (identical(_surenTur, tur)) _surenTur = null;
    }
  }

  /// Süren fiyat turu varsa bitmesini bekler; yoksa anında döner.
  ///
  /// Gün içi seriyi çeken yüzeyler (Bugün kartı, Performans GÜNLÜK, varlık
  /// ekranı GÜNLÜK) seriyi kurmadan ÖNCE bunu bekler: soğuk açılışta
  /// açılış turu ağdayken kurulan seri altın/döviz gün başı referansını
  /// bulamıyor ve iki yüzey farklı gün başı gösteriyordu. Gerekçe ve ölçüm
  /// `TazelikRitmi.turuBekle`'de. Hiç fırlatmaz.
  Future<void> fiyatTurunuBekle({Duration enFazla = TazelikRitmi.yuzey}) =>
      TazelikRitmi.turuBekle(_surenTur, enFazla: enFazla);

  /// [fiyatTurunuBekle] + bir kare: defteri `widget.state`'ten okuyan
  /// yüzeyler (Bugün kartı, Performans) turun yayınını ancak sonraki karede
  /// görür — gerekçe `TazelikRitmi.turuVeKareyiBekle`.
  Future<void> fiyatTurunuVeKareyiBekle(
          {Duration enFazla = TazelikRitmi.yuzey}) =>
      TazelikRitmi.turuVeKareyiBekle(_surenTur, enFazla: enFazla);

  /// Şu an bir fiyat turu ağda mı? Bekleme bütçesi dolduğunda çağıran
  /// "eski defterle kur" ile "tur bitince kur" arasında buna göre seçer.
  bool get fiyatTuruSuruyor => _surenTur != null;

  Future<void> _fiyatTuru({required bool force, required bool nabiz}) async {
    // Build henüz bitmediyse (ya da user null → boş state) — bekle. Aksi
    // halde eski/boş `s.assets`'i alıp await'ten sonra güncel state'in
    // üzerine sıfır yazma race'i oluşur (bkz. varlıkların bir görünüp
    // kaybolma bug'ı).
    final built = await future;
    // future'dan sonra en güncel state artık valid.
    final s = state.valueOrNull ?? built;
    // Sadece kendi varlıkları boşsa refresh yapılacak bir şey yok.
    if (s.assets.isEmpty) return;
    state = AsyncData(s.copyWith(isLoading: true, clearError: true));

    // Sparkline serileri gün-içinde değişmediği için süresiz cache'lenir;
    // kullanıcı bilerek yenilediğinde (pull-to-refresh) tazelenmeli — aksi
    // halde gün dönse bile dünkü eğri kalırdı. Nabız turu kullanıcının
    // isteği değildir: 30 sn'de bir düşürmek her kartı yeniden çektirirdi.
    if (!nabiz) SparklineService.instance.clear();

    final symbols = <String>{'USDTRY=X', 'EURTRY=X', 'GBPTRY=X'};
    // Gram altın kuru yalnızca baz birim altınsa istenir: altın tutmayan
    // kullanıcı için her yenilemede fazladan XAU isteği gereksiz.
    if (BaseCurrency.fromIndex(ref.read(baseCurrencyIndexProvider)) ==
        BaseCurrency.gold) {
      symbols.add(kGoldGramSymbol);
    }
    for (final a in s.assets) {
      // Silinmiş varlık için fiyat çekmek gereksiz ağ trafiğidir.
      if (!a.isActive) continue;
      if (a.ticker.isNotEmpty && !a.isManualPrice) {
        symbols.add(a.ticker.toUpperCase());
      }
    }

    // Aktif ortakların varlıklarını yükle
    final activePartners = ref.read(activePartnersProvider);
    final partnerAssetsMap = <String, List<Asset>>{};

    // `try` BURADAN başlar (eskiden ortak yüklemesinin ALTINDAN başlıyordu).
    // Ortak listesini çekerken bağlantı kopması `refreshPrices`'tan dışarı
    // fırlıyordu: çağıranlardan biri (`MainNavigation` sekme yenilemesi) bunu
    // await etmediği için hata zone handler'ına düşüyor ve ÇÖKME olarak
    // kaydediliyordu. Ortak listesi yenilemenin ZORUNLU parçası değil;
    // başarısızlığı "fiyatlar güncellenemedi" mesajına dönüşmeli.
    try {
      for (final partner in activePartners) {
        final assets = await SupabaseService.instance.fetchByUser(partner.id);
        partnerAssetsMap[partner.id] = assets;
        for (final a in assets) {
          if (a.ticker.isNotEmpty && !a.isManualPrice) {
            symbols.add(a.ticker.toUpperCase());
          }
        }
      }

      final quotes = await PriceService.instance
          .fetchQuotes(symbols.toList(), forceRefresh: force);

      // await sonrası state başka bir yerden değişmiş olabilir (addAsset,
      // deleteAsset gibi). Kendi asset listesini yazmadan önce **en güncel**
      // state'i tekrar oku — aksi halde bu arada eklenen/silinen lot'lar
      // eski snapshot ile ezilir.
      final current = state.valueOrNull ?? s;
      final baseAssets = current.assets;

      final usd = quotes['USDTRY=X']?.regularMarketPrice ?? current.usdTry;
      final eur = quotes['EURTRY=X']?.regularMarketPrice ?? current.eurTry;
      final gbp = quotes['GBPTRY=X']?.regularMarketPrice ?? current.gbpTry;
      final gold =
          quotes[kGoldGramSymbol]?.regularMarketPrice ?? current.goldGramTry;

      final nextState = current.copyWith(
          usdTry: usd, eurTry: eur, gbpTry: gbp, goldGramTry: gold);

      // Kendi varlıklarını güncelle
      final fiyatiDegisenler = <Asset>[];
      final updated = baseAssets.map((asset) {
        // **Silinmiş lot'a YAZMA — dirilirdi (kullanıcı bildirimi,
        // 2026-09-16).** `updateAsset` gövdenin tamamını yazıyor ve
        // `toSupabase()` `deleted_at` alanını da içeriyor; elindeki nesne
        // damgasızsa UPDATE o damgayı NULL'a çekiyor ve kullanıcının
        // sildiği varlık uygulamayı kapatıp açınca geri geliyordu.
        //
        // Yukarıdaki `symbols` döngüsü zaten `!a.isActive` diye eliyor
        // (fiyat çekmemek için); yazma tarafında aynı kapı yoktu.
        if (!asset.isActive) return asset;
        if (!asset.isManualPrice && asset.ticker.isNotEmpty) {
          final price = quotes[asset.ticker.toUpperCase()]?.regularMarketPrice;
          if (price != null) {
            asset.currentPrice = price;
            asset.lastUpdated = DateTime.now();
            // Alım fiyatı girilmemişse güncel fiyatı maliyet olarak kilitle
            if (asset.purchasePrice == 0) {
              asset.purchasePrice = price;
            }
            fiyatiDegisenler.add(asset);
          }
        }
        return asset;
      }).toList();

      // Sunucuya yazma ekranı BEKLETMEZ ama BAŞIBOŞ da bırakılmaz —
      // bkz. [_fiyatlariYaz].
      //
      // Nabız turunda SEYRELTİLİR (2026-09-24). Fiyat turu artık her ön
      // yüz nabzında atılıyor (eskiden yalnızca Performans GÜNLÜK açıkken);
      // her 30 sn'de varlık başına UPDATE ve yeni bir anlık görüntü satırı
      // sunucuya boşuna yük olurdu. Sunucudaki fiyatı okuyan yüzeyler (ana
      // ekran widget'ı, ortak, Live Activity) zaten 5 dk'lık push
      // döngüsüyle çalışıyor (`TazelikRitmi.gunIciSeriOmru`); yazım o
      // ritme iner. Ekrandaki değer bellekte her turda günceldir.
      final sunucuyaYaz = !nabiz ||
          _sonSunucuYazimi == null ||
          DateTime.now().difference(_sonSunucuYazimi!) >=
              TazelikRitmi.gunIciSeriOmru;
      if (sunucuyaYaz) {
        _sonSunucuYazimi = DateTime.now();
        _fiyatlariYaz(fiyatiDegisenler);
      }

      // Ortak varlıkları sadece okunur (RLS) — fiyatları bellekte güncelliyoruz
      for (final assets in partnerAssetsMap.values) {
        for (final asset in assets) {
          if (!asset.isManualPrice && asset.ticker.isNotEmpty) {
            final price =
                quotes[asset.ticker.toUpperCase()]?.regularMarketPrice;
            if (price != null) {
              asset.currentPrice = price;
              asset.lastUpdated = DateTime.now();
              // Not: updateAsset çağrılmıyor — RLS partner yazmasını engeller
            }
          }
        }
      }

      // Fiyatlanmış ortak listesini DOĞRUDAN yaz.
      //
      // Burada eskiden `allPartnerAssetsProvider.notifier.reload()` çağrılıyordu
      // ve o metot varlıkları DB'den YENİDEN çekiyordu — yukarıdaki fiyat
      // güncellemesini olduğu gibi çöpe atarak. Ortak lot'ları DB'de
      // `current_price` alanını taşır ama o alan yalnızca SAHİBİ uygulamayı
      // açtığında güncellenir (RLS başkasının yazmasını engeller). Sonuç:
      // ortağın varlıkları BAYAT fiyatla kalıyordu.
      //
      // Altında görünür olmasının sebebi: altın `currentPrice`'ı gram22k×kat
      // ile türetilir ve hızlı oynar. Grafik serisi ise fiyatı geçmiş
      // serisinden hesapladığı için GÜNCELDİ; yalnızca serinin son noktası
      // (canlı toplam) bayat kalıyordu. Simülasyonda tüm dönem bugünkü net
      // pozisyonla çizildiğinden bu sapma yüzdeye birebir yansıyor ve
      // "aynı altın, farklı kâr/zarar" olarak görünüyordu.
      ref.read(allPartnerAssetsProvider.notifier).setAssets(partnerAssetsMap);

      final finalState = nextState.copyWith(
        assets: updated,
        isLoading: false,
        lastUpdated: DateTime.now(),
      );

      state = AsyncData(finalState);

      // NOT: Burada `allPartnerAssetsProvider.reload()` ÇAĞRILMAZ. O metot
      // DB'den yeniden çeker ve yukarıda uygulanan canlı fiyatları geri alır.
      // Fiyatlanmış liste zaten `setAssets` ile yazıldı.

      // Snapshot kaydet — nabız turunda fiyat yazımıyla aynı seyreltme.
      if (sunucuyaYaz) {
        final userId = ref.read(authProvider).valueOrNull?.id ?? '';
        await _saveSnapshot(finalState, userId: userId);
      }

      // NOT: Teknik sinyal analizi burada tetiklenmez. `refreshPrices` her
      // ekran açılışında/pull-to-refresh'te çağrıldığı için burada
      // `analyzePortfolio` çalıştırmak spam push'a yol açıyor. Sinyal analizi
      // artık sadece iki yerden tetiklenir:
      //   1. Günde 2 kez cron (TR 11:00 & 15:00) → analyze-signals edge
      //      function → FCM data-message → `_AuthGate._triggerSignalAnalysis`
      //   2. Uygulama açılışında `signalProvider.build()` DB'den okur
      //      (yeni analiz yapmaz, sadece geçmişi yükler).
    } catch (e, st) {
      // Ham `$e` kullanıcıya gösterilmez (CLAUDE.md "Hata gösterimi"):
      // "Fiyatlar güncellenemedi: TimeoutException after 0:00:15.000000"
      // kullanıcıya hiçbir şey anlatmıyordu. Hata yine de görünür kalmalı,
      // o yüzden non-fatal olarak Crashlytics'e gider.
      CrashReporter.report(e, st, reason: 'PortfolioNotifier.refreshPrices');
      final current = state.valueOrNull ?? s;
      state = AsyncData(current.copyWith(
        isLoading: false,
        errorMessage: 'Fiyatlar güncellenemedi. ${friendlyError(e)}',
      ));
    }
  }

  /// Yenilenen fiyatları sunucuya yazar — ÜRETİM ÇÖKMESİNİN kaynağı burasıydı.
  ///
  /// Crashlytics (2026-09-19): "Fatal Exception: FlutterError → `Future.timeout`
  /// → `DbLogger.log` → `SupabaseService.updateAsset`". Bu yazma eskiden
  /// [refreshPrices] içinde `await`siz, `unawaited`sız tek satırdı
  /// (`SupabaseService.instance.updateAsset(asset)`). Zayıf bağlantıda
  /// `DbLogger.defaultTimeout` (15 sn) dolunca doğan `TimeoutException`
  /// hiçbir yerde yakalanmıyor, `runZonedGuarded` handler'ına düşüyor ve
  /// orada `fatal: true` ile kaydediliyordu. Kullanıcı açısından hiçbir şey
  /// olmuyordu — fiyat zaten bellekte güncellenmişti, ekran doğruydu — ama
  /// Crashlytics'te ÇÖKME görünüyordu.
  ///
  /// Kural: fiyat yazımı EN İYİ ÇABA'dır. Ekrandaki değer bellekte zaten
  /// güncel; sunucuya yazmak widget / ortak / başka cihaz içindir. Bu yüzden:
  /// - hata varlık BAŞINA yakalanır, tur ilk hatada kırılmaz;
  /// - turun tamamı için TEK non-fatal rapor gider (varlık başına rapor,
  ///   bağlantı koptuğunda Crashlytics'i boğardı).
  ///
  /// Eşzamanlılık bilerek korundu: yazmalar eskiden de paralel gidiyordu,
  /// sıraya dizmek 50 lotluk portföyde yenilemeyi dakikaya çıkarırdı.
  void _fiyatlariYaz(List<Asset> assets) {
    if (assets.isEmpty) return;
    Object? ilkHata;
    StackTrace? ilkStack;
    var basarisiz = 0;
    CrashReporter.arkaPlan(
      Future.wait(assets.map((asset) async {
        try {
          await SupabaseService.instance.updateAsset(asset);
        } catch (e, st) {
          basarisiz++;
          ilkHata ??= e;
          ilkStack ??= st;
        }
      })).then<void>((_) {
        final hata = ilkHata;
        if (hata == null) return;
        CrashReporter.report(hata, ilkStack,
            reason: 'refreshPrices fiyat yazımı '
                '($basarisiz/${assets.length} varlık)');
      }),
      reason: 'refreshPrices fiyat yazımı (beklenmeyen)',
    );
  }

  // ---- Snapshot / history --------------------------------------------------

  Future<void> _saveSnapshot(PortfolioState s, {String userId = ''}) async {
    if (s.assets.isEmpty) return;
    final categoryValues = snapshotKategoriDegerleri(s);
    await SupabaseService.instance
        .insertSnapshot(categoryValues, userId: userId);
  }

  Future<List<({int ts, Map<String, double> values})>> fetchSnapshots(
          int sinceMs) =>
      SupabaseService.instance.fetchSnapshots(
        sinceMs,
        userId: ref.read(authProvider).valueOrNull?.id,
      );
}

/// Günlük anlık görüntünün tür → TRY değeri haritası — saf, test edilir.
///
/// Ham lot defteri değil NET pozisyonlar: satış satırları, silinmiş
/// lot'lar ve kapanmış pozisyonlar da `totalValue` taşıdığı için eski
/// toplam bunları ekliyordu; yıllık özet ve "piyasadan %X" push'u bu
/// anlık görüntülerden hesaplanıyor (2026-09-23 denetimi F12). Kural
/// `PortfolioState.totalValue` ile aynı kaynaktan gelir.
Map<String, double> snapshotKategoriDegerleri(PortfolioState s) {
  final categoryValues = <String, double>{};
  for (final position in aggregatePositionsByOwner(lotlarSahibeGore(s.assets))) {
    final a = position.asDisplayAsset();
    final val = s.toTRY(a.totalValue, a.currency);
    if (val > 0) {
      categoryValues[a.type.name] = (categoryValues[a.type.name] ?? 0) + val;
    }
  }
  return categoryValues;
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final portfolioProvider =
    AsyncNotifierProvider<PortfolioNotifier, PortfolioState>(
  PortfolioNotifier.new,
);

final allPartnerAssetsProvider =
    AsyncNotifierProvider<PartnerAssetsNotifier, Map<String, List<Asset>>>(
  PartnerAssetsNotifier.new,
);

/// Ortakların varlıkları. Public: widget testleri `overrideWith` ile sahte
/// veri besleyebilsin (private sınıf test tarafından extend edilemiyor).
class PartnerAssetsNotifier extends AsyncNotifier<Map<String, List<Asset>>> {
  /// Bellekte fiyatlanmış lot'lar — `build()` yeniden koştuğunda DB'den
  /// gelen BAYAT `current_price` bunların üzerine yazılmasın diye.
  ///
  /// ## Neden gerekli (kullanıcı bildirimi, 2026-09-22)
  /// Ortak lot'larının fiyatı RLS yüzünden sunucuya yazılamaz; `refreshPrices`
  /// onları yalnızca bellekte günceller ve [setAssets] ile buraya koyar.
  /// Ama [build] `activePartnersProvider`'ı İZLİYOR: o provider
  /// `partnersProvider` her tazelendiğinde yeni bir liste nesnesi üretiyor,
  /// dolayısıyla `build()` yeniden koşuyor ve `fetchByUser` fiyatlı listeyi
  /// DB'deki bayat (çoğu zaman 0) değerle eziyordu.
  ///
  /// Ekrandaki sonucu: Performans › Özet'te **Birlikte "Bugün" = Ben
  /// "Bugün"** — ortağın tutarı canlı toplamdan tamamen düşüyordu. Dönem
  /// BAŞI doğru kalıyordu (seri geçmiş fiyatlardan hesaplanır), yalnızca uç
  /// yanlıştı ve aradaki fark sahte kâr/zarar olarak yazılıyordu.
  ///
  /// `fetchByUser` yine çağrılır — lot'ların KENDİSİ (yeni alım, satış,
  /// silme) sunucudan gelmeli. Yalnızca `currentPrice` korunur, ve yalnızca
  /// bellekteki değer gerçekten ölçülmüşse (`> 0`).
  final Map<String, double> _fiyatHafizasi = {};

  @override
  Future<Map<String, List<Asset>>> build() async {
    final activePartners = ref.watch(activePartnersProvider);
    final map = <String, List<Asset>>{};
    for (final p in activePartners) {
      final lots = await SupabaseService.instance.fetchByUser(p.id);
      for (final a in lots) {
        if (a.currentPrice > 0) continue;
        // 1) Bu oturumda bu LOT için ölçülmüş fiyat.
        final hatirlanan = _fiyatHafizasi[a.id];
        if (hatirlanan != null && hatirlanan > 0) {
          a.currentPrice = hatirlanan;
          continue;
        }
        // 2) Yoksa SEMBOL için görülmüş son kotasyon. Kendi portföyümde
        //    aynı sembol varsa fiyatı zaten ölçülmüştür; ortağın lot'u da
        //    aynı piyasadan fiyatlanır. `_fiyatHafizasi` boşken (uygulama
        //    yeni açıldı, `refreshPrices` henüz koşmadı) tek çare budur.
        //
        //    UYDURMA DEĞİL: `sonBilinenFiyat` yalnızca gerçekten ölçülmüş
        //    kotasyonları taşır ve hiç görülmemişse `null` döner — lot o
        //    zaman fiyatsız kalır ve toplamlara girmez.
        final t = a.ticker.trim();
        if (t.isEmpty || a.isManualPrice) continue;
        final son = PriceService.instance.sonBilinenFiyat(t);
        if (son != null && son > 0) a.currentPrice = son;
      }
      map[p.id] = lots;
    }
    return map;
  }

  /// Fiyatlanmış ortak listesini doğrudan yaz — DB'den YENİDEN ÇEKMEDEN.
  ///
  /// `refreshPrices` ortak lot'larının `currentPrice`'ını bellekte canlı
  /// kotasyonla günceller (RLS yüzünden DB'ye yazamaz). Ardından [reload]
  /// çağrılırsa o emek boşa gider: `fetchByUser` DB'deki BAYAT `current_price`
  /// değerini geri getirir ve ortağın varlıkları eski fiyatla görünür.
  /// Bu metot, hesaplanmış listeyi olduğu gibi state'e koyar.
  void setAssets(Map<String, List<Asset>> assets) {
    // Fiyatları hatırla — `build()` yeniden koşarsa bayat DB değeri
    // bunların üzerine yazmasın (gerekçe: [_fiyatHafizasi]).
    for (final lots in assets.values) {
      for (final a in lots) {
        if (a.currentPrice > 0) _fiyatHafizasi[a.id] = a.currentPrice;
      }
    }
    state = AsyncData(assets);
  }

  // Manuel yenileme — refreshPrices() tarafından çağrılır
  Future<void> reload() async {
    final activePartners = ref.read(activePartnersProvider);
    if (activePartners.isEmpty) {
      state = const AsyncData({});
      return;
    }
    // Mevcut veriyi koru, loading state'e GEÇMEDEn arka planda yenile
    final map = <String, List<Asset>>{};
    for (final p in activePartners) {
      map[p.id] = await SupabaseService.instance.fetchByUser(p.id);
    }
    state = AsyncData(map);
  }
}

/// [PortfolioNotifier.deletePositionLots]'un makbuzu — geri alma için
/// gereken her şey: damgalanan lot kimlikleri ve eklenen mezar taşı.
class SilinenPozisyon {
  const SilinenPozisyon({required this.lotIds, required this.logId});

  final List<String> lotIds;

  /// Mezar taşı yoksa (yalnızca eski mezar taşları silinmişse) null.
  final String? logId;
}
