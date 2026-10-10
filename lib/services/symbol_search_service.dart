import 'package:flutter/foundation.dart';

import '../demo/demo_modu.dart';
import '../models/abd_hisseleri.dart';
import '../models/asset_categories.dart';
import '../models/asset_type.dart';
import '../models/eurobond.dart';
import '../models/kripto_fiyat.dart';
import 'bist_hisse_katalogu.dart';
import 'supabase_service.dart';
import 'tefas_service.dart';
import 'fiyat_kaynagi.dart';
import 'remote_config_service.dart';
import '../utils/tr_katla.dart';

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

/// Karşılaştırma ekranında TÜFE endeksi — piyasada kote değil, `InflationService`
/// tablosundan gelir.
///
/// **Neden ayrı bir sanal sembol:** reel getiri kart olarak tam ama TÜFE
/// grafikte görünmüyordu. Portföyün TL eksenine endeks basmak iki ölçeği
/// karıştırırdı; karşılaştırma ekranı zaten her seriyi dönem başına göre
/// yüzdeye çeviriyor — TÜFE de o düzlemde dürüstçe çizilebilir. Seri AYLIK
/// basamak olarak çizilir (`PercentComparisonChart.steppedKeys`); ara
/// değer uydurulmaz.
abstract final class TufeSeries {
  static const ticker = 'TUFE:INDEX';
  static bool isTufe(String ticker) => ticker == TufeSeries.ticker;
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
/// Yabancı hisse (AAPL) LİSTELENMEZ: uygulamanın geri kalanı da TR
/// odaklıdır ve o varlıkların portföye eklenmesi desteklenmiyor; aramada
/// çıkmaları kullanıcıyı ekleyemeyeceği bir şeye yönlendirirdi.
///
/// **ABD hisseleri bayrakla listelenir (`abd_hisse`, 2026-10-08).** Bayrak
/// açıkken ABD portföye eklenebiliyor (hisse + `sub_category='abd'` + USD);
/// o zaman yukarıdaki gerekçe ("ekleyemeyeceği bir şey") düşer ve katalog
/// (`abdHisseleri`) aramaya `ABD` etiketiyle girer — BIST sonuçlarının
/// ARKASINDA: "ARM" araması önce BIST'teki eşleşmeyi göstermeli, yurt içi
/// kullanıcının varsayılan pazarı orası. Bayrak kapalıyken liste birebir
/// eski.
///
/// **Kripto 2026-09-25'ten beri listelenir** — ama `BTC-USD` Yahoo sembolü
/// olarak değil, sunucu kataloğundan `KRIPTO:BTC` olarak (portföye
/// eklenebilen ve fiyatı `kripto_fiyat`'tan gelen tek biçim).
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
///   3. **Kripto kataloğu** — `kripto_varlik` (Binance), oturum başına
///      önbellekli; hata olursa kriptosuz devam edilir.
///   4. **TEFAS tek-fon sorgusu** — liste API'sinde görünmeyen
///      kurucu-only fonlar (ALE, YLB gibi) için son çare.
///   5. **Eurobond kataloğu** (bayrak `eurobond`, seri denetimi
///      2026-10-08) — `eurobond_katalog`, oturum başına önbellekli.
///      Portföye eklenebilen eurobond takip listesine EKLENEMİYORDU: arama
///      tahvili hiç bilmiyordu, `EUROBOND:` sembolü elde edilse bile
///      `VarlikKimligi` onu BIST hissesi (TRY) sayardı. Yalnız eklenebilir
///      küme listelenir (`eklenebilirEurobondlar`: USD, vadesi gelmemiş) —
///      geçmiş değer yolu EUR kurunu bilmez (bkz. `TECHNICAL_DEBT.md`).
class SymbolSearchService {
  SymbolSearchService._();
  static final instance = SymbolSearchService._();

  /// Yazarken ağ aramasının beklemesi — her tuşta TEFAS'a gitmemek için.
  /// Takip listesi araması ve ekleme sayfasının tür seçicisi AYNI süreyi
  /// kullanır (tek kaynak; hareket süresi olmadığı için `SandikMotion` değil).
  static const aramaBeklemesi = Duration(milliseconds: 250);

  static final _cache = <String, List<SymbolHit>>{};

  /// ABD sonucunun köken etiketi; `VarlikKimligi.fromSymbolHit` buna bakıp
  /// USD kote hisse kimliği kurar.
  static const abdKaynagi = 'ABD';

  /// ABD kataloğu — yerleşik indeksten AYRI tutulur: bayrak oturum içinde
  /// açılıp kapanabilir (Remote Config yenilemesi), indeks ise bir kez
  /// kurulur.
  static final List<SymbolHit> _abd = [
    for (final e in abdHisseleri.entries)
      SymbolHit(ticker: e.key, name: e.value, source: abdKaynagi),
  ];
  static final Map<String, String> _abdAnahtar = {
    for (final h in _abd) h.ticker: trKatla('${h.ticker} ${h.name}'),
  };

  static bool get _abdAcik => RemoteConfigService.instance.abdHisse;

  /// Eurobond sonucunun köken etiketi; `VarlikKimligi.fromSymbolHit`
  /// `EUROBOND:` önekine bakar, etiket yalnız satır içindir.
  static const eurobondKaynagi = 'Eurobond';

  static bool get _eurobondAcik => RemoteConfigService.instance.eurobond;

  /// Eurobond kataloğu kaynağı — testte ağsız verilir.
  @visibleForTesting
  static Future<List<(EurobondSozlesmesi, EurobondFiyati?)>> Function()
      eurobondKatalogKaynagi =
      () => SupabaseService.instance.eurobondKatalogu();

  static List<(EurobondSozlesmesi, EurobondFiyati?)>? _eurobondKatalog;
  static DateTime? _eurobondKatalogZamani;

  /// Önbellek anahtarı: bayraklar anahtara girer ki oturum içinde açılan
  /// bayrak eski (o türsüz) sonucu döndürmesin. İkisi de kapalıyken
  /// anahtar birebir eski (katlanmış sorgu).
  static String _anahtar(String k) =>
      '${_katalogSurumu > 0 ? 'b$_katalogSurumu|' : ''}'
      '${_abdAcik ? 'abd|' : ''}${_eurobondAcik ? 'eb|' : ''}$k';

  /// BIST kataloğu sunucudan tazelenince (yeni halka arz) yerleşik dizin
  /// ve sonuç önbelleği eskir; sürüm anahtara girer, dizin yeniden kurulur.
  static int get _katalogSurumu => BistHisseKatalogu.instance.surum;

  /// Yerleşik listelerin tek seferlik düzleştirilmiş hali.
  ///
  /// İlk erişimde kurulur, sonraki aramalar hazır listeyi kullanır; ~800
  /// sembolü her tuş vuruşunda yeniden düzleştirmek gereksiz iş olurdu.
  /// BIST kataloğu değişince (sürüm) bir kez yeniden kurulur.
  static List<SymbolHit> get _builtIn {
    if (_builtInSurumu != _katalogSurumu || _builtInListe == null) {
      _builtInListe = _buildBuiltInIndex();
      _builtInAnahtarListe = {
        for (final h in _builtInListe!)
          h.ticker:
              trKatla('${h.ticker} ${h.name} ${_takmaAdlar[h.ticker] ?? ''}'),
      };
      _builtInSurumu = _katalogSurumu;
    }
    return _builtInListe!;
  }

  static List<SymbolHit>? _builtInListe;
  static Map<String, String> _builtInAnahtarListe = const {};
  static int _builtInSurumu = -1;

  /// Yerleşik sembolün aranabilir anahtarı: katlanmış ticker + ad + takma
  /// adlar. Bir kez kurulur (her tuşta ~500 adı yeniden katlamak gereksiz).
  static Map<String, String> get _builtInAnahtar {
    _builtIn; // sürüm değiştiyse dizinle birlikte kurulur
    return _builtInAnahtarListe;
  }

  /// Gündelik adlar — kullanıcının yazdığı, resmî adda geçmeyen kelimeler.
  ///
  /// "dolar" zaten "Amerikan Doları"nda geçer; burada yalnızca adda HİÇ
  /// olmayanlar var ("usd", "brent", "bist100"). Liste kısa tutulur: her
  /// takma ad bir başka sorguda gürültüdür.
  static const _takmaAdlar = <String, String>{
    FiyatKaynagi.usdTry: 'usd dolar',
    'EURTRY=X': 'eur avro',
    'GBPTRY=X': 'gbp sterlin pound',
    'XU100.IS': 'bist100 xu100 borsa',
    'XU030.IS': 'bist30 xu030',
    FiyatKaynagi.xauUsd: 'ons xau',
    'SI=F': 'ons silver',
    'BZ=F': 'brent',
    'CL=F': 'wti',
    'NG=F': 'gaz',
  };

  /// TEFAS fon adlarının katlanmış hâli — kod → ad. Fon sayısı binlerce;
  /// her tuşta hepsini yeniden katlamamak için oturum boyunca tutulur.
  static final _fonAdKatli = <String, String>{};

  static List<SymbolHit> _buildBuiltInIndex() {
    final out = <SymbolHit>[];

    // BIST — katalog kod→isim yönünde (sunucu → önbellek → gömülü liste).
    BistHisseKatalogu.instance.hisseler.forEach((ticker, name) {
      out.add(SymbolHit(ticker: ticker, name: name, source: 'BIST'));
    });

    // Altın — `goldTickerMap` TERS yönde (isim→kod). Karıştırmak kolay;
    // bu yüzden burada açıkça çevriliyor.
    goldTickerMap.forEach((name, ticker) {
      out.add(SymbolHit(ticker: ticker, name: name, source: 'Altın'));
    });

    // Döviz — karşılaştırmada sık istenen pariteler.
    const fx = {
      FiyatKaynagi.usdTry: 'Amerikan Doları',
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
      FiyatKaynagi.xauUsd: 'Altın (Ons)',
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
  ///
  /// Eşleştirme Türkçe-güvenlidir (`trKatla`): "turk hava" Türk Hava
  /// Yolları'nı, "altin" Gram Altın'ı bulur. Önbellek anahtarı da katlanmış
  /// sorgudur — "ALTIN" ve "altın" aynı sonucu paylaşır.
  Future<List<SymbolHit>> search(String query) async {
    final k = trKatla(query.trim());
    if (k.isEmpty) return defaults;
    // Kod karşılaştırmaları (fon kodu, kripto kodu) ASCII büyük harfle.
    final q = k.toUpperCase();

    // Bayrak önbellek anahtarına girer: oturum içinde açılırsa eski
    // (ABD'siz) sonuç dönmesin. Kapalıyken anahtar birebir eski.
    final anahtar = _anahtar(k);
    final cached = _cache[anahtar];
    if (cached != null) return cached;

    // Yerleşik listeler + TEFAS fonları PARALEL aranır.
    //
    // Fonlar ayrı bir katman çünkü kaynakları farklı: `bankFunds` sabiti
    // yalnızca görünen ADLARI tutar, TEFAS kodu yoktur — fiyat/geçmiş
    // çekmek için `TEFAS:AFA` gibi bir koda ihtiyaç var ve o yalnızca
    // `TefasService`'in canlı listesinde bulunur. Sabit listeyi kullanmak
    // aramada fon gösterip grafikte "veri yok" demeye yol açardı.
    final results = await Future.wait([
      Future.value(_yerlesikVeAbd(k)),
      _searchKripto(q),
      _searchFunds(k),
      _searchEurobond(k),
    ]);
    final local = <SymbolHit>[
      ...results[0],
      ...results[1],
      ...results[2],
      ...results[3],
    ];

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
        _cache[anahtar] = hit;
        return hit;
      }
    }

    _cache[anahtar] = local;
    return local;
  }

  /// Yalnızca yerleşik listeler — ağ yok, ANINDA.
  ///
  /// [search] fon ve kripto katmanlarını da bekler; ilk fon listesi ağdan
  /// gelirken (soğuk önbellek) bu saniyeler sürebilir. Arama ekranı o arada
  /// boş durmasın diye hisse/altın/döviz sonuçlarını hemen bundan gösterir,
  /// tam sonuç gelince yerine koyar. Önbellekte tam sonuç varsa o döner.
  List<SymbolHit> yerelAra(String query) {
    final k = trKatla(query.trim());
    if (k.isEmpty) return defaults;
    return _cache[_anahtar(k)] ?? _yerlesikVeAbd(k);
  }

  /// Yerleşik listeler; bayrak açıksa ARKALARINA ABD kataloğu.
  static List<SymbolHit> _yerlesikVeAbd(String k) {
    final yerli = _searchBuiltIn(k);
    if (!_abdAcik) return yerli;
    return [...yerli, ..._searchAbd(k)];
  }

  /// ABD kataloğunda arar. Sıra yerleşik listeyle aynı kural: sembolü
  /// sorguyla başlayan önde, sonra adı başlayan. Katalog ~200 kâğıt;
  /// "a" gibi kısa sorguda listeyi boğmasın diye 20 ile sınırlı.
  static List<SymbolHit> _searchAbd(String k) {
    final hits = _abd.where((h) => _abdAnahtar[h.ticker]!.contains(k)).toList();
    int sira(SymbolHit h) {
      final t = h.ticker.toLowerCase();
      if (t == k) return 0;
      if (t.startsWith(k)) return 1;
      if (trKatla(h.name).startsWith(k)) return 2;
      return 3;
    }

    hits.sort((a, b) {
      final d = sira(a) - sira(b);
      if (d != 0) return d;
      return a.ticker.compareTo(b.ticker);
    });
    return hits.take(20).toList();
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

  static List<KriptoKatalogOgesi>? _kriptoKatalog;
  static DateTime? _kriptoKatalogZamani;

  /// Kripto kataloğunda arar (`kriptoAra`: kod tam → kod öneki → ad).
  ///
  /// Katalog saatte bir değişir; 30 dk önbellek her tuşta sunucuya gitmeyi
  /// önler. Hata (oturum yok, ağ yok) boş döner — hisse/fon araması
  /// kripto yüzünden düşmemeli.
  Future<List<SymbolHit>> _searchKripto(String q) async {
    if (DemoModu.aktif) return const []; // Katalog sunucuda (F1).
    try {
      final simdi = DateTime.now();
      if (_kriptoKatalog == null ||
          simdi.difference(_kriptoKatalogZamani!) > const Duration(minutes: 30)) {
        _kriptoKatalog = await SupabaseService.instance.kriptoKatalogu();
        _kriptoKatalogZamani = simdi;
      }
      return [
        for (final o in kriptoAra(_kriptoKatalog!, q).take(10))
          SymbolHit(ticker: kriptoSembolu(o.kod), name: o.gorunenAd, source: 'Kripto'),
      ];
    } catch (e) {
      if (kDebugMode) debugPrint('Kripto araması başarısız: $e');
      return const [];
    }
  }

  /// Eurobond kataloğunda ad ya da ISIN ile arar. [k] katlanmış sorgudur.
  ///
  /// Bayrak kapalıyken HİÇ istek atılmaz. Katalog günde bir değişir; 30 dk
  /// önbellek kripto katmanıyla aynı. Hata boş döner — tahvil araması
  /// hisse/fon aramasını düşürmemeli.
  Future<List<SymbolHit>> _searchEurobond(String k) async {
    if (!_eurobondAcik || DemoModu.aktif) return const [];
    try {
      final simdi = DateTime.now();
      if (_eurobondKatalog == null ||
          simdi.difference(_eurobondKatalogZamani!) >
              const Duration(minutes: 30)) {
        _eurobondKatalog = await eurobondKatalogKaynagi();
        _eurobondKatalogZamani = simdi;
      }
      final eklenebilir =
          eklenebilirEurobondlar(_eurobondKatalog!, simdi: simdi);
      // Eşleme bu servisin katlamasıyla (`trKatla`): "turkiye" yazan
      // "Türkiye %9,875 2028"i bulmalı. `eurobondAra` yalnız küçük harfe
      // indirir; ekleme seçicisinin kuralıdır, aramanın değil.
      final bulunan = eklenebilir.where((e) =>
          trKatla(e.$1.ad).contains(k) ||
          e.$1.isin.toLowerCase().contains(k));
      return [
        for (final e in bulunan.take(10))
          SymbolHit(
            ticker: eurobondSembolu(e.$1.isin),
            name: e.$1.ad,
            source: eurobondKaynagi,
          ),
      ];
    } catch (e) {
      if (kDebugMode) debugPrint('Eurobond araması başarısız: $e');
      return const [];
    }
  }

  /// TEFAS fonlarında kod veya ada göre arar. [k] katlanmış sorgudur.
  ///
  /// `TefasService.fetchAllFunds` önbellekli: RAM'de taze liste varsa ya da
  /// disk önbelleği 24 saatten yeniyse ağa HİÇ çıkmaz. İlk çağrıda liste
  /// yoksa ağ turu olur; hata durumunda boş liste döner ve arama yalnızca
  /// fonsuz devam eder — kullanıcı hisse/altın aramaya devam edebilmeli.
  Future<List<SymbolHit>> _searchFunds(String k) async {
    try {
      final funds = await TefasService.instance.fetchAllFunds();
      final hits = <SymbolHit>[];
      for (final f in funds) {
        final code = f.code.toLowerCase();
        final ad = _fonAdKatli[f.code] ??= trKatla(f.name);
        if (!code.contains(k) && !ad.contains(k)) continue;
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
        final aStarts = ac.toLowerCase().startsWith(k) ? 0 : 1;
        final bStarts = bc.toLowerCase().startsWith(k) ? 0 : 1;
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
        SymbolHit(
            ticker: FiyatKaynagi.usdTry,
            name: 'Amerikan Doları',
            source: 'Döviz'),
        SymbolHit(
            ticker: 'THYAO.IS', name: 'Türk Hava Yolları', source: 'BIST'),
        SymbolHit(ticker: 'GARAN.IS', name: 'Garanti BBVA', source: 'BIST'),
      ];

  /// Yerleşik listelerde ada, ticker'a VEYA takma ada göre arar. [k]
  /// katlanmış sorgudur.
  static List<SymbolHit> _searchBuiltIn(String k) {
    final hits =
        _builtIn.where((h) => _builtInAnahtar[h.ticker]!.contains(k)).toList();

    // Ticker'ı sorguyla BAŞLAYANLAR öne alınır: "AK" araması
    // `AKBNK`'ı, adında "ak" geçen rastgele bir şirketten önce göstermeli.
    // Ardından ADI sorguyla başlayanlar: "turk" araması "Türk Hava
    // Yolları"nı, adının ortasında "türk" geçenden önce göstermeli.
    int sira(SymbolHit h) {
      if (h.ticker.toLowerCase().startsWith(k)) return 0;
      if (trKatla(h.name).startsWith(k)) return 1;
      return 2;
    }

    hits.sort((a, b) {
      final d = sira(a) - sira(b);
      if (d != 0) return d;
      return a.ticker.compareTo(b.ticker);
    });
    return hits;
  }

  @visibleForTesting
  static void clearCacheForTest() {
    _cache.clear();
    _fonAdKatli.clear();
    _kriptoKatalog = null;
    _kriptoKatalogZamani = null;
    _eurobondKatalog = null;
    _eurobondKatalogZamani = null;
  }
}
