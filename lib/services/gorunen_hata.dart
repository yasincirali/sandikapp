/// Kullanıcının az önce bir hata GÖRDÜĞÜ an (Ar-Ge 23 Eki 08:45 #2; yasin
/// "yap", 2026-10-23).
///
/// ## Neden
/// Değerlendirme istemi "mutlu an"da açılır ama oturumda ne yaşandığına
/// bakmıyordu: fiyat şeridi "güncellenemedi" dedikten iki dakika sonra
/// varlık ekleme bitince "sandık'ı beğendin mi?" çıkabiliyordu. Az
/// kullanıcıda mağaza puanı birkaç yorumla oluşur; o anda verilen tek bir
/// düşük puan ortalamayı belirgin düşürür.
///
/// ## Ne yazar
/// Yalnız kullanıcının ekranda gördüğü hatalar: `showAppError` diyaloğu,
/// `SandikErrorView` ve Ana sayfadaki fiyat hatası şeridi. Sessiz arka plan
/// hataları (Crashlytics non-fatal) YAZMAZ — yazsaydı istem neredeyse hiç
/// sorulmazdı (müşteri raporu 23 Eki 09:15 #2).
///
/// Bellekte durur, diske yazılmaz: süreç ölünce "oturum" da biter.
abstract final class GorunenHata {
  static int? _sonMs;

  /// Test için saat enjeksiyonu.
  static DateTime Function() now = DateTime.now;

  static void kaydet() => _sonMs = now().millisecondsSinceEpoch;

  /// Son görünen hatanın zamanı (epoch ms); bu süreçte hiç olmadıysa null.
  static int? get sonMs => _sonMs;

  static void sifirlaTest() {
    _sonMs = null;
    now = DateTime.now;
  }
}
