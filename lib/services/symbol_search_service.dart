import 'package:flutter/foundation.dart';

import '../models/asset_categories.dart';
import 'tefas_service.dart';

/// Portföy serilerinin sanal ticker önekleri.
///
/// Bunlar gerçek sembol DEĞİLDİR — fiyat servislerine gönderilmez.
/// Karşılaştırma ekranı bu önekleri görünce seriyi `getSymbolHistory`
/// yerine `getPortfolioHistory` ile hesaplar.
///
/// Sanal olmalarının sebebi: kullanıcının kendi portföyünün "fiyatı"
/// piyasada kote değildir; lot'larından hesaplanır. Ama karşılaştırma
/// grafiği için aynı arayüzden akmaları gerekir.
abstract final class PortfolioSeries {
  /// Yalnızca kullanıcının kendi varlıkları.
  static const mine = 'PORTFOLIO:MINE';

  /// Kullanıcı + tüm ortaklar.
  static const together = 'PORTFOLIO:TOGETHER';

  /// Belirli bir ortağın portföyü — `PORTFOLIO:PARTNER:<uuid>`.
  static const partnerPrefix = 'PORTFOLIO:PARTNER:';

  static bool isPortfolio(String ticker) => ticker.startsWith('PORTFOLIO:');

  /// `PORTFOLIO:PARTNER:<uuid>` → `<uuid>`; değilse null.
  static String? partnerIdOf(String ticker) => ticker.startsWith(partnerPrefix)
      ? ticker.substring(partnerPrefix.length)
      : null;
}

/// Arama sonucundaki tek bir sembol.
@immutable
class SymbolHit {
  /// Fiyat servislerine verilecek sembol — ör. `THYAO.IS`, `ALTIN_CEYREK`.
  final String ticker;

  /// Kullanıcıya gösterilen ad — ör. `Türk Hava Yolları`.
  final String name;

  /// Kısa köken etiketi — ör. `BIST`, `Fon`, `Altın`, `Emtia`.
  final String source;

  const SymbolHit({
    required this.ticker,
    required this.name,
    required this.source,
  });

  @override
  bool operator ==(Object other) =>
      other is SymbolHit && other.ticker == ticker;

  @override
  int get hashCode => ticker.hashCode;
}

/// Karşılaştırmaya eklenecek varlığı bulur.
///
/// ## Kapsam: yalnızca Türkiye
/// Arama bilinçli olarak **TR'de işlem gören** varlıklarla sınırlıdır —
/// BIST hisseleri, TEFAS fonları, altın ürünleri, döviz ve BIST endeksleri.
/// Yabancı hisse/kripto (AAPL, BTC-USD) LİSTELENMEZ: uygulamanın geri
/// kalanı da TR odaklıdır ve o varlıkların portföye eklenmesi zaten
/// desteklenmiyor; aramada çıkmaları kullanıcıyı ekleyemeyeceği bir
/// şeye yönlendirirdi.
///
/// **İstisna — küresel emtia referansları.** Ons altın, Brent petrol gibi
/// semboller TR'de kote değildir ama yerel varlığın dayandığı fiyattır
/// (gram altın onsa, akaryakıt Brent'e bağlıdır). Amaç yabancı borsada
/// işlem yapmak değil, kıyas noktasını görmek — bu yüzden kalırlar.
///
/// ## Katmanlar
///   1. **Yerleşik listeler** (`asset_categories.dart`) — BIST, altın,
///      döviz, endeks, emtia. Ticker formatları doğru, fiyat desteği
///      kanıtlı.
///   2. **TEFAS fon listesi** — `TefasService` üzerinden, önbellekli.
///   3. **TEFAS tek-fon sorgusu** — liste API'sinde görünmeyen
///      kurucu-only fonlar (ALE, YLB gibi) için son çare.
class SymbolSearchService {
  SymbolSearchService._();
  static final instance = SymbolSearchService._();

  static final _cache = <String, List<SymbolHit>>{};

  /// Yerleşik listelerin tek seferlik düzleştirilmiş hali.
  ///
  /// `static final` alan Dart'ta zaten tembel başlatılır: ilk erişimde
  /// kurulur, sonraki aramalar hazır listeyi kullanır. ~500 sembolü her
  /// tuş vuruşunda yeniden düzleştirmek gereksiz iş olurdu.
  static final List<SymbolHit> _builtIn = _buildBuiltInIndex();

  static List<SymbolHit> _buildBuiltInIndex() {
    final out = <SymbolHit>[];

    // BIST — `bist100StocksMap` kod→isim yönünde.
    bist100StocksMap.forEach((ticker, name) {
      out.add(SymbolHit(ticker: ticker, name: name, source: 'BIST'));
    });

    // Altın — `goldTickerMap` TERS yönde (isim→kod). Karıştırmak kolay;
    // bu yüzden burada açıkça çevriliyor.
    goldTickerMap.forEach((name, ticker) {
      out.add(SymbolHit(ticker: ticker, name: name, source: 'Altın'));
    });

    // Döviz — karşılaştırmada sık istenen pariteler.
    const fx = {
      'USDTRY=X': 'Amerikan Doları',
      'EURTRY=X': 'Euro',
      'GBPTRY=X': 'İngiliz Sterlini',
    };
    fx.forEach((ticker, name) {
      out.add(SymbolHit(ticker: ticker, name: name, source: 'Döviz'));
    });

    // Endeksler — "BIST'i yendim mi?" karşılaştırmasının referansı.
    // Yerleşik listede yoklar ama karşılaştırmanın en doğal kıyas
    // noktaları olduğu için elle ekleniyor.
    const indices = {
      'XU100.IS': 'BIST 100 Endeksi',
      'XU030.IS': 'BIST 30 Endeksi',
    };
    indices.forEach((ticker, name) {
      out.add(SymbolHit(ticker: ticker, name: name, source: 'Endeks'));
    });

    // Küresel emtia referansları.
    //
    // Bunlar Türkiye'de kote DEĞİLDİR ama TR yatırımcısının fiilen takip
    // ettiği kıyas noktalarıdır (ons altın gram altının, Brent akaryakıtın
    // referansı). Yabancı HİSSE/kriptodan farkı bu: burada amaç yabancı
    // borsada işlem yapmak değil, yerel varlığın dayandığı fiyatı görmek.
    // `getSymbolHistory` bunları USD kabul edip o günün kuruyla TRY'ye
    // çevirir.
    const commodities = {
      'GC=F': 'Altın (Ons)',
      'SI=F': 'Gümüş (Ons)',
      'BZ=F': 'Petrol (Brent)',
      'CL=F': 'Petrol (WTI)',
      'NG=F': 'Doğalgaz',
    };
    commodities.forEach((ticker, name) {
      out.add(SymbolHit(ticker: ticker, name: name, source: 'Emtia'));
    });

    return out;
  }

  /// [query] için sembol arar. Boş sorguda popüler kıyas noktalarını döner.
  Future<List<SymbolHit>> search(String query) async {
    final q = query.trim().toUpperCase();
    if (q.isEmpty) return defaults;

    final cached = _cache[q];
    if (cached != null) return cached;

    // Yerleşik listeler + TEFAS fonları PARALEL aranır.
    //
    // Fonlar ayrı bir katman çünkü kaynakları farklı: `bankFunds` sabiti
    // yalnızca görünen ADLARI tutar, TEFAS kodu yoktur — fiyat/geçmiş
    // çekmek için `TEFAS:AFA` gibi bir koda ihtiyaç var ve o yalnızca
    // `TefasService`'in canlı listesinde bulunur. Sabit listeyi kullanmak
    // aramada fon gösterip grafikte "veri yok" demeye yol açardı.
    final results = await Future.wait([
      Future.value(_searchBuiltIn(q)),
      _searchFunds(q),
    ]);
    final local = <SymbolHit>[...results[0], ...results[1]];

    // Sonuç yoksa ve sorgu bir fon koduna benziyorsa TEK-FON sorgusu.
    //
    // TEFAS'ın liste API'si bazı fonları döndürmez — kurucu-only para
    // piyasası fonları (ALE, YLB gibi) listede yoktur ama Türkiye'de
    // fiilen işlem görür ve tek tek sorulduğunda gelir. `add_asset`
    // ekranı da aynı yolu kullanıyor; karşılaştırmada eksik olması
    // kullanıcının kendi portföyündeki fonu arayamamasına yol açardı.
    if (local.isEmpty && q.length >= 2 && q.length <= 6) {
      final fund = await _lookupFund(q);
      if (fund != null) {
        final hit = [fund];
        _cache[q] = hit;
        return hit;
      }
    }

    _cache[q] = local;
    return local;
  }

  /// TEFAS liste API'sinde görünmeyen bir fon kodunu tek tek sorar.
  Future<SymbolHit?> _lookupFund(String code) async {
    try {
      final f = await TefasService.instance.lookupFund(code);
      if (f == null) return null;
      return SymbolHit(
        ticker: 'TEFAS:${f.code}',
        name: f.name,
        source: 'Fon',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('TEFAS tek-fon sorgusu başarısız: $e');
      return null;
    }
  }

  /// TEFAS fonlarında kod veya ada göre arar.
  ///
  /// `TefasService.fetchAllFunds` önbellekli: RAM'de taze liste varsa ya da
  /// disk önbelleği 24 saatten yeniyse ağa HİÇ çıkmaz. İlk çağrıda liste
  /// yoksa ağ turu olur; hata durumunda boş liste döner ve arama yalnızca
  /// fonsuz devam eder — kullanıcı hisse/altın aramaya devam edebilmeli.
  Future<List<SymbolHit>> _searchFunds(String q) async {
    try {
      final funds = await TefasService.instance.fetchAllFunds();
      final hits = <SymbolHit>[];
      for (final f in funds) {
        final code = f.code.toUpperCase();
        if (!code.contains(q) && !f.name.toUpperCase().contains(q)) continue;
        hits.add(SymbolHit(
          // Fiyat/geçmiş servisleri bu öneki bekler (bkz. PriceService).
          ticker: 'TEFAS:${f.code}',
          name: f.name,
          source: 'Fon',
        ));
      }

      // Kodu sorguyla başlayanlar öne — "AFA" araması AFA fonunu, adında
      // "afa" geçen bir fondan önce göstermeli.
      hits.sort((a, b) {
        final ac = a.ticker.replaceFirst('TEFAS:', '');
        final bc = b.ticker.replaceFirst('TEFAS:', '');
        final aStarts = ac.startsWith(q) ? 0 : 1;
        final bStarts = bc.startsWith(q) ? 0 : 1;
        if (aStarts != bStarts) return aStarts - bStarts;
        return ac.compareTo(bc);
      });

      // Fon sayısı binlerce; hepsini listelemek arama sayfasını boğar.
      return hits.take(20).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('TEFAS fon araması başarısız: $e');
      return const [];
    }
  }

  /// Sorgu boşken gösterilen öneriler — kullanıcıya "ne arayabilirim"
  /// fikri verir.
  List<SymbolHit> get defaults => const [
        SymbolHit(
            ticker: 'XU100.IS', name: 'BIST 100 Endeksi', source: 'Endeks'),
        SymbolHit(
            ticker: 'ALTIN_GRAM', name: '22 Ayar Gram Altın', source: 'Altın'),
        SymbolHit(ticker: 'USDTRY=X', name: 'Amerikan Doları', source: 'Döviz'),
        SymbolHit(
            ticker: 'THYAO.IS', name: 'Türk Hava Yolları', source: 'BIST'),
        SymbolHit(ticker: 'GARAN.IS', name: 'Garanti BBVA', source: 'BIST'),
      ];

  /// Yerleşik listelerde ada VEYA ticker'a göre arar.
  static List<SymbolHit> _searchBuiltIn(String q) {
    final hits = _builtIn.where((h) {
      return h.ticker.contains(q) || h.name.toUpperCase().contains(q);
    }).toList();

    // Ticker'ı sorguyla BAŞLAYANLAR öne alınır: "AK" araması
    // `AKBNK`'ı, adında "ak" geçen rastgele bir şirketten önce göstermeli.
    hits.sort((a, b) {
      final aStarts = a.ticker.startsWith(q) ? 0 : 1;
      final bStarts = b.ticker.startsWith(q) ? 0 : 1;
      if (aStarts != bStarts) return aStarts - bStarts;
      return a.ticker.compareTo(b.ticker);
    });
    return hits;
  }

  @visibleForTesting
  static void clearCacheForTest() => _cache.clear();
}
