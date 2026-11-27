/// Uygulama DIŞI yüzeylerin (tek varlık widget'ı, Canlı Etkinlik) uygulama
/// kapalıyken kendini tazeleme sıklığı — kullanıcı seçimi (yasin 27 Kas
/// 2026: "müşteri yenileme zamanını seçebilsin, şarjı yiyebileceği
/// dipnotla açıklansın").
///
/// ## Neden yalnız bu iki yüzey
/// Portföy widget'ı uygulama kapalıyken kendini tazeleyemez: tutar lot
/// toplama + kur çevrimi ister ve o hesap yalnız uygulamada yaşar (bkz.
/// `HomeWidgetService`). Sunucudan kendi fiyatını çeken tek ana ekran
/// yüzeyi tek varlık widget'ıdır (altın, döviz, kripto); Canlı Etkinlik'i
/// ise sunucu push'lar. Seçim bu ikisine gider; arayüz dipnotu bunu söyler.
///
/// ## Neden bu aralıklar (sistemin garanti ettiği kadar vaat)
///   * Widget: WidgetKit günde ~40–70 yenileme tanır; 15 dk gündüz bu
///     bütçenin içinde kalır, daha sıkı seçenek sistemce kısılırdı.
///     Android alarmı kesin değildir (`AlarmManager.set`, RTC). Varsayılan
///     30 dk = bugüne kadarki davranış.
///   * Canlı Etkinlik: sunucu cron'u dakikada bir döner; dakikalık ileri
///     taşıma (`canli_etkinlik_dakikalik`) kapalıysa en sık 5 dk'dır, o
///     yüzden "Her dakika" yalnız bayrak açıkken sunulur. Varsayılan en sık
///     seçenek = bugüne kadarki davranış; sunucuya hiçbir şey yazılmaz.
library;

/// Tek varlık widget'ı seçenekleri (dakika).
const widgetYenilemeSecenekleri = [15, 30, 60];

/// Bugüne kadarki davranış (iOS `tazelemeAraligi`, Android
/// `TAZELEME_ARALIGI_MS`).
const widgetYenilemeVarsayilan = 30;

/// Canlı Etkinlik seçenekleri (dakika). Sunucu yalnız 5'in katlarını ve
/// 1'i tanır (`_shared/canli_etkinlik_yenileme.ts`).
List<int> canliEtkinlikYenilemeSecenekleri({required bool dakikalik}) =>
    dakikalik ? const [1, 5, 15] : const [5, 15, 30];

/// Kayıtlı tercih [secenekler] içinde değilse (0 = hiç seçilmedi, ya da
/// bayrak kapanınca "1" artık sunulmuyor) eşit ya da büyük ilk seçeneğe
/// oturur; hiç seçilmediyse en sık seçenek — bugünkü davranış.
int yenilemeEtkin(int tercih, List<int> secenekler) {
  if (tercih <= 0) return secenekler.first;
  for (final s in secenekler) {
    if (s >= tercih) return s;
  }
  return secenekler.last;
}
