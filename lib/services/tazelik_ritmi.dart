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

  /// Ritimlerin [temel]'e hizalı olup olmadığı — test ve doğrulama için.
  ///
  /// Hizasız bir ritim eklenirse `tazelik_ritmi_test` kırılır: bu dosyanın
  /// varlık sebebi tam olarak o hizanın korunmasıdır.
  static bool hizali(Duration d) =>
      d.inMilliseconds % temel.inMilliseconds == 0;
}
