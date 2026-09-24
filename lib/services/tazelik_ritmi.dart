/// Yenileme ritimlerinin TEK kaynağı.
///
/// ## Neden bu dosya var (kullanıcı kararı, 2026-09-23)
/// *"Fiyat yenileme sıklıklarımızı da senkron hale getirmeliyiz, bu sayede
/// bir ekranda altın fiyatıyla diğer ekranda aynı olmalı."*
///
/// Beş ayrı ritim, beş ayrı yerde tanımlıydı ve hiçbiri diğerini bilmiyordu:
///
/// | Yüzey | Ritim | Nerede |
/// |---|---|---|
/// | Kotasyon önbelleği | 45 sn | `PriceService._quoteTtl` (private) |
/// | Piyasa bandı | 30 sn | `PiyasaSeridi.yenilemeAraligi` |
/// | Performans gün içi | 30 sn | `seriler.dart` içinde ham literal |
/// | Bugün kartı | 30 sn | `BugunKarti._seriTazelikPenceresi` (private) |
/// | Gün içi seri önbelleği | 5 dk | `IntradaySeriesCache.minInterval` |
///
/// ### Ölçülen arıza: TTL ile poll AYNI FAZDA DEĞİLDİ
/// Ekranlar 30 sn'de bir soruyor ama kotasyon önbelleği 45 sn tutuyordu.
/// Oran 1,5 — tam sayı değil. Sonuç, üç tick'te bir tekrarlayan bir vuruş
/// deseni:
///
/// ```
///   t=  0 sn  AĞ (taze çekildi)
///   t= 30 sn  ÖNBELLEK (yaş 30 sn)
///   t= 60 sn  ÖNBELLEK (yaş 15 sn)   ← 45'i aşmadı
///   t= 90 sn  AĞ (taze)
/// ```
///
/// Önbellek paylaşımlı (singleton) olduğu için AYNI ANDA soran iki yüzey
/// aynı fiyatı görür. Ama TTL sınırının iki yanına düşen iki soru farklı
/// yanıt alır: `t=44` önbellekten eski fiyatı, `t=46` ağdan yenisini alır.
/// İki ekran iki saniye arayla farklı altın fiyatı gösterebilir.
///
/// ### Kural
/// Tüm ritimler [temel]'in TAM KATIDIR. Böylece tick'ler hizalanır ve bir
/// sorunun önbellekten mi ağdan mı döndüğü yüzeye göre DEĞİŞMEZ.
///
/// `fiyat_kaynagi.dart` ile aynı disiplin: orası "hangi seri", burası
/// "ne sıklıkta". Yeni bir yüzey kendi periyodunu TANIMLAMAZ, buradan okur.

library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'crash_reporter.dart';

/// Uygulamanın yenileme ritimleri — hepsi [temel]'in katı.
abstract final class TazelikRitmi {
  const TazelikRitmi._();

  /// Taban ritim. Diğer her şey bunun tam katıdır.
  ///
  /// 30 saniye: BIST/döviz kotasyonlarının anlamlı biçimde değiştiği en kısa
  /// aralık. Daha sık çekmek ölçülebilir bir bilgi kazandırmaz, yalnızca
  /// ağ trafiği ve pil tüketir.
  static const Duration temel = Duration(seconds: 30);

  /// Kotasyon önbelleğinin ömrü (`PriceService`).
  ///
  /// **[temel] ile AYNI olmalı, daha uzun DEĞİL.** Eskiden 45 sn'ydi ve
  /// ekranlar 30 sn'de bir sorduğu için yukarıdaki vuruş deseni oluşuyordu.
  ///
  /// Eşit olunca davranış öngörülebilir: her tick önbelleği bayat bulur ve
  /// tazeler; iki yüzey aynı tick'te aynı kotasyonu paylaşır. Ağ trafiği
  /// ARTMAZ çünkü önbellek paylaşımlıdır — ilk soran çeker, diğerleri aynı
  /// turdan okur.
  static const Duration kotasyonOmru = temel;

  /// Ön yüz yüzeylerinin yenileme aralığı (piyasa bandı, Performans gün içi
  /// tick'i, Bugün kartı serisi).
  static const Duration yuzey = temel;

  /// Gün içi SERİ önbelleğinin ömrü (`IntradaySeriesCache`).
  ///
  /// Kotasyondan uzun tutulur ([temel] × 10 = 5 dk): gün içi seri saatlik
  /// kovalara bölünmüş GEÇMİŞ veridir ve her 30 saniyede yeniden çekmek
  /// aynı noktaları tekrar indirmek olurdu. Ana ekran widget'ı ile Live
  /// Activity da bu ritimle hizalı (5 dk'lık push döngüsü).
  ///
  /// Ekranda DURAN yüzey daha tazesini isteyebilir (`azamiYas`) — o yol
  /// [yuzey] kullanır, yani kullanıcının baktığı şey 30 saniyede bir
  /// tazelenir, arka plandaki yüzeyler 5 dakikada bir.
  static const Duration gunIciSeriOmru = Duration(minutes: 5);

  /// Serinin ucu bu süreden eskiyse canlı değer son noktayı EZMEZ, ayrı bir
  /// nokta olarak EKLENİR (`DailySummary.dayValues`).
  ///
  /// [gunIciSeriOmru] ile eşit: seri o yaşa gelmişse zaten tazelenecektir,
  /// dolayısıyla "ucu bayat" durumu tam o sınırda başlar.
  static const Duration canliUcAzamiGecikme = gunIciSeriOmru;

  /// Uygulamanın TEK nabzı — tüm yüzeyler aynı ANDA tazelenir.
  ///
  /// ## Neden gerekli (kullanıcı isteği, 2026-09-23)
  /// *"Günlük grafik, özet, ana sayfa kartları tutarlı ve senkron şekilde
  /// yenilenmeli, veri tutarsızlığı olmamalı."*
  ///
  /// Ritimleri eşitlemek YETMEZ. Her yüzey kendi `Timer`'ını mount anında
  /// kuruyordu, yani hepsi 30 sn'de bir ama FARKLI FAZDA çalışıyordu:
  ///
  /// ```
  ///   Ana sayfa açıldı  t=0   → Bugün kartı tick: 0, 30, 60, 90…
  ///   Performans'a geçti t=12  → Performans tick: 12, 42, 72, 102…
  /// ```
  ///
  /// İki yüzey 12 saniye farklı anın verisini gösteriyordu. Gün başı
  /// serinin ilk noktasından geldiği ve canlı uç o andaki fiyattan
  /// hesaplandığı için, iki kart arasında geçici ama gerçek bir fark
  /// oluşuyordu.
  ///
  /// Tek nabız bunu yapısal olarak kapatır: sayacı uygulama tutar,
  /// yüzeyler yalnızca DİNLER. Hangi ekrandan girildiğinden bağımsız
  /// olarak herkes AYNI tick'te tazelenir.
  ///
  /// Ekranda olmayan yüzey dinleyicisini kaldırır (`dispose`), yani
  /// görünmeyen kart için iş yapılmaz.
  static final TazelikNabzi nabiz = TazelikNabzi._(yuzey);

  /// Ritimlerin [temel]'e hizalı olup olmadığı — test ve doğrulama için.
  ///
  /// Hizasız bir ritim eklenirse `tazelik_ritmi_test` kırılır: bu dosyanın
  /// varlık sebebi tam olarak o hizanın korunmasıdır.
  static bool hizali(Duration d) =>
      d.inMilliseconds % temel.inMilliseconds == 0;

  /// Süren bir fiyat turu varsa bitmesini bekler — en fazla [enFazla].
  ///
  /// ## Neden (kullanıcı bildirimi, 2026-09-24, soğuk açılış)
  /// *"Ana sayfa günlük ile Performans › grafik ve özet arasında, uygulama
  /// kill edildikten sonraki ilk açılışta fark var."* Ölçüldü: Bugün kartı
  /// −₺5.640 / %0,50, Performans −₺7.424 / %0,66 — aynı canlı uç, aynı
  /// katkı, FARKLI gün başı (₺1.073.410'a karşı ₺1.075.195).
  ///
  /// Nabız yolu 2026-09-24'te "önce tek fiyat turu, SONRA dinleyiciler"
  /// sırasına bağlandı ([TazelikNabzi.fiyatTuruBagla]); açılış yolu bu
  /// sıranın dışında kalmıştı. Bugün kartı mount olur olmaz seriyi
  /// çekiyor, `MainNavigationScreen`'in açılış turu ise aynı anda ağda.
  /// Altın/döviz gün başı `PriceService.gunlukReferansFiyat`'tan gelir ve o
  /// bellek YALNIZCA kotasyon çekilince dolar (diskten geri yüklenmez —
  /// `_birincilYukle` yalnızca fiyatı taşır, yüzdeyi değil). Turdan önce
  /// kurulan seri referansı bulamaz, eski çarpan yoluna düşer ve gün başı
  /// Yahoo'nun ilk noktasından çıkar; Performans ise kullanıcı oraya
  /// geçene kadar tur bitmiş olduğundan yurt içi referansı alır. Kart bir
  /// sonraki nabızda (`zorla`) toparlanıyordu — yani fark ilk 30 sn'de
  /// görünüp kayboluyordu; kullanıcı tam o pencereye bakıyordu.
  ///
  /// Kural: gün içi seriyi çeken HER yüzey (Bugün kartı, Performans GÜNLÜK,
  /// varlık ekranı GÜNLÜK) önce süren turu bekler. Tur yoksa anında döner.
  /// Asılı turda [enFazla] sonra eldeki fiyatla devam edilir — nabızdaki
  /// "asılı tur yüzeyleri en fazla bir aralık bekletir" kuralının aynısı;
  /// turun hatası da burada yutulur, sahibi (`refreshPrices`) raporlar.
  /// Saf: bekleyecek future'ı çağıran verir (`PortfolioNotifier
  /// .fiyatTurunuBekle`), böylece provider kurmadan sınanır.
  static Future<void> turuBekle(Future<void>? suren,
      {Duration enFazla = yuzey}) async {
    if (suren == null) return;
    try {
      await suren.timeout(enFazla);
    } catch (_) {
      // Hata ve zaman aşımı aynı kapıya çıkar: eldeki fiyatla devam.
    }
  }

  /// [turuBekle] + BİR KARE — `widget.state` üzerinden defter okuyan
  /// yüzeyler için.
  ///
  /// ## Neden bir kare (emülatörde ölçüldü, 2026-09-24, ikinci tur)
  /// Yalnızca turu beklemek yetmedi: kill sonrası açılışta kart yine
  /// −₺6.129, Performans −₺7.424 gösterdi ve ~30 sn sonra eşitlendi.
  ///
  /// Tur bitince defteri yayınlar (`state = AsyncData(...)`); ama bu
  /// yayın widget ağacına ancak BİR SONRAKİ KAREDE iner
  /// (`didUpdateWidget`). `await`in devamı ise turun future'ı çözülür
  /// çözülmez, o kareden ÖNCE koşar: `widget.state` hâlâ turdan önceki
  /// kopyadır — soğuk açılışta DB'den gelen, saatler önceki fiyatlar.
  /// Motor gün başını o fiyatlardan kalibre eder (`altinKalibrasyonu`,
  /// `dovizUrunBirimi` → `a.currentPrice`), yani seri bir tur geride
  /// kurulur. Nabız yolunda da aynı: dinleyiciler turun hemen ardından,
  /// kare gelmeden çağrılır; piyasa açıkken kart her nabızda bir tur
  /// önceki fiyatın gün başına bakıyordu — "bir süre farklı, sonra aynı,
  /// sonra yine farklı" bildirimlerinin kalan ayağı. Piyasa kapalıyken
  /// ikinci turdan itibaren fiyat değişmediği için fark 30 sn'de kayboldu.
  ///
  /// `endOfFrame` boşta bir kare PLANLAR (SDK), yani yayın olmasa da en
  /// fazla bir kare beklenir. Provider'ı doğrudan okuyan yüzey (varlık
  /// ekranı `_canli`) buna muhtaç değildir, [turuBekle] yeter.
  static Future<void> turuVeKareyiBekle(Future<void>? suren,
      {Duration enFazla = yuzey}) async {
    await turuBekle(suren, enFazla: enFazla);
    try {
      // Arka planda kare gelmez; nabız zaten durur ama asılı kalınmasın.
      await WidgetsBinding.instance.endOfFrame.timeout(yuzey);
    } catch (_) {
      // Kare gelmediyse eldeki defterle devam.
    }
  }
}

/// [TazelikRitmi.nabiz] — uygulama ömrünce tek sayac.
///
/// `ForegroundPoller` ile aynı yaşam döngüsü disiplini: arka planda
/// durur, öne gelince HEMEN bir tur atar (kullanıcı bayat rakam
/// görmesin) ve sayacı yeniden kurar.
///
/// Dinleyici YOKSA sayac çalışmaz — hiçbir yüzey açık değilken
/// boşuna tur atmak pil tüketirdi.
class TazelikNabzi with WidgetsBindingObserver {
  TazelikNabzi._(this.aralik);

  /// Nabız aralığı — [TazelikRitmi.yuzey].
  final Duration aralik;

  final Set<VoidCallback> _dinleyiciler = {};
  Timer? _sayac;
  bool _gozlemciEkli = false;

  /// Her nabızda dinleyicilerden ÖNCE koşan tek fiyat turu.
  Future<void> Function()? _fiyatTuru;

  /// Nabzın fiyat turunu bağlar — uygulamada TEK sahibi vardır
  /// (`MainNavigationScreen`). Dönüş değeri bağı çözer.
  ///
  /// ## Neden (kullanıcı isteği, 2026-09-24)
  /// *"Anasayfa günlük, varlık günlük performans, Performans günlük'te
  /// grafik ve özet ... senkron şekilde yenilenmeliler."*
  ///
  /// Nabız yüzeyleri aynı ANDA uyandırıyordu ama fiyatı kimin tazelediği
  /// belli değildi: turu yalnızca Performans ekranı, o da yalnızca GÜNLÜK
  /// seçiliyken atıyordu. Performans başka dönemdeyken defterdeki fiyat
  /// hiç tazelenmiyor; piyasa bandı ise kendi kotasyonunu her nabızda
  /// çekiyordu — bantta bir altın fiyatı, Bugün kartında daha eskisi.
  /// Varlık ekranı nabzı hiç dinlemiyordu.
  ///
  /// Şimdi sıra yapısal: önce fiyat turu (bitene kadar, en fazla bir
  /// [aralik]), SONRA dinleyiciler. Her yüzey aynı turun fiyatını okur;
  /// seriyi çeken yüzey de o turdan sonra çeker. Tur kotasyon önbelleğini
  /// atlar: önbellek damgası ağ yanıtıyla atıldığı için ömrü nabızla eşit
  /// olan önbellek her İKİNCİ nabızda hâlâ taze sayılıyor ve fiyat fiilen
  /// 60 sn'de bir tazeleniyordu.
  ///
  /// Bağ sayacı BAŞLATMAZ — nabız, ona bakan bir yüzey varken atar.
  VoidCallback fiyatTuruBagla(Future<void> Function() tur) {
    _fiyatTuru = tur;
    return () {
      if (identical(_fiyatTuru, tur)) _fiyatTuru = null;
    };
  }

  /// Bu yüzey her nabızda [geriCagri]'yı çağırsın.
  ///
  /// İlk dinleyici geldiğinde sayac başlar. Dönüş değeri, çağıranın
  /// `dispose`'unda çağırması gereken kaldırma işlevidir.
  VoidCallback dinle(VoidCallback geriCagri) {
    _dinleyiciler.add(geriCagri);
    _baslat();
    return () {
      _dinleyiciler.remove(geriCagri);
      if (_dinleyiciler.isEmpty) _durdur();
    };
  }

  void _baslat() {
    if (!_gozlemciEkli) {
      WidgetsBinding.instance.addObserver(this);
      _gozlemciEkli = true;
    }
    _kur();
  }

  void _kur() {
    _sayac?.cancel();
    if (_dinleyiciler.isEmpty) return;
    _sayac = Timer.periodic(aralik, (_) => _at());
  }

  void _durdur() {
    _sayac?.cancel();
    _sayac = null;
    if (_gozlemciEkli) {
      WidgetsBinding.instance.removeObserver(this);
      _gozlemciEkli = false;
    }
  }

  Future<void> _at() async {
    final tur = _fiyatTuru;
    if (tur != null) {
      try {
        // Asılı kalan tur yüzeyleri durdurmasın: en fazla bir aralık
        // beklenir, sonra dinleyiciler eldeki fiyatla tazelenir.
        await tur().timeout(aralik);
      } catch (_) {
        // Turun hatası sahibinde raporlanır (`refreshPrices`); burada
        // yalnızca sıranın devam etmesi önemli.
      }
    }
    // Kopya üzerinde gezilir: bir dinleyici tepki olarak kendini
    // kaldırırsa (örn. `dispose`) koleksiyon döngü sırasında değişmesin.
    for (final d in _dinleyiciler.toList()) {
      d();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Öne gelince HEMEN bir tur: arka planda geçen süre kadar bayat
      // rakam gösterilmemeli.
      // `_at` hatayı kendi içinde yutar; yine de başıboş bırakılmaz.
      CrashReporter.arkaPlan(_at(), reason: 'TazelikNabzi.resumed');
      _kur();
    } else {
      _sayac?.cancel();
      _sayac = null;
    }
  }

  /// Testler için: nabzı elle at. Fiyat turu bağlı değilse dinleyiciler
  /// eşzamanlı koşar; bağlıysa dönen future tur + dinleyicilerle biter.
  @visibleForTesting
  Future<void> atForTest() => _at();

  /// Testler için: kaylı dinleyici sayısı.
  @visibleForTesting
  int get dinleyiciSayisi => _dinleyiciler.length;
}
