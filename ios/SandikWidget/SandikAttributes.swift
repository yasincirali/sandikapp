import ActivityKit
import Foundation

/// Live Activity'nin veri sözleşmesi — ana uygulama ile uzantının ORTAK tipi.
///
/// Bu dosya İKİ hedefe birden üye olmalıdır (Runner + SandikWidget). Yalnızca
/// birine üyeyse `Activity<SandikActivityAttributes>` diğer tarafta derlenmez.
///
/// ## Gizlilik değişmezi
/// Live Activity içeriği **kilit ekranında**, yani telefonu açmadan herkesin
/// görebileceği bir yüzeyde durur. `HomeWidgetService`'teki kuralın aynısı
/// burada daha da sıkı geçerlidir: yalnızca ÖZET yazılır. Varlık listesi,
/// ticker, adet, kullanıcı kimliği veya e-posta ASLA bu tipe girmez.
/// Kullanıcı bakiyeyi gizlediyse ([isHidden]) tutar hiç gönderilmez —
/// maskeleme sunum katmanında değil, KAYNAKTA yapılır ki veri cihazda
/// hiç bulunmasın.
@available(iOS 17.0, *)
struct SandikActivityAttributes: ActivityAttributes {
    /// Oturum boyunca DEĞİŞMEYEN alanlar.
    ///
    /// Not: `ActivityAttributes` protokolü değişken durumu `ContentState`
    /// adlı iç tipte arar; isim birebir böyle olmalıdır.
    public struct ContentState: Codable, Hashable {
        /// Biçimlenmiş toplam portföy değeri — ör. `₺1.482.350,80`.
        ///
        /// **Neden hazır metin, sayı değil:** Türkçe biçim (binlik `.`,
        /// ondalık `,`) tek bir yerde, Dart `tr_format` helper'larında
        /// üretilir. Swift tarafında `NumberFormatter` ile yeniden kurmak
        /// aynı kuralın ikinci bir kopyasını yaratır ve iki kopya
        /// kaçınılmaz olarak ayrışır.
        var totalText: String

        /// Günlük net değişim — ör. `+₺35.420,00`. İşaret dahildir.
        var changeText: String

        /// Günlük değişim yüzdesi — ör. `%2,45`. İşaret HARİÇ; yön ayrıca
        /// [isPositive] ile taşınır (bkz. aşağıdaki erişilebilirlik notu).
        var changePctText: String

        /// Yön. Renk seçimini VE ok işaretini birlikte sürer.
        ///
        /// Marka kuralı: kazanç/kayıp yalnızca renkle anlatılamaz — renk
        /// körlüğü için yön her zaman ▲/▼ ile de gösterilir. Bu yüzden
        /// tek bir bool iki sunum kararını birden besler.
        var isPositive: Bool

        /// Kullanıcı bakiyeyi gizlemişse `true` — tutar alanları `••••••`
        /// olarak gelir, gerçek rakam cihaza hiç ulaşmaz.
        var isHidden: Bool

        /// Son güncelleme — `HH:mm`, ör. `18:04`.
        var updatedAtText: String

        /// Seansın planlanan bitişi. Kilit ekranında geri sayım göstermek
        /// için değil, "seans sürüyor mu" kararını uzantıda da verebilmek
        /// için taşınır.
        var sessionEndsAt: Date

        /// Gün içi portföy serisi — **normalize edilmiş** (0…1) noktalar.
        ///
        /// **Neden ham tutar değil:** kilit ekranı telefonu açmadan
        /// görülebilir. Ham TL değerleri göndermek, `showAmounts` kapalıyken
        /// bile portföy büyüklüğünü grafik ekseninden okunabilir kılardı.
        /// Normalize seri yalnızca ŞEKLİ taşır: gün içinde yükseldi mi,
        /// düştü mü. Tutar bilgisi cihazın bu yüzeyine hiç ulaşmaz.
        ///
        /// Boş dizi "grafik çizme" demektir (veri yok ya da tek nokta —
        /// tek noktalı bir "çizgi" yanıltıcı olurdu).
        var sparkline: [Double]

        /// Tutarlar kilit ekranında gösterilsin mi?
        ///
        /// **iOS kilitli/açık ayrımı VERMEZ.** ActivityKit'te böyle bir
        /// sinyal yoktur; aynı `ContentState` iki durumda da render edilir.
        /// Bu yüzden "kilitliyken gizle, açılınca göster" davranışı teknik
        /// olarak kurulamaz — bunun yerine kullanıcı tercihi taşınır
        /// (Ayarlar → "Kilit ekranında tutarı göster", varsayılan KAPALI).
        ///
        /// Kapalıyken tutar alanları kaynakta maskelenir; yüzde ve grafik
        /// görünmeye devam eder çünkü onlar portföy büyüklüğünü ele vermez.
        var showAmounts: Bool

        /// BIST işlem saatleri içinde miyiz?
        ///
        /// Kullanıcının seçtiği GÖSTERİM penceresinden ayrıdır: 7/24
        /// gösterim seçilse bile gece fiyat hareket etmez. Bu bayrak
        /// olmadan donuk rakam "bozuk" gibi görünürdü — banner bunun
        /// yerine "Piyasa kapalı" der ve canlılık noktası griye döner.
        var isMarketOpen: Bool
    }

    /// Seans etiketi — ör. `BIST Seansı`. Oturum boyunca sabittir.
    var sessionName: String
}
